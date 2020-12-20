#!/usr/bin/sh
# NOTE: /bin/sh on macOS, /usr/bin/sh on CentOS

# Fetch Unraid information via SNMP


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

# Call SNMP running on Unraid, specifying the community, version, IP, and block of data
bulk_snmp="$(snmpwalk -v 2c -c public poorbox.brad nsExtendOutLine)"
echo "Call to Unraid SNMP to fetch disk and share data complete. Begin parsing..."

# Define strings we'll update that send to influx
influx_disk_free="UNFILLED"
influx_share_free="UNFILLED"
influx_disk_temp="UNFILLED"
influx_disk_active="UNFILLED"
influx_mem_info="UNFILLED"

# Store the line count of bulk data
bulk_line_count=$(echo "$bulk_snmp" | wc -l)

# Iterate through each line of bulk data
# https://github.com/koalaman/shellcheck/wiki/SC2004 no need for $
for (( i=1; i<=bulk_line_count; i++ ));
do
    # Get the specific line of the string we want
    # https://stackoverflow.com/questions/15777232/how-can-i-echo-print-specific-lines-from-a-bash-variable
    line=$(sed -n "${i}"p <<< "$bulk_snmp")

    # check the line for the type of SNMP data we want
    # https://stackoverflow.com/questions/22712156/bash-if-string-contains-in-case-statement
    # The close paren ) marks the end of the case evaluation and is not part of the string match
    # The double semicolon marks the end of the case action
    case $line in
        *"diskfree"*)
            # Replace colons with equal signs, get 4th and 5th whitespace-separated values
            # https://github.com/koalaman/shellcheck/wiki/SC2001
            # Line example: NET-SNMP-EXTEND-MIB::nsExtendOutLine."diskfree".3 = STRING: disk2: 197598232576
            # Output example: disk2=197598232576
            current_disk_free=$(echo "${line//:/=}" | awk '{print $4$5}')

            # Confirm the value after = is numeric, otherwise go to next loop
            # https://unix.stackexchange.com/questions/151654/checking-if-an-input-number-is-an-integer
            string_to_check=$(echo "$line" | awk '{print $5}')
            if [[ -z "$string_to_check" || ! "$string_to_check" =~ ^[0-9]+$ ]]
            then
                echo "Skipping: Encountered an empty disk name or non-numeric free space"
                continue
            fi

            echo "Found disk free line: $current_disk_free"

            # If it's the first one, replace UNFILLED and don't trail a comma
            if [[ $influx_disk_free == "UNFILLED" ]]; then
                influx_disk_free="$current_disk_free"
            else
                # Add the value to the influx string separated by comma.
                influx_disk_free="$current_disk_free,$influx_disk_free"
            fi
            ;;
        *"sharefree"*)
            # Line example: NET-SNMP-EXTEND-MIB::nsExtendOutLine."sharefree".1 = STRING: Files: 3028310544384
            # Output example: Files=197598232576
            current_share_free=$(echo "${line//:/=}" | awk '{print $4$5}')

            # Confirm the value after = is numeric, otherwise go to next loop
            # https://unix.stackexchange.com/questions/151654/checking-if-an-input-number-is-an-integer
            string_to_check=$(echo "$line" | awk '{print $5}')
            if [[ -z "$string_to_check" || ! "$string_to_check" =~ ^[0-9]+$ ]]
            then
                echo "Skipping: Encountered an empty share name or non-numeric free space"
                continue
            fi

            echo "Found share free line: $current_share_free"

            # If it's the first one, replace UNFILLED and don't trail a comma
            if [[ $influx_share_free == "UNFILLED" ]]; then
                influx_share_free="$current_share_free"
            else
                # Add the value to the influx string separated by comma.
                influx_share_free="$current_share_free,$influx_share_free"
            fi
            ;;
        *"meminfo"*)
            # Line example: NET-SNMP-EXTEND-MIB::nsExtendOutLine."meminfo".1 = STRING: MemTotal: 25278668800
            # Output example: MemTotal=25278668800
            current_mem_info=$(echo "${line//:/=}" | awk '{print $4$5}')

            # Confirm the value after = is numeric, otherwise go to next loop
            # https://unix.stackexchange.com/questions/151654/checking-if-an-input-number-is-an-integer
            string_to_check=$(echo "$line" | awk '{print $5}')
            if [[ -z "$string_to_check" || ! "$string_to_check" =~ ^[0-9]+$ ]]
            then
                echo "Skipping: Encountered an memory or non-numeric memory bytes"
                continue
            fi

            echo "Found memory info: $current_mem_info"

            # If it's the first one, replace UNFILLED and don't trail a comma
            if [[ $influx_mem_info == "UNFILLED" ]]; then
                influx_mem_info="$current_mem_info"
            else
                # Add the value to the influx string separated by comma.
                influx_mem_info="$current_mem_info,$influx_mem_info"
            fi
            ;;
        *"disktemp"*)
            # Disk temp is a special measurement, as it also communicates standby state
            # An input of -2 is standby, -1 is error, >0 is active/idle temperature. 0 not used

            # Remove the colon : character from the name
            # https://stackoverflow.com/questions/13210880/replace-one-substring-for-another-string-in-shell-script
            # Line example: NET-SNMP-EXTEND-MIB::nsExtendOutLine."disktemp".1 = STRING: WDC_WD100EMAZ-00WJTA0_2ABCDAD: 44
            current_disk_name=$(echo "${line//:/}" | awk '{print $4}')
            current_disk_temp=$(echo "$line" | awk '{print $5}')
            if [[ -z "$current_disk_name$current_disk_temp" ]]
            then
                echo "Skipping: Encountered an empty disk name or temperature"
                continue
            fi

            # Calculate active state. -1 is error, 0 is standby, 1 is active/idle
            current_disk_active="-1"
            if [[ $current_disk_temp == "-2" ]]; then
                echo "Disk $current_disk_name in standby, setting active state to 0"
                current_disk_active=0
            elif [[ $current_disk_temp -gt 0 ]]; then
                echo "Disk $current_disk_name has temperature $current_disk_temp, setting active state to 1"
                current_disk_active=1
            else
                echo "Disk $current_disk_name temp value is $current_disk_temp, setting active state to -1"
            fi

            # Update the influx strings with this disk's active state and temperature

            # If it's the first one, replace UNFILLED and don't trail a comma
            if [[ $influx_disk_temp == "UNFILLED" ]]; then
                influx_disk_temp="$current_disk_name=$current_disk_temp"
            else
                # Add the value to the influx string separated by comma.
                influx_disk_temp="$current_disk_name=$current_disk_temp,$influx_disk_temp"
            fi

            # If it's the first one, replace UNFILLED and don't trail a comma
            if [[ $influx_disk_active == "UNFILLED" ]]; then
                influx_disk_active="$current_disk_name=$current_disk_active"
            else
                # Add the value to the influx string separated by comma.
                influx_disk_active="$current_disk_name=$current_disk_active,$influx_disk_active"
            fi
            ;;
    esac

done


# Now get the CPU data, which is in a separate SNMP output
printf "\nCalling SNMP again to grab a different OID\n"
# Call SNMP running on Unraid, specifying the community, version, IP, and block of data
bulk_snmp=$(snmpwalk -v 2c -c public poorbox.brad HOST-RESOURCES-MIB::hrProcessorLoad)
echo "Call to Unraid SNMP to fetch CPU complete. Begin parsing..."

# Remove the OID information to leave only the percent load value
# Input: HOST-RESOURCES-MIB::hrProcessorLoad.196609 = INTEGER: 61
# Output: 61
procLoadData=($(echo "$bulk_snmp" | sed -e 's/.*= INTEGER: //g'))

# Update array elements with core number alongside CPU percent
# Core numbers are zero-indexed
for ((i=0; i<${#procLoadData[@]}; i++));
do
    procLoadData[$i]="$i=${procLoadData[$i]}"
done

# Convert the array elements to a single comma separated line
influx_cpu_percent=$(IFS=, ; echo "${procLoadData[*]}")
echo "Processor CPU Percent values are $influx_cpu_percent"


# Validate the data, exiting early if some are empty or unfilled
if [[ -z "$influx_cpu_percent" || $influx_disk_free == "UNFILLED" || $influx_share_free == "UNFILLED" || $influx_disk_temp == "UNFILLED" || $influx_disk_active == "UNFILLED" || $influx_mem_info == "UNFILLED" ]]; then
    echo "Some value was unfilled, please fix to submit data to InfluxDB"
    exit 1
fi

# Get seconds since Epoch, which is timezone-agnostic
# https://serverfault.com/questions/151109/how-do-i-get-the-current-unix-time-in-milliseconds-in-bash
epoch_seconds=$(date +%s)

# Write the data to the database, one line per measurement
printf "\nPosting data to InfluxDB\n\n"
curl -i -XPOST 'http://localhost:8086/write?db=local_reporting&precision=s' -u "$INFLUX1USER:$INFLUX1PASS" --data-binary \
"unraid,host=poorbox,type=diskTemp $influx_disk_temp $epoch_seconds
unraid,host=poorbox,type=diskActive $influx_disk_active $epoch_seconds
unraid,host=poorbox,type=diskFree $influx_disk_free $epoch_seconds
unraid,host=poorbox,type=shareFree $influx_share_free $epoch_seconds
unraid,host=poorbox,type=cpuPercent $influx_cpu_percent $epoch_seconds
unraid,host=poorbox,type=memInfo $influx_mem_info $epoch_seconds"