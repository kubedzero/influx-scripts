#!/usr/bin/sh

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euo pipefail

#
# Get USB-connected Cyberpower UPS information using the powerpanel package's pwrstat utility
#

# store the output of pwrstat -status. Use the full path, otherwise cron can't run it.
bulkData=$(/usr/sbin/pwrstat -status)

# Bash 4 support required for readarray -t y <<<"$bulkData". Splits into an array, one line per element
readarray -t linesplitdata <<<"$bulkData"

# get length of an array
arraylength=${#linesplitdata[@]}

# initialize variables
utilVoltage="UNFILLED"
outputVoltage="UNFILLED"
batteryCapacity="UNFILLED"
remainingRuntime="UNFILLED"
loadWatts="UNFILLED"
loadPercent="UNFILLED"


# Iterate the string array using for loop
# https://stackoverflow.com/questions/8880603/loop-through-an-array-of-strings-in-bash

# use for loop to read all values and indexes
for (( i=1; i<${arraylength}+1; i++ ));
	do
		# https://stackoverflow.com/questions/22712156/bash-if-string-contains-in-case-statement
		# check each line of the input for the type we want
		case ${linesplitdata[$i-1]} in
	    *"Utility Voltage..."*)
			# https://unix.stackexchange.com/questions/191122/how-to-split-the-string-after-and-before-the-space-in-shell-script
			# print the line, split on space, take the field containing the number
	        utilVoltage=$(echo ${linesplitdata[$i-1]} | cut -d' ' -f3 );;
	    *"Output Voltage..."*)
	        outputVoltage=$(echo ${linesplitdata[$i-1]} | cut -d' ' -f3 );;
	    *"Battery Capacity..."*)
	        batteryCapacity=$(echo ${linesplitdata[$i-1]} | cut -d' ' -f3 );;
	    *"Remaining Runtime..."*)
	        remainingRuntime=$(echo ${linesplitdata[$i-1]} | cut -d' ' -f3 );;
	    *"Load..."*)
	        loadWatts=$(echo ${linesplitdata[$i-1]} | cut -d' ' -f2 )
	        # isolate the second number in the line by splitting and splitting again
	        loadPercent=$(echo ${linesplitdata[$i-1]} | cut -d' ' -f3 | cut -d'(' -f2);;
	esac
done

echo "utilVoltage is $utilVoltage"
echo "outputVoltage is $outputVoltage"
echo "batteryCapacity is $batteryCapacity"
echo "remainingRuntime is $remainingRuntime"
echo "loadWatts is $loadWatts"
echo -e "loadPercent is $loadPercent\n"

# write the data to the database if all values are filled
if [[ $utilVoltage != "UNFILLED" || $outputVoltage != "UNFILLED" || $batteryCapacity != "UNFILLED" || $remainingRuntime != "UNFILLED" || $loadWatts != "UNFILLED" || $loadPercent != "UNFILLED" ]]; then
	curl -i -XPOST 'http://10.1.1.7:8086/write?db=local_reporting' --data-binary "ups_data,ups=cyberpower utilVoltage=$utilVoltage,outputVoltage=$outputVoltage,batteryCapacity=$batteryCapacity,remainingRuntime=$remainingRuntime,loadWatts=$loadWatts,loadPercent=$loadPercent"
else
	echo "Some value was unfilled, please fix to submit data to InfluxDB"
fi