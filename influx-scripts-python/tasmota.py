from json import loads
from random import randint
from time import time, sleep

from requests import RequestException, get

from influx_writer import send_data_to_influx

# These Tuples define the IP address from which to fetch data and the host string stored in InfluxDB for each.
# This way, if the IP address changes, an update can be made to keep the data going to the same tag in Influx
ip_addresses_to_influx_hosts = [("lamp.brad", "lamp"),
                                ("tv.brad", "tv"),
                                ("hvac1.brad", "hvac1"),
                                ("hvac2.brad", "hvac2"),
                                ("fridge.brad", "fridge"),
                                ("blanket.brad", "blanket"),
                                ("kitchen1.brad", "kitchen"),
                                ("server-switch.brad", "server"),
                                ("ct-desk.brad", "ctdesk"),
                                ("jb-desk.brad", "jbdesk"),
                                ("heater", "heater"),
                                ("kitchen2.brad", "kitchen2")]

# These Tuples define the names of the fields in InfluxDB, and the Tasmota-reported field names they are derived from.
influx_fields_to_http_fields = [("kilowattHours", "StatusSNS.ENERGY.Total"),
                                ("voltage", "StatusSNS.ENERGY.Voltage"),
                                ("powerFactor", "StatusSNS.ENERGY.Factor"),
                                ("watts", "StatusSNS.ENERGY.Power"),
                                ("amps", "StatusSNS.ENERGY.Current"),
                                ("voltAmps", "StatusSNS.ENERGY.ApparentPower"),
                                ("uptime", "StatusSTS.UptimeSec"),
                                ("powerState", "Status.Power")]


# Given a JSON blob and a dot.separated.path to the key of the desired value, fetch that value or return an error
def fetch_value_from_json(json, search_string):
    # Split the search_string into a List
    search_term_list = search_string.split(".")
    # Traverse the List one level at a time, throwing an error if the value doesn't exist
    filtered_json = json
    for search_term in search_term_list:
        filtered_json = filtered_json[search_term]
    # Get the value associated with the final level, and return it
    return filtered_json


# Given an IP address, fetch its HTTP response
def fetch_data_from_ip(ip_address):
    # Form the URL and limit the HTTP GET to 5 seconds before timing out
    response = get("http://{}/cm?cmnd=Status%200".format(ip_address), timeout=5)
    return response.text


# Given the String representation of the Tasmota data, parse through it and return the Line Protocol version
def parse_raw_data_into_field_set(data_string):
    line_protocol_list = []
    # Convert to JSON
    json_data = loads(data_string)
    # Iterate through influx_fields_to_http_fields, using each entry's JSON search string and Influx field name
    for influx_field, http_field in influx_fields_to_http_fields:
        try:
            # Get the data value, if it exists
            data_value = fetch_value_from_json(json_data, http_field)
        except KeyError:
            # Don't exit on an Exception when parsing JSON, rather skipping the current entry
            print("Could not find value for {}, skipping Influx value {}".format(http_field, influx_field))
            continue
        # Add the key/value pair to a running String consisting of the line protocol data
        line_protocol_list.append("{}={}".format(influx_field, data_value))
    # Return the various key/value pairs, separated by commas as Line Protocol dictates
    return ",".join(line_protocol_list)


# Main method to retrieve data from multiple Tasmota devices and write Line Protocol data to InfluxDB
def collect_and_write_tasmota_readings():
    # Instantiate a list used to store lines of Line Protocol to write to Influx
    line_protocol_string_list = []
    # Get the current time since Epoch in seconds, used to set the record time of data going into Influx
    epoch_time_seconds = int(time())
    # Iterate through each tuple of IP/address and Influx host name
    for current_ip, influx_host_name in ip_addresses_to_influx_hosts:
        try:
            # Get the data from the current IP, leaving it as a string
            data = fetch_data_from_ip(current_ip)
            # Convert the Influx field name dict into a Line Protocol string, but just the data at this point
            line_protocol_field_set = parse_raw_data_into_field_set(data)
        except RequestException:
            # Don't exit on an Exception when getting data, rather skipping the current IP
            print("Could not connect/fetch from IP {}, skipping".format(current_ip))
            continue
        # Format the rest of the Line Protocol, forming together the measurement, tags, field set, and time
        line_protocol_full_string = "tasmota,device={} {} {}".format(influx_host_name,
                                                                     line_protocol_field_set,
                                                                     epoch_time_seconds)
        print("Converted data from {} into Line Protocol: {}".format(current_ip, line_protocol_full_string))
        # Add the completed Line Protocol to the list of Line Protocol to write to Influx
        line_protocol_string_list.append(line_protocol_full_string)
    print("Writing data from {} Tasmota devices into InfluxDB".format(len(line_protocol_string_list)))
    send_data_to_influx(line_protocol_string_list)
    print("Completed writing Tasmota data to Influx!")


if __name__ == '__main__':
    wait_seconds = randint(0, 10)
    print("Adding {} second(s) of jitter before executing".format(wait_seconds))
    sleep(wait_seconds)
    collect_and_write_tasmota_readings()
