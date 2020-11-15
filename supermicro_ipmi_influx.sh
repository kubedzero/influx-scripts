#!/usr/bin/sh
# NOTE: /bin/sh on macOS, /usr/bin/sh on CentOS

# Get Supermicro IPMI sensor information


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

# call ipmitool to get all physical sensor data collected by the motherboard, plus upper
# thresholds. -H defines the IP address to connect, -U for the user, -P for password, and
# sensor is one of many options for return data. Output data will be pipe-delimited with
# whitespace and will have the schema metricName, currentValue, unit, status, lower critical
# threshold, lower noncritical, lower ok, upper ok, upper noncritical, upper critical
# NOTE: /usr/bin/ipmitool on CentOS, /usr/local/bin/ipmitool on macOS
bulkData=$(ipmitool -H x9srw.brad -U ipminetworkuser -P ipminetworkpass sensor)
# echo "$bulkData"

# given bulkData + metricName + passback value, retrieves that metric's current value
# https://stackoverflow.com/questions/3236871/how-to-return-a-string-value-from-a-bash-function
# $1 is bulkData, $2 is metricName, $3 is passback value
getMetricValueFromBulkData () {

    # find line with our metric with grep
    # https://stackoverflow.com/questions/9018691/how-to-separate-fields-with-pipe-character-delimiter
    # split on pipe character
    # get second field with metricValue
    # https://stackoverflow.com/questions/369758/how-to-trim-whitespace-from-a-bash-variable
    # trim whitespace from the identified field
    # NOTE: unsure why whitespace before $ in parsedValue=$() breaks this, but it does
    parsedValue=$(echo "$bulkData" | grep "$1" | cut -d '|' -f2 | tr -d '[:space:]')

    echo "metricName $1 has a metricValue of $parsedValue"

    # Remove the na values and replace them with numerical values
    if [[ $parsedValue == "na" ]]
    then
        echo "replacing value [na] with -1"
        parsedValue=-1
    fi

    # set passback value to the parsed value
    eval "$2=$parsedValue"
}

# Initialize variables
cpuTempC="UNFILLED"
systemTempC="UNFILLED"
peripheralTempC="UNFILLED"
pchTempC="UNFILLED"
dimmA1TempC="UNFILLED"
dimmA2TempC="UNFILLED"
dimmB1TempC="UNFILLED"
dimmB2TempC="UNFILLED"
dimmC1TempC="UNFILLED"
dimmC2TempC="UNFILLED"
dimmD1TempC="UNFILLED"
dimmD2TempC="UNFILLED"
fan1rpm="UNFILLED"
fan2rpm="UNFILLED"
fan3rpm="UNFILLED"
fan4rpm="UNFILLED"
fan5rpm="UNFILLED"

# Call the function, note that the second argument is a reference rather than the value
# which is necessary to update the passed-in variable
getMetricValueFromBulkData "CPU Temp" cpuTempC
getMetricValueFromBulkData "System Temp" systemTempC
getMetricValueFromBulkData "Peripheral Temp" peripheralTempC
getMetricValueFromBulkData "PCH Temp" pchTempC
getMetricValueFromBulkData "P1-DIMMA1 TEMP" dimmA1TempC
getMetricValueFromBulkData "P1-DIMMA2 TEMP" dimmA2TempC
getMetricValueFromBulkData "P1-DIMMB1 TEMP" dimmB1TempC
getMetricValueFromBulkData "P1-DIMMB2 TEMP" dimmB2TempC
getMetricValueFromBulkData "P1-DIMMC1 TEMP" dimmC1TempC
getMetricValueFromBulkData "P1-DIMMC2 TEMP" dimmC2TempC
getMetricValueFromBulkData "P1-DIMMD1 TEMP" dimmD1TempC
getMetricValueFromBulkData "P1-DIMMD2 TEMP" dimmD2TempC
getMetricValueFromBulkData "FAN1" fan1rpm
getMetricValueFromBulkData "FAN2" fan2rpm
getMetricValueFromBulkData "FAN3" fan3rpm
getMetricValueFromBulkData "FAN4" fan4rpm
getMetricValueFromBulkData "FAN5" fan5rpm

# Get seconds since Epoch, which is timezone-agnostic
# https://serverfault.com/questions/151109/how-do-i-get-the-current-unix-time-in-milliseconds-in-bash
epoch_seconds=$(date +%s)

#Write the data to the database
printf "\nPosting data to InfluxDB\n\n"
curl -i -XPOST 'http://influx.brad:8086/write?db=local_reporting&precision=s' -u "$INFLUX1USER:$INFLUX1PASS" --data-binary "ipmi,host=x9srw,type=temp cpuTempC=$cpuTempC,systemTempC=$systemTempC,peripheralTempC=$peripheralTempC,pchTempC=$pchTempC,dimmA1TempC=$dimmA1TempC,dimmA2TempC=$dimmA2TempC,dimmB1TempC=$dimmB1TempC,dimmB2TempC=$dimmB2TempC,dimmC1TempC=$dimmC1TempC,dimmC2TempC=$dimmC2TempC,dimmD1TempC=$dimmD1TempC,dimmD2TempC=$dimmD2TempC $epoch_seconds
ipmi,host=x9srw,type=fan fan1rpm=$fan1rpm,fan2rpm=$fan2rpm,fan3rpm=$fan3rpm,fan4rpm=$fan4rpm,fan5rpm=$fan5rpm $epoch_seconds"