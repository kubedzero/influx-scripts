import decimal
from random import randint
from time import time, sleep

from pysnmp.error import PySnmpError
from pysnmp.hlapi import ObjectType, ObjectIdentity, getCmd, SnmpEngine, UsmUserData, UdpTransportTarget, ContextData

from influx_writer import send_data_to_influx
from my_credentials import APC_SNMPV3_USER

# Gets APC UPS information using its NMC2 network management card and SNMPv3
# https://www.apc.com/us/en/product/SFPMIB441/powernet-mib-v4-4-1/
# https://www.apc.com/us/en/faqs/FA156048/

# These Tuples define the IP address from which to fetch data and the tag "ups" stored in InfluxDB for each.
# This way, if the IP address changes, an update can be made to keep the data going to the same tag in Influx
ip_addresses_to_influx_ups = [("apc.brad", "apc")]
# This Dict defines the SNMP OIDs under which the values are retrieved, alongside the names of each field in InfluxDB
oid_to_influx_field_dict = {"1.3.6.1.4.1.318.1.1.1.3.3.1.0": "utilVoltage",
                            "1.3.6.1.4.1.318.1.1.1.2.3.2.0": "upsTemp",
                            "1.3.6.1.4.1.318.1.1.1.4.3.3.0": "loadPercent",
                            "1.3.6.1.4.1.318.1.1.1.4.3.4.0": "loadCurrent"}
# Define the "measurement" category under which the data fields will be stored
influx_measurement_name = "ups_data"
# Define the port where SNMP is running on the target devices
snmp_port_number = 161


# Given a list of OIDs, create the object structure needed by the SNMP library
def create_object_type_list_from_oid_list(oid_list):
    object_type_list = []
    for oid in oid_list:
        object_type_list.append(ObjectType(ObjectIdentity(oid)))
    return object_type_list


# Given an IP address and a list of OIDs, fetch the OID values using the SNMP library's GET command
def fetch_data(ip_address, oid_list):
    object_type_list = create_object_type_list_from_oid_list(oid_list)
    # For SNMPV2, replace UsmUserData("someSNMPuser") with CommunityData("public")
    result_tuple = getCmd(SnmpEngine(), UsmUserData(APC_SNMPV3_USER),
                          UdpTransportTarget((ip_address, snmp_port_number)), ContextData(), *object_type_list)
    return result_tuple


# Convert the dict to a string in Line Protocol, which is `field=value,field2=value2,field3=value3` for the data section
def parse_influx_dict_into_line_protocol(influx_dict):
    line_protocol_list = []
    for key in influx_dict:
        line_protocol_list.append("{}={}".format(key, influx_dict[key]))
    return ",".join(line_protocol_list)


# Top-level APC data-gathering function to orchestrate all the other calls in this file
def collect_and_write_apc_readings():
    # Instantiate a list to store lines of Line Protocol to write to Influx
    line_protocol_string_list = []
    # Iterate through each tuple of IP and Influx ups name
    for ip_to_ups_tuple in ip_addresses_to_influx_ups:
        current_ip = ip_to_ups_tuple[0]
        influx_ups_name = ip_to_ups_tuple[1]
        print("\nChecking IP {} with Influx Host Name {}".format(current_ip, influx_ups_name))
        try:
            # Get the data from the current IP, using the dict to source the OIDs needed
            data = fetch_data(current_ip, oid_to_influx_field_dict.keys())
        except PySnmpError:
            # Don't exit on an Exception when getting data, rather skipping the current IP
            print("Could not connect/fetch from IP {}, skipping".format(current_ip))
            continue

        # Parse the returned data Tuple
        error_indication = data[0]
        error_status = data[1]
        error_index = data[2]
        var_binds = data[3]
        # Skip this IP and proceed to others if an error is found
        if error_indication:
            print("SNMP returned an error for IP {}, skipping: {}".format(current_ip, error_indication))
            continue
        elif error_status:
            print("SNMP returned an error for IP {}, skipping: {} at {}".format(current_ip,
                                                                                error_status.prettyPrint(),
                                                                                error_index and
                                                                                var_binds[int(error_index) - 1][
                                                                                    0] or "?"))
            continue
        # Otherwise begin parsing the returned data
        influx_dict = {}
        # Each var_bind is a tuple itself, with the first element being an identifier and the second a value
        for var_bind in var_binds:
            data_oid = var_bind[0].getOid().prettyPrint()
            data_value = var_bind[1].prettyPrint()
            print("Retrieved OID {} with value {}".format(data_oid, data_value))
            # APC returns integers and requires division by 10 to get the true value
            try:
                data_value_adjusted = decimal.Decimal(data_value) / 10
            except decimal.InvalidOperation:
                # Don't exit on an Exception when getting data, just skip the current IP
                print("Could not convert OID {} value [{}] to a decimal, skipping this value".format(data_oid,
                                                                                                     data_value))
                continue
            # Look up the OID to Influx field name mapping
            influx_field_name = oid_to_influx_field_dict.get(data_oid)
            if influx_field_name:
                # Add the Influx field name and data value combo to the dict
                influx_dict[influx_field_name] = data_value_adjusted

        # Skip adding line protocol for output if there were no values
        if len(influx_dict) < 1:
            print("No valid data was found for IP {}, skipping submission of this IP".format(current_ip))
            continue

        # Convert the Influx field name dict into a Line Protocol string, but just the data at this point
        line_protocol_data_string = parse_influx_dict_into_line_protocol(influx_dict)
        # Get the current time since Epoch in seconds, which is used when writing lines to Influx
        epoch_time_seconds = int(time())
        # Format the rest of the Line Protocol, forming together the measurement, tags, field set, and time
        line_protocol_full_string = "{},ups={} {} {}".format(influx_measurement_name, influx_ups_name,
                                                             line_protocol_data_string, epoch_time_seconds)
        # Add the completed Line Protocol to the list of Line Protocol to write to Influx
        line_protocol_string_list.append(line_protocol_full_string)

    # Skip calling InfluxDB if the Line Protocol list ended up being empty
    if len(line_protocol_string_list) < 1:
        print("No APC UPS data found, exiting")
        exit(0)
    print("\nWriting data from {} APC UPS unit(s) into InfluxDB".format(len(line_protocol_string_list)))
    send_data_to_influx(line_protocol_string_list)
    print("Completed writing APC data to Influx!")


if __name__ == '__main__':
    wait_seconds = randint(0, 10)
    print("Adding {} second(s) of jitter before executing".format(wait_seconds))
    sleep(wait_seconds)
    collect_and_write_apc_readings()
