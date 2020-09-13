#!/usr/local/sbin/bash
# macOS `sh` is located at /bin/sh for 3.2 or /usr/local/bin/bash if installed with Homebrew
# *nix is /usr/bin/bash but I installed bash 5.0 manually to /usr/local/sbin/bash on CentOS

# This script uses the Ookla official speedtest utility (1.0.0.2 latest) to calculate internet speeds and send them to InfluxDB

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euo pipefail


# Define an array of the speedtest server IDs we want to use, and pick a random one
# https://www.christianroessler.net/tech/2015/bash-array-random-element.html
speedtestservers=(603 5754 17587 18531)
selectedserver=${speedtestservers[$RANDOM % ${#speedtestservers[@]}]}

# Run the speedtest https://www.speedtest.net/apps/cli
# - Use the randomly selected server from the list
# - Turn precision of speeds to 0 decimal places
# - Disable progress updates, getting only the final values
echo "Running speed test, this may take a few seconds..."
speedtestresult=$(/usr/bin/speedtest --server-id="$selectedserver" --precision=0 --progress=no)

# Use `awk` to get the numerical values from the lines
ping=$(echo "$speedtestresult" | awk '/Latency/{print $2}')
download=$(echo "$speedtestresult" | awk '/Download/{print $3}')
upload=$(echo "$speedtestresult" | awk '/Upload/{print $3}')

echo "Server ID: $selectedserver. Ping: $ping ms. DL: $download Mbps. UL: $upload Mbps. Sending to InfluxDB..."

# Get seconds since Epoch, which is timezone-agnostic
# https://serverfault.com/questions/151109/how-do-i-get-the-current-unix-time-in-milliseconds-in-bash
epochseconds=$(date +%s)

# Write to the database, including the timestamp for a precision of seconds versus default nanoseconds
# Store serverID as a tag rather than a field, as we may want to query on it
/usr/bin/curl -i -XPOST 'http://influx.brad:8086/write?db=local_reporting&precision=s' --data-binary "speedtest,serverid=$selectedserver ping=$ping,download=$download,upload=$upload $epochseconds"