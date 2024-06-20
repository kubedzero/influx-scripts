import re
from random import randint
from time import time, sleep

from netmiko import ConnectHandler

from netmiko.exceptions import NetMikoTimeoutException, NetMikoAuthenticationException, SSHException

from influx_writer import send_data_to_influx
from my_credentials import S16_LOGIN_TUPLE

# These Tuples define the IP address from which to fetch data and the tag "name" stored in InfluxDB for each.
# This way, if the IP address changes, an update can be made to keep the data going to the same tag in Influx
s16_ip_tag_tuples = [("10.96.158.56", "nn632")]

# Define the "measurement" category under which the data fields will be stored
influx_measurement_name = "s16_data"

# Define the mapping from Ubiquiti-generated description to Influx Field Name. Fields may be additionally decorated
description_to_influx_field_dict = {"TEMP-1": "temp1",
                                    "TEMP-2": "temp2",
                                    "PoE-01": "poe1Temp",
                                    "PoE-02": "poe2Temp",
                                    "PoE-03": "poe3Temp",
                                    "PoE-IN-1": "poeIn1",
                                    "PoE-IN-2": "poeIn2",
                                    "DC-IN-1": "dcIn1"}


# Given an IP of an S16 and its user/pass, connect to it and get its environmental data
def fetch_data(current_ip, login_user, login_password):
    # Establish a connection with the device. Use the `terminal_server` device type to avoid netmiko
    # preconfigured setups to automatically run `configure` or `enable terminal` the way most devices need
    net_connect = ConnectHandler(device_type='terminal_server', ip=current_ip, username=login_user,
                                 password=login_password)
    # Run the "show environment" command that prints a human-readable table of data
    data = net_connect.send_command("show environment")
    # Disconnect from the device now that the data is retrieved
    net_connect.disconnect()
    return data


# Convert a dict to a string in Line Protocol, which is `field=value,field2=value2,field3=value3` for the data section
def parse_influx_dict_into_line_protocol(influx_dict):
    line_protocol_list = []
    for key in influx_dict:
        line_protocol_list.append("{}={}".format(key, influx_dict[key]))
    return ",".join(line_protocol_list)


# Top-level S16 data-gathering function to orchestrate all the other calls in this file
def collect_and_write_s16_readings():
    # Instantiate a list to store lines of Line Protocol to write to Influx
    line_protocol_string_list = []
    # Iterate through each tuple of IP and Influx tag name
    for s16_ip_tag_tuple in s16_ip_tag_tuples:
        current_ip = s16_ip_tag_tuple[0]
        influx_measurement_tag_name = s16_ip_tag_tuple[1]
        login_user = S16_LOGIN_TUPLE[0]
        login_password = S16_LOGIN_TUPLE[1]

        try:
            # Get the data from the current IP
            print("\nChecking IP {} with Influx Name {}".format(current_ip, influx_measurement_tag_name))
            data = fetch_data(current_ip, login_user, login_password)
            print(data)
        except (NetMikoTimeoutException, NetMikoAuthenticationException, SSHException) as exit_error:
            # Don't exit on an Exception when getting data, rather skipping the current IP
            print("Could not connect/fetch from IP {}, skipping. Error was {}".format(current_ip, exit_error))
            continue
        # Begin parsing retrieved data. Instantiate the dict to hold each field/value pair
        influx_dict = {}
        # Use retrieved data to parse the human_readable table into a list of lines, throwing away blank lines.
        data_list = data.splitlines()
        # Lines 5-9 (elements 4-8) contain the temperatures
        for line_number in range(4, 9):
            try:
                # Split the line into elements, delimited by >1 space so a field such as "Not Powered" is not split
                # https://pynative.com/python-regex-split/
                line_list = re.split("\\s\\s+", data_list[line_number])
                # Schema is `Unit Sensor Description Temp (C) State Max_Temp (C)` such as `1 1 TEMP-1 56 Normal 59`
                # Grab Description and use it to fetch the desired Influx Field name. Each Description is unique
                description = line_list[2]
                influx_field_name = description_to_influx_field_dict.get(description)
                # Grab the current temperature
                temperature_string = line_list[3]
                # Try to add the integer representation of the Temperature to the dict, and skip otherwise
                try:
                    influx_dict[influx_field_name] = int(temperature_string)
                except ValueError as exit_error:
                    print("Error converting {} to Int for field {}: {}".format(temperature_string, influx_field_name,
                                                                               exit_error))
                    continue
            except IndexError:
                print("Error reading line {}, is the data formatting correct?".format(line_number))
                continue
        # Lines 14-16 (elements 13-15) contain the power data
        for line_number in range(13, 16):
            try:
                # Split the line into elements, delimited by >1 space so a field such as "Not Powered" is not split
                # https://pynative.com/python-regex-split/
                line_list = re.split("\\s\\s+", data_list[line_number])
                # Schema `Unit PowerSupply Description Type State Consumed(W) Voltage(V) Current(mA) ConsumedMeter(Whr)`
                # Example data `1 3 DC-IN-1 Fixed Powering 100.48 53.49 1878.48 101772.33`
                # Grab Description and use it to fetch the desired Influx Field name. Each Description is unique
                description = line_list[2]
                influx_field_name_partial = description_to_influx_field_dict.get(description)
                # Safely grab the current watts, voltage, current, and energy usage
                try:
                    influx_dict[influx_field_name_partial + "Watts"] = float(line_list[5])
                except ValueError as exit_error:
                    print("Error converting {} to Float: {}".format(line_list[5], exit_error))
                    continue
                try:
                    influx_dict[influx_field_name_partial + "Voltage"] = float(line_list[6])
                except ValueError as exit_error:
                    print("Error converting {} to Float: {}".format(line_list[6], exit_error))
                    continue
                try:
                    influx_dict[influx_field_name_partial + "Current"] = float(line_list[7])
                except ValueError as exit_error:
                    print("Error converting {} to Float: {}".format(line_list[7], exit_error))
                    continue
                try:
                    influx_dict[influx_field_name_partial + "EnergyUsage"] = float(line_list[8])
                except ValueError as exit_error:
                    print("Error converting {} to Float: {}".format(line_list[8], exit_error))
                    continue
            except IndexError:
                print("Error reading line {}, is the data formatting correct?".format(line_number))
                continue
        # Skip adding line protocol for output if there were no values
        if len(influx_dict) < 1:
            print("No valid data was found for IP {}, skipping submission of this IP".format(current_ip))
            continue

        # Convert the Influx field name dict into a Line Protocol string, but just the data at this point
        line_protocol_data_string = parse_influx_dict_into_line_protocol(influx_dict)
        # Get the current time since Epoch in seconds, which is used when writing lines to Influx
        epoch_time_seconds = int(time())
        # Format the rest of the Line Protocol, forming together the measurement, tags, field set, and time
        line_protocol_full_string = "{},name={} {} {}".format(influx_measurement_name, influx_measurement_tag_name,
                                                              line_protocol_data_string, epoch_time_seconds)
        # Add the completed Line Protocol to the list of Line Protocol to write to Influx
        line_protocol_string_list.append(line_protocol_full_string)

    # Skip calling InfluxDB if the Line Protocol list ended up being empty
    if len(line_protocol_string_list) < 1:
        print("No S16 UPS data found, exiting")
        exit(0)
    print("\nWriting data from {} S16 unit(s) into InfluxDB".format(len(line_protocol_string_list)))
    send_data_to_influx(line_protocol_string_list)
    print("Completed writing S16 data to Influx!")


if __name__ == '__main__':
    wait_seconds = randint(0, 10)
    print("Adding {} second(s) of jitter before executing".format(wait_seconds))
    sleep(wait_seconds)
    collect_and_write_s16_readings()
