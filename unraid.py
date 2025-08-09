

import decimal
from asyncio import run
from random import randint
from time import time, sleep

from pysnmp.entity.engine import SnmpEngine
from pysnmp.error import PySnmpError
from pysnmp.hlapi.v3arch import get_cmd, UsmUserData, UdpTransportTarget, ContextData, CommunityData, walk_cmd, bulk_cmd
from pysnmp.proto.rfc1902 import ObjectName
from pysnmp.smi.rfc1902 import ObjectType, ObjectIdentity

from influx_writer import send_data_to_influx


# Gets Unraid system health via SNMP v2c

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
oid_to_influx_field_dict = {"cpumhz": ".1.3.6.1.4.1.8072.1.3.2.4.1.2.6.99.112.117.109.104.122.1.",
                            "meminfo": ".1.3.6.1.4.1.8072.1.3.2.4.1.2.7.109.101.109.105.110.102.111.",
                            "diskfree": ".1.3.6.1.4.1.8072.1.3.2.4.1.2.8.100.105.115.107.102.114.101.101.",
                            "disktemp": ".1.3.6.1.4.1.8072.1.3.2.4.1.2.8.100.105.115.107.116.101.109.112.",
                            "sharefree": ".1.3.6.1.4.1.8072.1.3.2.4.1.2.9.115.104.97.114.101.102.114.101.101.",
                            "cpuPercent": ".1.3.6.1.2.1.25.3.3.1.2.196608"}

# Define the "measurement" category under which the data fields will be stored
influx_measurement_name = "unraid"
# Define the port where SNMP is running on the target devices
snmp_port_number = 161


# Given an IP address and an OID to walk, fetch the OID values using the SNMP library's WALK command
async def fetch_data(ip_address, walk_oid):
    snmp_engine = SnmpEngine()
    # For SNMPV3, replace CommunityData("public") with UsmUserData("someSNMPuser")
    # lookupMib=False will leave full OID numeric representation. Otherwise it might be SNMPv2-SMI::snmpModules.16.1.5.
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
        for walk_oid in walk_oid_to_mib_name.keys():
            try:
                # Get the data from the current IP and OID
                walk_response_objects = run(fetch_data(current_ip, walk_oid))
                # Add the data to the running list of results across all walk OIDs
                walk_result_list = walk_result_list + walk_response_objects
            except PySnmpError as e:
                # Don't exit on an Exception when getting data, rather skipping the current IP
                print("Could not connect/fetch from IP {}, skipping. Error: {}".format(current_ip, e))
                continue
        # Now that the data from multiple walks have been fetched, parse them into a Dict
        walk_result_parsed_dict = {}
        for walk_single_result in walk_result_list:
            # Handle if there is an ErrorIndication instead of None
            if walk_single_result[0] is not None:
                print("ErrorIndication found for single walk result, skipping {}".format(walk_single_result[0]))
                continue
            # Otherwise, get the OID and data value
            # oid_value is an ObjectName which is an ObjectIdentifier
            oid = walk_single_result[3][0][0].prettyPrint()
            data_value = walk_single_result[3][0][1].prettyPrint()
            # Add the parsed result into a dictionary for easier parsing of the next stage
            walk_result_parsed_dict[oid] = data_value
        # Now that the data is easily accessible in a Dict, format and arrange it for submission
        print(walk_result_parsed_dict)


if __name__ == '__main__':
    wait_seconds = randint(0, 10)
    print("Adding {} second(s) of jitter before executing".format(wait_seconds))
    # sleep(wait_seconds)
    collect_and_write_unraid_readings()
