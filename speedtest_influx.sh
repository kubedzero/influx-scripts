#!/usr/local/sbin/bash
# macOS `sh` is located at /bin/sh for 3.2 or /usr/local/bin/bash if installed with Homebrew
# *nix is /usr/bin/bash but I installed bash 5.0 manually to /usr/local/sbin/bash on CentOS

# This script uses the `speedtest-cli` utility (2.1.2 latest) to calculate internet speeds and send them to InfluxDB

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euo pipefail


# Define an array of the speedtest server IDs we want to use, and randomize the order
# Determine which servers by using `/root/speedtest-cli --list`
# https://unix.stackexchange.com/questions/124478/how-to-randomize-the-output-from-seq
speedtestservers=(603 5754 17587 18531)
shuffledservers=($(printf "%d\n" "${speedtestservers[@]}" | shuf))

# Run the speedtest using the `speedtest-cli` hand-edited in the home dir to remove some XML server lists
# due to San Francisco servers otherwise missing. Apparently Speedtest changed its XML format in some of
# the URLs listed to something incompatible. 
# https://github.com/sivel/speedtest-cli/releases
speedtestversion=$(/root/speedtest-cli --version | awk '/speedtest-cli/{print $2}')
echo "Running speedtest-cli version $speedtestversion with random server order ${shuffledservers[@]}. This can take ~10s"
speedtestresult=$(/root/speedtest-cli --simple --server ${shuffledservers[0]} --server ${shuffledservers[1]} --server ${shuffledservers[2]} --server ${shuffledservers[3]})

# Use `awk` to get the numerical values from the lines
ping=$(echo "$speedtestresult" | awk '/Ping/{print $2}')
download=$(echo "$speedtestresult" | awk '/Download/{print $2}')
upload=$(echo "$speedtestresult" | awk '/Upload/{print $2}')

echo "Ping: $ping ms. DL: $download Mbit/s. UL: $upload Mbit/s. Sending to InfluxDB..."

#Write to the database. Separate calls since each has its own metric value as well as value.
/usr/bin/curl -i -XPOST 'http://influx.brad:8086/write?db=local_reporting' --data-binary "speedtest,metric=ping value=$ping"
/usr/bin/curl -i -XPOST 'http://influx.brad:8086/write?db=local_reporting' --data-binary "speedtest,metric=download value=$download"
/usr/bin/curl -i -XPOST 'http://influx.brad:8086/write?db=local_reporting' --data-binary "speedtest,metric=upload value=$upload"