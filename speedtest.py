import subprocess
from json import loads
from random import randint, choice
from time import time, sleep

from influx_writer import send_data_to_influx


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


# Call speedtest.net using a shell command and collect its results, writing into InfluxDB
def collect_and_write_speedtest_readings():
    # Define the possible Speedtest servers to use
    speedtest_server_ids = [13098, 16976, 16888, 21016, 35055, 21313, 20326]
    # Pick a random server from the list
    # https://stackoverflow.com/questions/306400/how-can-i-randomly-select-choose-an-item-from-a-list-get-a-random-element
    selected_speedtest_server_id = choice(speedtest_server_ids)

    # Build the shell command to execute
    # NOTE: current `speedtest --version` reports 1.2.0.84 on macOS and Debian
    shell_command = ["/opt/homebrew/bin/speedtest",
                     # TODO enable after good servers are found "--server-id={}".format(selected_speedtest_server_id),
                     "--precision=0",
                     "--progress=no",
                     "--format=json", ]
    print("\nRunning speedtest shell command [{}]".format(" ".join(shell_command)))

    # Run the speedtest using subprocess, skip parsing if the executable doesn't exist
    try:
        # https://stackoverflow.com/questions/89228/how-do-i-execute-a-program-or-call-a-system-command
        # https://docs.python.org/3/library/subprocess.html#
        # NOTE that the first time this is run on a system, the license will need to be agreed to interactively
        completed_process = subprocess.run(shell_command, capture_output=True, timeout=60)
    except FileNotFoundError as e:
        print("Speedtest shell command not found, error {}".format(e))
        return
    except subprocess.TimeoutExpired as e:
        print("Speedtest took too long, error: {}".format(e))
        return

    # Check if the process returned an error code and skip parsing if so
    if completed_process.returncode != 0:
        print("Failed to run speedtest shell command, skipping submission. Error: {}".format(completed_process.stderr))
        return

    # Otherwise, interpret the results. First convert stdout to JSON object
    # Also decode the stdout using the correct encoding
    # https://stackoverflow.com/questions/45909639/subprocess-stdout-string-decoding-not-working
    json_data = loads(completed_process.stdout.decode())
    print("JSON data is [{}]".format(json_data))

    # Extract values from the JSON
    ping_ms = fetch_value_from_json(json_data, "ping.latency")
    download_kbps = fetch_value_from_json(json_data, "download.bandwidth")
    upload_kbps = fetch_value_from_json(json_data, "upload.bandwidth")
    server_id = fetch_value_from_json(json_data, "server.id")

    # Convert Kbps results to Mbps, dividing by 125000. Also round to nearest integer
    # https://www.matisse.net/bitcalc
    # IEEE kilobyte is 1000 bytes, not 1024 bytes
    # IEEE megabit is 125 kilobytes, not 128 kilobytes
    download_mbps = round(download_kbps / 125000)
    upload_mbps = round(upload_kbps / 125000)
    ping_ms = round(ping_ms)

    # Get the current time since Epoch in seconds, used to set the record time of data going into Influx
    epoch_time_seconds = int(time())
    # Format the rest of the Line Protocol, forming together the measurement, tags, field set, and time
    line_protocol_full_string = "speedtest,serverid={} ping={},download={},upload={} {}".format(
        server_id, ping_ms,
        download_mbps,
        upload_mbps,
        epoch_time_seconds)
    print("Converted data into Line Protocol: {}".format(line_protocol_full_string))
    send_data_to_influx([line_protocol_full_string])
    print("Completed writing speedtest data to Influx!")


if __name__ == '__main__':
    wait_seconds = randint(0, 10)
    print("Adding {} second(s) of jitter before executing".format(wait_seconds))
    sleep(wait_seconds)
    collect_and_write_speedtest_readings()
