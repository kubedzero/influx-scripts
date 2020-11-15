#!/usr/local/sbin/bash
# macOS `sh` is located at /bin/sh for 3.2 or /usr/local/bin/bash if installed with Homebrew
# *nix is /usr/bin/bash but I installed bash 5.0 manually to /usr/local/sbin/bash on CentOS

# This script uses the Ookla official speedtest utility (1.0.0.2 latest) to calculate internet speeds and send them to InfluxDB


# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euo pipefail

# Add jitter by sleeping for a random amount of time (between 0-10 seconds).
# https://servercheck.in/blog/little-jitter-can-help-evening-out-distributed
wait_seconds=$(( RANDOM %= 10 ))
echo "Adding $wait_seconds second wait to introduce jitter..."
sleep $wait_seconds

# source will load the lines of the credentials file as variables
# Format in the file is `VARNAME="VARVALUE"` with one per line
source "/root/creds.source"

# Define an array of the speedtest server IDs we want to use, and pick a random one
# https://www.christianroessler.net/tech/2015/bash-array-random-element.html
speedtest_servers=(603 17587 18531 8228)
selected_server=${speedtest_servers[$RANDOM % ${#speedtest_servers[@]}]}

# Run the speedtest https://www.speedtest.net/apps/cli
# - Use the randomly selected server from the list
# - Turn precision of speeds to 0 decimal places
# - Disable progress updates, getting only the final values
echo "Running speed test, this may take a few seconds..."
speedtest_result=$(/usr/bin/speedtest --server-id="$selected_server" --precision=0 --progress=no)

# Use `awk` to get the numerical values from the lines
ping=$(echo "$speedtest_result" | awk '/Latency/{print $2}')
download=$(echo "$speedtest_result" | awk '/Download/{print $3}')
upload=$(echo "$speedtest_result" | awk '/Upload/{print $3}')

printf "Server ID: $selected_server. Ping: $ping ms. DL: $download Mbps. UL: $upload Mbps. Sending to InfluxDB...\n\n"

# Get seconds since Epoch, which is timezone-agnostic
# https://serverfault.com/questions/151109/how-do-i-get-the-current-unix-time-in-milliseconds-in-bash
epoch_seconds=$(date +%s)

# Write to the database, including the timestamp for a precision of seconds versus default nanoseconds
# Store serverID as a tag rather than a field, as we may want to query on it
/usr/bin/curl -i -XPOST 'http://localhost:8086/write?db=local_reporting&precision=s' -u "$INFLUX1USER:$INFLUX1PASS" --data-binary "speedtest,serverid=$selected_server ping=$ping,download=$download,upload=$upload $epoch_seconds"