from math import log
from time import time

from influxdb_client import InfluxDBClient, WritePrecision
from influxdb_client.client.write_api import SYNCHRONOUS
from requests import get

# These Tuples define the IP address from which to fetch data and the host string stored in InfluxDB for each.
# This way, if the IP address changes, an update can be made to keep the data going to the same tag in Influx
ip_addresses_to_influx_hosts = [("10.1.1.32", "nodemcu1"),
                                ("10.1.1.36", "nodemcu2"),
                                ("10.1.1.34", "nodemcu3"),
                                ("10.1.1.35", "nodemcu4"),
                                ("10.1.1.31", "nodemcu5")]

# These Tuples define the names of the fields in InfluxDB, and the ESP-reported field names they are derived from.
# In special cases such as dew point, multiple inputs are needed. We define the Tuple with a nested Tuple in this case
# NOTE: These are defined in order of preference, ascending. Where there are repeated Influx fields (to cover duplicate
# sensors and fallbacks), the last-listed sensor in a non-erroneous state will be output.
influx_fields_to_http_fields = [("humidity", "dhtHumidityPercent"),
                                ("humidity", "boschHumidityPercent"),
                                ("temperaturec", "dhtTemperatureC"),
                                ("temperaturec", "boschTemperatureC"),
                                ("temperaturef", "dhtTemperatureC"),
                                ("temperaturef", "boschTemperatureC"),
                                ("dewpointf", ("dhtTemperatureC", "dhtHumidityPercent")),
                                ("dewpointf", ("boschTemperatureC", "boschHumidityPercent")),
                                ("pressurehg", "boschPressurePa"),
                                ("pm100", "pmsPm10Standard"),
                                ("pm250", "pmsPm25Standard"),
                                ("pm1000", "pmsPm100Standard"),
                                ("pm100", "pmsPm10Environmental"),
                                ("pm250", "pmsPm25Environmental"),
                                ("pm1000", "pmsPm100Environmental"),
                                ("uva", "vemlUVA"),
                                ("uvb", "vemlUVB"),
                                ("uvindex", "vemlUVIndex"),
                                ("tvoc", "sgpTVOC"),
                                ("eco2", "sgpECO2")]


# Convert temperature from degrees Celsius to degrees Fahrenheit
def convert_celsius_to_fahrenheit(temp_c):
    return "{:.2f}".format(float(temp_c) * 1.8 + 32)


# Convert barometric pressure in Pascals to inches of Mercury
# https://www.metric-conversions.org/pressure/pascals-to-inches-of-mercury.htm
def convert_pascals_to_inches_mercury(pressure_pa):
    return "{:.2f}".format(float(pressure_pa) * 0.00029530)


# Given the temperature in Celsius and relative humidity in percent, determine the dewpoint
# of the current moisture level in the air in Celsius
# https://forum.arduino.cc/t/dew-point-using-dht22-sensor/485107/7 (cites "Application of a Dew Point Method to
# Obtain the Soil Water Characteristic," 2007, https://link.springer.com/chapter/10.1007/3-540-69873-6_7)
# https://iridl.ldeo.columbia.edu/dochelp/QA/Basic/dewpoint.html
# https://unidata.github.io/MetPy/latest/api/generated/metpy.calc.dewpoint.html
# https://sites.google.com/site/alessandropensato/arduino/simple-dew-point-controller
def convert_relative_humidity_temperature_to_dewpoint(temp_c, humidity_percent):
    gamma = log(float(humidity_percent) / 100.0) + ((17.62 * float(temp_c)) / (243.5 + float(temp_c)))
    dewpoint_c = 243.5 * gamma / (17.62 - gamma)
    return "{:.2f}".format(dewpoint_c)


# Given an IP address, fetch its HTTP response
def fetch_data(ip_address):
    # Form the URL and limit the HTTP GET to 5 seconds before timing out
    response = get("http://" + ip_address, timeout=5)
    return response.text


# Given an ESP's response as a list of lines, validate that its schema line and data line are the only lines,
# and that the number of fields is equal in both
def validate_data(line_list):
    line_list_count = len(line_list)
    if line_list_count != 2:
        raise Exception("Expected ESP response was 2 lines, actual was {}".format(line_list_count))
    schema_field_count = len(line_list[0].split(","))
    data_field_count = len(line_list[1].split(","))
    if schema_field_count != data_field_count:
        raise Exception("Expected ESP response schema field count to match data field count. Schema count was {} and "
                        "field count was {}".format(schema_field_count, data_field_count))


# Given an ESP's response as a list of lines, add each field name/value pair to a dictionary
# Super cool shorthand https://www.geeksforgeeks.org/python-convert-two-lists-into-a-dictionary/
def parse_data_into_dict(line_list):
    esp_dict = {line_list[0].split(",")[i]: line_list[1].split(",")[i] for i in range(len(line_list[0].split(",")))}
    return esp_dict


# Given a dict of ESP field name field value pairs, remove the input dict's entries with known bad values in place
def filter_bad_values_from_dict(dict):
    known_bad_value = -16384
    for key in list(dict):
        # TODO remove the 0/inf/nan stuff once Arduino code is fixed up
        if float(dict[key]) == known_bad_value or float(dict[key]) == 0 or dict[key] == "nan" or dict[key] == "inf":
            dict.pop(key)


# Given a dict of valid ESP data, perform necessary conversions if any and store the output value in a dict
# under its Influx field name
def parse_esp_dict_into_influx_dict(esp_dict):
    influx_dict = {}
    # Go through all the pre-defined mappings of Influx field name to ESP field name
    for tuple in influx_fields_to_http_fields:
        # Get the Influx field name from the tuple, which we'll use to handle different cases
        influx_field_name = tuple[0]
        # Using the new Python 3.10 switch syntax to handle special cases where conversion is needed
        # https://www.blog.pythonlibrary.org/2021/09/16/case-switch-comes-to-python-in-3-10/
        # Wrap in try except to catch instances where the necessary data doesn't exist. We skip the Tuple in that case
        try:
            match influx_field_name:
                case "dewpointf":
                    # Use esp_dict[key] rather than esp_dict.get(key) so a KeyError is raised
                    dewpoint_c = convert_relative_humidity_temperature_to_dewpoint(esp_dict[tuple[1][0]],
                                                                                   esp_dict[tuple[1][1]])
                    data_value = convert_celsius_to_fahrenheit(dewpoint_c)
                case "temperaturef":
                    data_value = convert_celsius_to_fahrenheit(esp_dict[tuple[1]])
                case "pressurehg":
                    data_value = convert_pascals_to_inches_mercury(esp_dict[tuple[1]])
                case _:
                    # Default case, the raw data from ESP can be saved directly to Influx
                    data_value = esp_dict[tuple[1]]
            print("Found value of [{}] for Influx field [{}]".format(data_value, influx_field_name))
            # Since we're using a dict, only one value for each field name can exist. For that reason, the later
            # values as defined in the field name Tuples will overwrite earlier fields. This allows us to define
            # fallback, or less preferred values by processing them first. DHT and then Bosch, for example.
            influx_dict[influx_field_name] = data_value
        except KeyError:
            print("Corresponding data value not found when trying to fetch Influx value {}".format(influx_field_name))
    return influx_dict


# Convert the dict to a string in Line Protocol, which is `field=value,field2=value2,field3=value3` for the data section
def parse_influx_dict_into_line_protocol(influx_dict):
    line_protocol_list = []
    for key in influx_dict:
        line_protocol_list.append("{}={}".format(key, influx_dict[key]))
    return ",".join(line_protocol_list)


# Use the Influx Python Client to call the Influx 2.0 write API to batch-write the Line Protocol for all new data
def send_data_to_influx(line_protocol_string_list):

    client = InfluxDBClient(url=url, token=token, org=org)
    write_api = client.write_api(write_options=SYNCHRONOUS)
    write_api.write(write_precision=WritePrecision.S, bucket=bucket, record=line_protocol_string_list)


# Top-level ESP data-gathering function to orchestrate all the other calls in this file
def collect_and_write_esp_sensor_readings():
    # Instantiate a list that we'll store lines of Line Protocol to write to Influx
    line_protocol_string_list = []
    # Get the current time since Epoch in seconds, which we'll use when writing lines to Influx
    epoch_time_seconds = int(time())
    # Iterate through each tuple of IP and Influx host name
    for tuple in ip_addresses_to_influx_hosts:
        current_ip = tuple[0]
        influx_host_name = tuple[1]
        try:
            # Get the data from the current IP, removing any whitespace as it should be CSV
            data = fetch_data(current_ip).replace(" ", "")
        except Exception:
            # Don't exit on an Exception when getting data, rather skipping that particular IP
            print("Could not connect/fetch from IP {}, skipping".format(current_ip))
            break
        # Split the ESP data into separate lines
        line_list = str.splitlines(data)
        # Validate that the data is in a parseable format
        validate_data(line_list)
        # Convert the CSV data into a dict, with the field name as key and the field value as value
        esp_dict = parse_data_into_dict(line_list)
        # Remove key/value pairs from the dict when the value doesn't meet the criteria needed for saving to Influx
        filter_bad_values_from_dict(esp_dict)
        # Run conversions and create a new dict keyed on the field name in Influx, rather than the ESP name
        influx_dict = parse_esp_dict_into_influx_dict(esp_dict)
        # Convert the Influx field name dict into a Line Protocol string, but just the data at this point
        line_protocol_data_string = parse_influx_dict_into_line_protocol(influx_dict)
        # Format the rest of the Line Protocol, forming together the measurement, tags, field set, and time
        line_protocol_full_string = "environment,host={} {} {}".format(influx_host_name, line_protocol_data_string,
                                                                       epoch_time_seconds)
        # Add the completed Line Protocol to the list of Line Protocol to write to Influx
        line_protocol_string_list.append(line_protocol_full_string)
    # Perform the write to Influx
    send_data_to_influx(line_protocol_string_list)


if __name__ == '__main__':
    collect_and_write_esp_sensor_readings()
