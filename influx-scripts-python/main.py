import math

from influxdb_client import InfluxDBClient, WritePrecision
from influxdb_client.client.write_api import SYNCHRONOUS
from requests import get
from time import time

# Press ⌃R to execute it or replace it with your code.
# Press Double ⇧ to search everywhere for classes, files, tool windows, actions, and settings.

"""
TODO
- parse the CSV out into strings to write
- format the string into a payload to send
- make an HTTP POST call to send data
- Use influx or just construct the raw call
- TODO handle fallback logic for duplicate data, such as dewpoint, humidity, temperature
- TODO provide conversion tools such as barometric pressure from pascals to inHg, C to F, Dewpoint
- TODO handle missing data by skipping writes of that data rather than failing the whole thing
- TODO how to handle an output needing one or more inputs to function - for each output data field, define a list of input fields?
then to handle fallback, just define the data fields multiple times, and in the final summation look for fallback?
"""


# Convert temperature in degrees Celsius to degrees Fahrenheit
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
    gamma = math.log(float(humidity_percent) / 100.0) + ((17.62 * float(temp_c)) / (243.5 + float(temp_c)))
    dewpoint_c = 243.5 * gamma / (17.62 - gamma)
    return "{:.2f}".format(dewpoint_c)


# These Tuples define the IP address from which to fetch data and the host string stored in InfluxDB for each.
# This way, if the IP address changes, an update can be made to keep the data going to the same host
ip_addresses_to_influx_hosts = [("10.1.1.32", "nodemcu1"),
                                ("10.1.1.36", "nodemcu2"),
                                ("10.1.1.34", "nodemcu3"),
                                ("10.1.1.35", "nodemcu4"),
                                ("10.1.1.31", "nodemcu5")]

# These Tuples define the names of the fields in InfluxDB, and the ESP-reported field names they are derived from
# In special cases such as dew point, multiple inputs are needed. We define the Tuple with a nested Tuple in this case
# NOTE: These are defined in order of preference, descending. Where there are repeated Influx fields (to cover duplicate
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
                                ("eco2", "sgpECO2"),
                                ]


# Given an IP address, fetch its HTTP response
def fetch_data(ip_address):
    # Form the URL and limit the HTTP GET to 5 seconds before timing out
    # TODO handle timeout ConnectTimeoutError exception without crashing
    response = get("http://" + ip_address, timeout=5)
    return response.text


# Given an ESP's response as a list of lines, validate that its schema line and data line are the only lines, and that the number
# of fields is equal in both
def validate_data(line_list):
    line_list_count = len(line_list)
    if line_list_count != 2:
        print("Expected ESP response was 2 lines, actual was {}".format(line_list_count))
    schema_field_count = len(line_list[0].split(","))
    data_field_count = len(line_list[1].split(","))
    if schema_field_count != data_field_count:
        print("Expected ESP response schema field count to match data field count. Schema count was {} and "
              "field count was {}".format(schema_field_count, data_field_count))


# Given an ESP's response as a list of lines, add each field name/value pair to a dictionary
# super cool shorthand https://www.geeksforgeeks.org/python-convert-two-lists-into-a-dictionary/
def parse_data_into_dict(line_list):
    esp_dict = {line_list[0].split(",")[i]: line_list[1].split(",")[i] for i in range(len(line_list[0].split(",")))}
    return esp_dict


# Given a dict of ESP field name field value pairs, remove the entries with known bad values
def filter_bad_values_from_dict(dict):
    known_bad_value = -16384
    for key in list(dict):
        if float(dict[key]) == known_bad_value or float(dict[key]) == 0 or dict[key] == "nan" or dict[key] == "inf":
            dict.pop(key)


def parse_esp_dict_into_influx_dict(esp_dict):
    influx_dict = {}
    # Go through all the pre-defined mappings of Influx field name to ESP field name
    for tuple in influx_fields_to_http_fields:
        # Get the Influx field name from the tuple, which we'll
        influx_field_name = tuple[0]
        # Using the new Python 3.10 switch syntax to handle special cases where conversion is needed
        # https://www.blog.pythonlibrary.org/2021/09/16/case-switch-comes-to-python-in-3-10/
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
                    data_value = esp_dict[tuple[1]]
            print("Found value of [{}] for Influx field [{}]".format(data_value, influx_field_name))
            influx_dict[influx_field_name] = data_value
        except KeyError:
            print("Corresponding data value not found when trying to fetch Influx value {}".format(influx_field_name))
    return influx_dict


# Line protocol is `field=value,field2=value2,field3=value3` for the data section
def parse_influx_dict_into_line_protocol(influx_dict):
    line_protocol_list=[]
    for key in influx_dict:
        line_protocol_list.append("{}={}".format(key, influx_dict[key]))
    return ",".join(line_protocol_list)


def send_data_to_influx(line_protocol_string_list):

    client = InfluxDBClient(url=url, token=token, org=org)
    write_api = client.write_api(write_options=SYNCHRONOUS)
    write_api.write(write_precision=WritePrecision.S, bucket=bucket,record=line_protocol_string_list)


# Press the green button in the gutter to run the script.
if __name__ == '__main__':
    line_protocol_string_list = []
    epoch_time_seconds = int(time())
    for tuple in ip_addresses_to_influx_hosts:
        current_ip=tuple[0]
        influx_host_name=tuple[1]
        try:
            data = fetch_data(current_ip).replace(" ","")
        except Exception:
            print("Could not connect/fetch from IP {}, skipping".format(current_ip))
            break
        line_list = str.splitlines(data)
        validate_data(line_list)
        esp_dict = parse_data_into_dict(line_list)
        filter_bad_values_from_dict(esp_dict)
        influx_dict = parse_esp_dict_into_influx_dict(esp_dict)
        line_protocol_data_string = parse_influx_dict_into_line_protocol(influx_dict)
        line_protocol_full_string = "environment,host={} {} {}".format(influx_host_name, line_protocol_data_string,
                                                                       epoch_time_seconds)
        line_protocol_string_list.append(line_protocol_full_string)

    send_data_to_influx(line_protocol_string_list)