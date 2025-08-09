from asyncio import run
from random import randint
from time import time, sleep

from pysnmp.entity.engine import SnmpEngine
from pysnmp.error import PySnmpError
from pysnmp.hlapi.v3arch import UdpTransportTarget, ContextData, CommunityData, walk_cmd
from pysnmp.smi.rfc1902 import ObjectType, ObjectIdentity

from influx_writer import send_data_to_influx

# Gets Unraid system health via SNMP v2c walk commands

# These Tuples define the IP address from which to fetch data and the tag "host" stored in InfluxDB for each.
# This way, if the IP address changes, an update can be made to keep the data going to the same tag in Influx
ip_addresses_to_influx_host = [("poorbox.brad", "poorbox")]

# This Dict defines the SNMP OIDs with which to call snmpwalk, alongside friendly names
# snmpwalk -v 2c -O n -c public poorbox.brad nsExtendOutLine specifically -O n can be used to find OID from human name
# double-colon aka NET-SNMP-EXTEND-MIB::nsExtendOutLine means the MIB file is NET-SNMP-EXTEND-MIB, category is right
walk_oid_to_mib_name = {".1.3.6.1.4.1.8072.1.3.2.4.1.2.": "NET-SNMP-EXTEND-MIB::nsExtendOutLine",
                        ".1.3.6.1.2.1.25.3.3.1.2.": "HOST-RESOURCES-MIB::hrProcessorLoad"}

# This Dict defines the sublevels of OID under each walk, and the type of data they represent. Mini MIB
# These were found by comparing snmpwalk outputs with and without the -O OUTOPTS / n:  print OIDs numerically
influx_type_to_oid_dict = {"memInfo": "1.3.6.1.4.1.8072.1.3.2.4.1.2.7.109.101.109.105.110.102.111.",
                           "diskFree": "1.3.6.1.4.1.8072.1.3.2.4.1.2.8.100.105.115.107.102.114.101.101.",
                           "diskTemp": "1.3.6.1.4.1.8072.1.3.2.4.1.2.8.100.105.115.107.116.101.109.112.",
                           "shareFree": "1.3.6.1.4.1.8072.1.3.2.4.1.2.9.115.104.97.114.101.102.114.101.101.",
                           "cpuPercent": "1.3.6.1.2.1.25.3.3.1.2."}

# Define the "measurement" category under which the data fields will be stored
influx_measurement_name = "unraid"
# Define the port where SNMP is running on the target devices
snmp_port_number = 161


# Given an IP address and an OID to walk, fetch the OID values using the SNMP library's WALK command
async def fetch_data(ip_address, walk_oid):
    snmp_engine = SnmpEngine()
    # For SNMPV3, replace CommunityData("public") with UsmUserData("someSNMPuser")
    # lookupMib=False will leave full OID numeric representation. Otherwise, it might be SNMPv2-SMI::snmpModules.16.1.5.
    # lexicographicMode=False stops the walk when leaving the defined OID subsection
    # Taken from library examples
    objects = walk_cmd(snmp_engine,
                       CommunityData("public"),
                       await UdpTransportTarget.create((ip_address, snmp_port_number)),
                       ContextData(),
                       ObjectType(ObjectIdentity(walk_oid)),
                       lookupMib=False,
                       lexicographicMode=False)
    # Walk returns a list of tuples, each containing ErrorIndication, ObjectType, and more
    walk_response_objects = [item async for item in objects]
    # Copied from quick start https://docs.lextudio.com/pysnmp/v7.1/quick-start
    snmp_engine.close_dispatcher()
    return walk_response_objects


def validate_and_add_field_set_to_line_protocol_string_list(
        influx_host_name, influx_type, field_set, epoch_time_seconds, line_protocol_string_list):
    # Skip adding the field set to output if it is empty
    if len(field_set) < 1:
        print("No valid fields found for {}, skipping submission".format(influx_type))
        return
    # Format the data into line protocol with the tags, fields, and time for the record
    line_protocol_string = "unraid,host={},type={} {} {}".format(
        influx_host_name, influx_type, ",".join(field_set), epoch_time_seconds)
    # Add the line protocol into the caller's list
    line_protocol_string_list.append(line_protocol_string)
    print("Completed {} parsing: {}".format(influx_type, line_protocol_string))


def assemble_line_protocol_from_data_dict(walk_result_parsed_dict, influx_host_name):
    # Instantiate a list to store lines of Line Protocol to write to Influx
    line_protocol_string_list = []
    # Get the current time since Epoch in seconds, which is used when writing lines to Influx
    epoch_time_seconds = int(time())
    # Each Influx Type requires special handling to parse and arrange its values into a line protocol list
    for influx_type, influx_type_oid in influx_type_to_oid_dict.items():
        walk_result_parsed_dict_keys_to_remove = []
        match influx_type:
            case "memInfo" | "diskFree" | "shareFree":
                field_set = []
                # Find all items in the walk result dict whose oid contains the selected oid
                for walk_result_oid, walk_result_value in walk_result_parsed_dict.items():
                    if influx_type_oid in walk_result_oid:
                        # Parse matching item's value after marking the item for removal from the source dict
                        walk_result_parsed_dict_keys_to_remove.append(walk_result_oid)
                        value_split = walk_result_value.split(":")
                        # Handle if the formatting was unexpected, skipping submission and printing
                        if len(value_split) != 2:
                            print("Unexpected format in {} line, skipping {}".format(influx_type, walk_result_value))
                            continue
                        # Add the parsed value to the fieldset
                        field_set.append("{}={}".format(value_split[0], int(value_split[1])))
                # The field set is now populated, so the final Line Protocol for this data can be generated
                # Example: unraid,host=poorbox,type=memInfo Dirty=0,Committed_AS=898048000 1754713059
                # Example: unraid,host=poorbox,type=diskFree boot=74170368,disk1=3892485283840 1754713059
                # Example: unraid,host=poorbox,type=shareFree Files=74170368,Backups=3892485283840 1754713059
                validate_and_add_field_set_to_line_protocol_string_list(
                    influx_host_name, influx_type, field_set, epoch_time_seconds, line_protocol_string_list)
            case "diskTemp":
                # Disk Temp positive values communicate temperature, while negative values communicate standby state
                # The diskActive Influx type thus also comes from diskTemp and must be recorded
                field_set_temperature = []
                field_set_active = []
                # Find all items in the walk result dict whose oid contains the selected oid
                for walk_result_oid, walk_result_value in walk_result_parsed_dict.items():
                    if influx_type_oid in walk_result_oid:
                        # Parse matching item's value after marking the item for removal from the source dict
                        walk_result_parsed_dict_keys_to_remove.append(walk_result_oid)
                        value_split = walk_result_value.split(":")
                        # Handle if the formatting was unexpected, skipping submission and printing
                        if len(value_split) != 2:
                            print("Unexpected format in {} line, skipping {}".format(influx_type, walk_result_value))
                            continue
                        # Add the parsed value to the temperature fieldset
                        field_set_temperature.append("{}={}".format(value_split[0], int(value_split[1])))
                        # Calculate active state. -1 is error, 0 is standby, 1 is active/idle
                        if int(value_split[1]) > 0:
                            field_set_active.append("{}=1".format(value_split[0]))
                        elif int(value_split[1]) == -2:
                            field_set_active.append("{}=0".format(value_split[0]))
                        else:
                            field_set_active.append("{}=-1".format(value_split[0]))
                # The field set is now populated, so the final Line Protocol for this data can be generated
                # Example: unraid,host=poorbox,type=diskTemp HGST_HUH721212ALE604_5PHGGGF=-2 1754713059
                validate_and_add_field_set_to_line_protocol_string_list(
                    influx_host_name, influx_type, field_set_temperature, epoch_time_seconds, line_protocol_string_list)
                validate_and_add_field_set_to_line_protocol_string_list(
                    influx_host_name, "diskActive", field_set_active, epoch_time_seconds, line_protocol_string_list)
            case "cpuPercent":
                # cpuPercent reports using zero-indexed CPU core numbers
                field_set = []
                core_count = 0
                # Find all items in the walk result dict whose oid contains the selected oid
                for walk_result_oid, walk_result_value in walk_result_parsed_dict.items():
                    if influx_type_oid in walk_result_oid:
                        # Parse matching item's value after marking the item for removal from the source dict
                        walk_result_parsed_dict_keys_to_remove.append(walk_result_oid)
                        # Handle if the formatting was unexpected, skipping submission and printing
                        if not walk_result_value.isdigit():
                            print("Unexpected format in {} line, skipping {}".format(influx_type, walk_result_value))
                            continue
                        # Add the value to the fieldset
                        field_set.append("{}={}".format(core_count, walk_result_value))
                        core_count += 1
                # The field set is now populated, so the final Line Protocol for this data can be generated
                # Example: unraid,host=poorbox,type=cpuPercent 0=3,1=3,2=3,3=3 1754713059
                validate_and_add_field_set_to_line_protocol_string_list(
                    influx_host_name, influx_type, field_set, epoch_time_seconds, line_protocol_string_list)
            case _:
                print("unknown influx type:", influx_type)
        # After each round of the match case, clear items from the walk result dictionary that were processed
        for key in walk_result_parsed_dict_keys_to_remove:
            del walk_result_parsed_dict[key]
    # See if there are any remaining items in the dict and warn if so, that means there's data left unparsed
    if len(walk_result_parsed_dict) > 0:
        print("Not all values fetched from SNMP were parsed! Remaining values: {}".format(walk_result_parsed_dict))
    else:
        print("All values fetched from SNMP were parsed!")
    # All parsing has been completed and the list of line protocol can now be returned for submission prep
    return line_protocol_string_list


# Top-level Unraid data-gathering function to orchestrate all the other calls in this file
def collect_and_write_unraid_readings():
    # Instantiate a list to store lines of Line Protocol to write to Influx
    line_protocol_string_list = []
    # Iterate through each tuple of IP and host name
    for ip_to_host_tuple in ip_addresses_to_influx_host:
        current_ip = ip_to_host_tuple[0]
        influx_host_name = ip_to_host_tuple[1]
        print("\nChecking IP {} with Influx Host Name {}".format(current_ip, influx_host_name))
        walk_result_list = []
        for walk_oid, friendly_name in walk_oid_to_mib_name.items():
            try:
                # Get the data from the current IP and OID
                walk_response_objects = run(fetch_data(current_ip, walk_oid))
                # Add the data to the running list of results across all walk OIDs
                walk_result_list += walk_response_objects
            except PySnmpError as e:
                # Don't exit on an Exception when getting data, rather skipping the current attempt
                print("Could not fetch {} from IP {}, skipping. Error: {}".format(friendly_name, current_ip, e))
                continue
        # Now that the data from multiple walks have been fetched, parse them into a Dict
        walk_result_parsed_dict = {}
        for walk_single_result in walk_result_list:
            # Handle if there is an ErrorIndication instead of None. Otherwise, get the OID and data value
            if walk_single_result[0] is not None:
                print("ErrorIndication found for single walk result, skipping {}".format(walk_single_result[0]))
                continue
            # oid_value is an ObjectName which is an ObjectIdentifier, which has prettyPrint() available
            # For whatever reason the actual data is deeply nested in the return structure
            oid = walk_single_result[3][0][0].prettyPrint()
            data_value = walk_single_result[3][0][1].prettyPrint()
            # Add the parsed result into a dictionary for easier parsing of the next stage
            walk_result_parsed_dict[oid] = data_value
        # Now that the data is easily accessible in a Dict, format and arrange it for submission
        line_protocol_string_list += assemble_line_protocol_from_data_dict(walk_result_parsed_dict, influx_host_name)

    # All the SNMP walks for all IPs have been completed, line protocol is ready for submission. Submit!
    print("\nWriting {} categories of data from {} Unraid server(s) into InfluxDB".format(
        len(line_protocol_string_list), len(ip_addresses_to_influx_host)))
    send_data_to_influx(line_protocol_string_list)
    print("Completed writing Unraid data to Influx!")


if __name__ == '__main__':
    # https://servercheck.in/blog/little-jitter-can-help-evening-out-distributed
    wait_seconds = randint(0, 5)
    print("Adding {} second(s) of jitter before executing".format(wait_seconds))
    sleep(wait_seconds)
    collect_and_write_unraid_readings()
