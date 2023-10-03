from random import randint
from time import time, sleep

from math import log
from requests import get, RequestException

from influx_writer import send_data_to_influx

# These Tuples define the IP address from which to fetch data and the host string stored in InfluxDB for each.
# This way, if the IP address changes, an update can be made to keep the data going to the same tag in Influx
ip_addresses_to_influx_hosts = [("10.1.1.31", "nodemcu3"),  # office esp32 Feather BME280 PMS7003 SGP30
                                ("10.1.1.37", "nodemcu1"),  # bed amica2 DHT22 BME280
                                ("10.1.1.36", "nodemcu2"),  # bathroom amica1 DHT22 BME280
                                ("10.1.1.34", "nodemcu4"),  # couch geek1 SCD40 SGP30 (adafruit) BME280
                                ("10.1.1.35", "nodemcu5")]  # bedbath geek2 SGP30

# These Tuples define the names of the fields in InfluxDB, and the ESP-reported field names they are derived from.
# In special cases such as dew point, multiple inputs are needed. We define the Tuple with a nested Tuple in this case
# NOTE: These are defined in order of preference, ascending. Where there are repeated Influx fields (to cover duplicate
# sensors and fallbacks), the last-listed sensor in a non-erroneous state will be output.
influx_fields_to_http_fields = [("humidity", "dhtHumidityPercent"),
                                ("humidity", "scdHumidityPercent"),
                                ("humidity", "boschHumidityPercent"),
                                ("temperaturec", "dhtTemperatureC"),
                                ("temperaturec", "scdTemperatureC"),
                                ("temperaturec", "boschTemperatureC"),
                                ("temperaturef", "dhtTemperatureC"),
                                ("temperaturef", "scdTemperatureC"),
                                ("temperaturef", "boschTemperatureC"),
                                ("dewpointf", ("dhtTemperatureC", "dhtHumidityPercent")),
                                ("dewpointf", ("scdTemperatureC", "scdHumidityPercent")),
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
                                ("co2", "scdCO2")]


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
def filter_bad_values_from_dict(esp_dict):
    known_bad_value_float = -16384
    known_bad_value_string = "nan"
    for key in list(esp_dict):
        if (esp_dict[key] == known_bad_value_string) or (float(esp_dict[key]) == known_bad_value_float):
            esp_dict.pop(key)


# Given a dict of valid ESP data, perform necessary conversions if any and store the output value in a dict
# under its Influx field name
def parse_esp_dict_into_influx_dict(esp_dict):
    influx_dict = {}
    # Go through all the pre-defined mappings of Influx field name to ESP field name
    for influx_http_tuple in influx_fields_to_http_fields:
        # Get the Influx field name from the tuple, which we'll use to handle different cases
        influx_field_name = influx_http_tuple[0]
        # Using the new Python 3.10 switch syntax to handle special cases where conversion is needed
        # https://www.blog.pythonlibrary.org/2021/09/16/case-switch-comes-to-python-in-3-10/
        # Wrap in try except to catch instances where the necessary data doesn't exist. We skip the Tuple in that case
        try:
            match influx_field_name:
                case "dewpointf":
                    # Use esp_dict[key] rather than esp_dict.get(key) so a KeyError is raised
                    dewpoint_c = convert_relative_humidity_temperature_to_dewpoint(esp_dict[influx_http_tuple[1][0]],
                                                                                   esp_dict[influx_http_tuple[1][1]])
                    data_value = convert_celsius_to_fahrenheit(dewpoint_c)
                case "temperaturef":
                    data_value = convert_celsius_to_fahrenheit(esp_dict[influx_http_tuple[1]])
                case "pressurehg":
                    data_value = convert_pascals_to_inches_mercury(esp_dict[influx_http_tuple[1]])
                case _:
                    # Default case, the raw data from ESP can be saved directly to Influx
                    data_value = esp_dict[influx_http_tuple[1]]
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


# Top-level ESP data-gathering function to orchestrate all the other calls in this file
# TODO move this to an esp-specific python file so main can be log setup and switching between different updates
# TODO maybe make this return the list of line protocol, and then we can merge them all together for writing to Influx
def collect_and_write_esp_sensor_readings():
    # Instantiate a list that we'll store lines of Line Protocol to write to Influx
    line_protocol_string_list = []
    # Get the current time since Epoch in seconds, which we'll use when writing lines to Influx
    epoch_time_seconds = int(time())
    # Iterate through each tuple of IP and Influx host name
    for ip_to_host_tuple in ip_addresses_to_influx_hosts:
        current_ip = ip_to_host_tuple[0]
        influx_host_name = ip_to_host_tuple[1]
        print("\n\nChecking IP {} with Influx Host Name {}\n".format(current_ip, influx_host_name))
        try:
            # Get the data from the current IP, removing any whitespace as it should be CSV
            data = fetch_data(current_ip).replace(" ", "")
        except RequestException:
            # Don't exit on an Exception when getting data, rather skipping the current IP
            print("Could not connect/fetch from IP {}, skipping".format(current_ip))
            continue
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
    wait_seconds = randint(0, 10)
    print("Adding {} second(s) of jitter before executing".format(wait_seconds))
    sleep(wait_seconds)
    collect_and_write_esp_sensor_readings()
