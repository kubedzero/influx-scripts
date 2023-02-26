#!/usr/bin/sh
# NOTE: /bin/sh on macOS, /usr/bin/sh on CentOS

# Gets APC UPS information using its NMC2 network management card and SNMPv3
# https://www.apc.com/us/en/product/SFPMIB441/powernet-mib-v4-4-1/
# https://www.apc.com/us/en/faqs/FA156048/

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

# Function to take an OID, name and passback variable, call SNMP, and format the return
# https://stackoverflow.com/questions/12722095/how-do-i-use-floating-point-arithmetic-in-bash
# https://linuxize.com/post/bash-functions/#passing-arguments-to-bash-functions
# https://stackoverflow.com/questions/3236871/how-to-return-a-string-value-from-a-bash-function
callSnmp () {
  echo "Fetching OID of $1 to get $2"
  rawValue=$(snmpget -v 3 -u centos -O qUv apc.brad "$1")

  echo "Raw value of $2 is $rawValue, converting..."
  convertedValue=$(echo "1k $rawValue 10 /p" | dc)
  echo -e "Output value of $2 is $convertedValue\n"

  # set passback value to the parsed value
  eval "$3=$convertedValue"

  # set return status code as success
  return 0
}

# Use SNMP to fetch the UPS values from the Network Management Card 
utilVoltage="UNFILLED"
upsTemp="UNFILLED"
loadPercent="UNFILLED"
loadCurrent="UNFILLED"

echo "Reading values using SNMP"
callSnmp ".1.3.6.1.4.1.318.1.1.1.3.3.1.0" "upsHighPrecInputVoltage", utilVoltage
callSnmp ".1.3.6.1.4.1.318.1.1.1.2.3.2.0" "upsHighPrecBatteryTemperature", upsTemp
callSnmp ".1.3.6.1.4.1.318.1.1.1.4.3.3.0" "upsHighPrecOutputLoad", loadPercent
callSnmp ".1.3.6.1.4.1.318.1.1.1.4.3.4.0" "upsHighPrecOutputCurrent", loadCurrent

# Validate the data, exiting early if any value is unfilled
if [[ $utilVoltage == "UNFILLED" || $upsTemp == "UNFILLED" || $loadPercent == "UNFILLED" || $loadCurrent == "UNFILLED" ]]; then
    echo "Some value was unfilled, please fix to submit data to InfluxDB"
    exit 1
fi

# Get seconds since Epoch, which is timezone-agnostic
# https://serverfault.com/questions/151109/how-do-i-get-the-current-unix-time-in-milliseconds-in-bash
epoch_seconds=$(date +%s)

printf "\nPosting data to InfluxDB\n\n"
# write the data to the database. No need to check if values are filled because they would exit if empty.
curl -i -XPOST 'http://localhost:8086/write?db=local_reporting&precision=s' -u "$INFLUX1USER:$INFLUX1PASS" --data-binary "ups_data,ups=apc utilVoltage=$utilVoltage,upsTemp=$upsTemp,loadPercent=$loadPercent,loadCurrent=$loadCurrent $epoch_seconds"