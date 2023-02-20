#!/usr/bin/sh
# NOTE: /bin/sh on macOS, /usr/bin/sh on CentOS

# Gets USB-connected APC UPS information using the apcupsd package's apcaccess utility


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

# Use apcaccess with -p <varname> to get a particular variable, and -u to remove units.
# This gives us the final value on its own. It will exit with code 1 if there is an error
# such as "Error contacting apcupsd @ localhost:3551: Connection refused"
echo "Reading values using apcaccess"
utilVoltage=$(/usr/sbin/apcaccess -u -p  LINEV)
upsTemp=$(/usr/sbin/apcaccess -u -p  ITEMP)
loadPercent=$(/usr/sbin/apcaccess -u -p  LOADPCT)
transferCount=$(/usr/sbin/apcaccess -u -p  NUMXFERS)


echo "utilVoltage is $utilVoltage"
echo "upsTemp is $upsTemp"
echo "loadPercent is $loadPercent"
echo -e "transferCount is $transferCount\n"

# Get seconds since Epoch, which is timezone-agnostic
# https://serverfault.com/questions/151109/how-do-i-get-the-current-unix-time-in-milliseconds-in-bash
epoch_seconds=$(date +%s)

printf "\nPosting data to InfluxDB\n\n"
# write the data to the database. No need to check if values are filled because they would exit if empty.
curl -i -XPOST 'http://localhost:8086/write?db=local_reporting&precision=s' -u "$INFLUX1USER:$INFLUX1PASS" --data-binary "ups_data,ups=apc utilVoltage=$utilVoltage,upsTemp=$upsTemp,loadPercent=$loadPercent,transferCount=$transferCount $epoch_seconds"