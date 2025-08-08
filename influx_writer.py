from influxdb_client import InfluxDBClient, WritePrecision
from influxdb_client.client.write_api import SYNCHRONOUS

from my_credentials import INFLUX_URL, INFLUX_BUCKET, INFLUX_ORG, INFLUX_TOKEN


# Use the Influx Python Client to call the Influx 2.0 write API to batch-write the Line Protocol for all new data
def send_data_to_influx(line_protocol_string_list):
    client = InfluxDBClient(url=INFLUX_URL, token=INFLUX_TOKEN, org=INFLUX_ORG)
    write_api = client.write_api(write_options=SYNCHRONOUS)
    print("Writing data {} to InfluxDB".format(line_protocol_string_list))
    write_api.write(write_precision=WritePrecision.S, bucket=INFLUX_BUCKET, record=line_protocol_string_list)
