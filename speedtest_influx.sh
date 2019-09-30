#!/usr/local/sbin/bash
# macOS `sh` is located at /bin/sh for 3.2 or /usr/local/bin/bash if installed with Homebrew
# *nix is /usr/bin/bash but I installed bash 5.0 manually to /usr/local/sbin/bash on CentOS

# This script uses the `speedtest-cli` utility (2.1.2 latest) to calculate internet speeds and send them to InfluxDB

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euo pipefail


# Run the speedtest using the `speedtest-cli` installed by pip at /opt/rh/rh-python36/root/usr/bin/speedtest-cli
# https://github.com/sivel/speedtest-cli/releases
# Determine which servers by using `speedtest-cli --list`
speedtestversion=$(/opt/rh/rh-python36/root/usr/bin/speedtest-cli --version | awk '/speedtest-cli/{print $2}')
echo "Running speedtest-cli version $speedtestversion which can take ~10s"
speedtestresult=$(/opt/rh/rh-python36/root/usr/bin/speedtest-cli --simple --server 603 --server 5754 --server 17587 --server 18531)

# Use `awk` to get the numerical values from the lines
ping=$(echo "$speedtestresult" | awk '/Ping/{print $2}')
download=$(echo "$speedtestresult" | awk '/Download/{print $2}')
upload=$(echo "$speedtestresult" | awk '/Upload/{print $2}')

echo "Ping was $ping ms and download was $download Mbit/s and upload was $upload Mbit/s. Sending to InfluxDB..."

#Write to the database. Separate calls since each has its own metric value as well as value.
/usr/bin/curl -i -XPOST 'http://10.1.1.7:8086/write?db=local_reporting' --data-binary "speedtest,metric=ping value=$ping"
/usr/bin/curl -i -XPOST 'http://10.1.1.7:8086/write?db=local_reporting' --data-binary "speedtest,metric=download value=$download"
/usr/bin/curl -i -XPOST 'http://10.1.1.7:8086/write?db=local_reporting' --data-binary "speedtest,metric=upload value=$upload"
