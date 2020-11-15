#!/usr/bin/sh
# macOS `sh` is located at /bin/sh for 3.2 or /usr/local/bin/bash if installed with Homebrew
# *nix is /usr/bin/bash but I installed bash 5.0 manually to /usr/local/sbin/bash on CentOS

# This script pulls data from ESP8266 WiFi smart outlets flashed with Tasmota firmware


# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
# Add an `x` for printing out every line automatically, for debugging
set -euo pipefail

# Add jitter by sleeping for a random amount of time (between 0-10 seconds).
# https://servercheck.in/blog/little-jitter-can-help-evening-out-distributed
wait_seconds=$(( RANDOM %= 10 ))
echo "Adding $wait_seconds second wait to introduce jitter..."
sleep $wait_seconds

# source will load the lines of the credentials file as variables
# Format in the file is `VARNAME="VARVALUE"` with one per line
source "/root/creds.source"

# List the IP addresses or host names that we'll connect to
# https://linuxhint.com/bash_loop_list_strings/
declare -a TasmotaIpArray=(
    "lamp.brad" # Lightstory WP5 plug controlling a lamp
    "tv.brad" # Oittm WS01 in-wall outlet controlling  a TV
)

# List the device names that will be sent to InfluxDB. This should be a 1:1 mapping with the above array
declare -a InfluxDeviceArray=(
    "lamp"
    "tv"
)

# Iterate the string array using for loop
# https://stackoverflow.com/questions/8880603/loop-through-an-array-of-strings-in-bash
# get length of an array
arraylength=${#TasmotaIpArray[@]}

# use for loop to read all values and indexes
# https://github.com/koalaman/shellcheck/wiki/SC2004 no need for $
for (( i=1; i<arraylength+1; i++ ));
do
    echo "$i" "/" "${arraylength}" ":" "${TasmotaIpArray[$i-1]}" "to" "${InfluxDeviceArray[$i-1]}"
    # Get all the Tasmota status information using the command Status 0 (%20 is a space)
    # Use the IP array for one-indexed values
    # https://stackoverflow.com/questions/3742983/how-to-get-the-contents-of-a-webpage-in-a-shell-variable
    # --silent to hide the download prgress from the output
    # https://unix.stackexchange.com/questions/94604/does-curl-have-a-timeout/94612
    # --max-time to time out the operation if the link is down
    # || true because pipefail -e recognizes curl no response as a failure and will end the script here otherwise
    webdata=$(curl --silent "${TasmotaIpArray[$i-1]}/cm?cmnd=Status%200" --max-time 5 || true)

    # Use jq to parse the JSON response to get the uptime. Should be present on all Tasmota devices
    # https://unix.stackexchange.com/questions/121718/how-to-parse-json-with-shell-scripting-in-linux
    uptime_seconds=$(echo "$webdata" | jq -r '.StatusSTS.UptimeSec')
    # Also get the current switch power state. 1 is on, 0 is off
    power_state=$(echo "$webdata" | jq -r '.Status.Power')

    if [[ "$uptime_seconds" == "null" || "$power_state" == "null" ]]
    then
        echo "Uptime or power state was null, exiting early"
        exit 1
    fi

    printf "Uptime is $uptime_seconds seconds, power state is $power_state"

    # Get various power usage data for the Oittm plug. These should be null for the lamp
    total_kwh=$(        echo "$webdata" | jq -r '.StatusSNS.ENERGY.Total')
    power_voltage=$(    echo "$webdata" | jq -r '.StatusSNS.ENERGY.Voltage')
    power_watts=$(      echo "$webdata" | jq -r '.StatusSNS.ENERGY.Power')
    power_amps=$(       echo "$webdata" | jq -r '.StatusSNS.ENERGY.Current')
    power_voltamps=$(   echo "$webdata" | jq -r '.StatusSNS.ENERGY.ApparentPower')
    power_factor=$(     echo "$webdata" | jq -r '.StatusSNS.ENERGY.Factor')

    # We'll append the power usage as one big chunk if all values are not set to the string "null"
    power_influx_data=""
    if [[ "$total_kwh" != "null" && "$power_voltage" != "null" && "$power_watts" != "null" && "$power_amps" != "null" && "$power_voltamps" != "null" && "$power_factor" != "null" ]]
    then
        power_influx_data=",kilowattHours=$total_kwh,voltage=$power_voltage,watts=$power_watts,amps=$power_amps,voltAmps=$power_voltamps,powerFactor=$power_factor"
    fi
    printf ", power usage is [$power_influx_data]\n"

    printf "\nPosting data to InfluxDB...\n\n"
    # Get seconds since Epoch, which is timezone-agnostic
    # https://serverfault.com/questions/151109/how-do-i-get-the-current-unix-time-in-milliseconds-in-bash
    epoch_seconds=$(date +%s)

    # Submit all values as one record to InfluxDB
    curl -i -XPOST 'http://influx.brad:8086/write?db=local_reporting&precision=s' -u "$INFLUX1USER:$INFLUX1PASS" --data-binary \
        "tasmota,device=${InfluxDeviceArray[$i-1]} uptime=$uptime_seconds,powerState=$power_state$power_influx_data $epoch_seconds"

done