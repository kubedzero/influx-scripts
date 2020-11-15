#!/usr/bin/sh
# NOTE: /bin/sh on macOS, /usr/bin/sh on CentOS

# Get per-thread CPU utilization and memory utilization


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

# Call snmpwalk to get data from ESXi
# -v 2c to specify the SNMP version
# -c public to identify the community
# Specify the IP, then the specific set of lines we want: hrProcessorLoad
# Example output: HOST-RESOURCES-MIB::hrProcessorLoad.1 = INTEGER: 11
bulkData=$(snmpwalk -v 2c -c public esxi.brad hrProcessorLoad)
echo "Call to ESXi SNMP to fetch CPU data complete. Begin parsing..."

# From the unformatted data, isolate a specific thread's line and the CPU %
cpu1=$(echo "$bulkData"  | grep "\.1 "  | awk '{print $4}')
cpu2=$(echo "$bulkData"  | grep "\.2 "  | awk '{print $4}')
cpu3=$(echo "$bulkData"  | grep "\.3 "  | awk '{print $4}')
cpu4=$(echo "$bulkData"  | grep "\.4 "  | awk '{print $4}')
cpu5=$(echo "$bulkData"  | grep "\.5 "  | awk '{print $4}')
cpu6=$(echo "$bulkData"  | grep "\.6 "  | awk '{print $4}')
cpu7=$(echo "$bulkData"  | grep "\.7 "  | awk '{print $4}')
cpu8=$(echo "$bulkData"  | grep "\.8 "  | awk '{print $4}')
cpu9=$(echo "$bulkData"  | grep "\.9 "  | awk '{print $4}')
cpu10=$(echo "$bulkData" | grep "\.10 " | awk '{print $4}')
cpu11=$(echo "$bulkData" | grep "\.11 " | awk '{print $4}')
cpu12=$(echo "$bulkData" | grep "\.12 " | awk '{print $4}')

echo "CPU1: $cpu1%"
echo "CPU2: $cpu2%"
echo "CPU3: $cpu3%"
echo "CPU4: $cpu4%"
echo "CPU5: $cpu5%"
echo "CPU6: $cpu6%"
echo "CPU7: $cpu7%"
echo "CPU8: $cpu8%"
echo "CPU9: $cpu9%"
echo "CPU10: $cpu10%"
echo "CPU11: $cpu11%"
echo "CPU12: $cpu12%"


# Get the SSD/datastore name manually with `esxcli storage core device list |grep t10`
datastoreDeviceName=t10.NVMe____Samsung_SSD_970_PRO_512GB_______________803BB19155382500
# Now get the SSD info from the remote host using passwordless SSH
# Use -o LogLevel=QUIET which avoids "Connection to x closed" message
# https://superuser.com/questions/457316/how-to-remove-connection-to-xx-xxx-xx-xxx-closed-message
hwinfo=$(ssh -t -o LogLevel=QUIET root@esxi.brad "esxcli storage core device smart get --device-name $datastoreDeviceName")
echo "Remote SSH call to ESXi to fetch SSD data complete. Begin parsing..."

# Try to find the SSD temp information from the lines of output
while read -r line; do
    # Check if the line contains the string
    if [[ $line == *"Drive Temperature"* ]]
    then
        driveTemp=$line
    fi
done <<< "$hwinfo"

# https://unix.stackexchange.com/questions/109835/how-do-i-use-cut-to-separate-by-multiple-whitespace
# Line should be similar to 'Drive Temperature         43     81         N/A    N/A'
# Reformat the line to remove consecutive spaces
driveTemp=$(echo "$driveTemp" | tr --squeeze-repeats ' ')

# Use IFS to split into an array with space delimiter
IFS=' ' read -ra driveTempArr <<< "$driveTemp"

# Get the third element, since "Drive" is 0, "Temperature" is 1, current temp is 2, and max allowed temp is 3
driveTempC=${driveTempArr[2]}

echo "datastoreTemp: $driveTempC C"


# Now get the hardware info from the remote host using passwordless SSH
# Use -o LogLevel=QUIET which avoids "Connection to x closed" message
# https://superuser.com/questions/457316/how-to-remove-connection-to-xx-xxx-xx-xxx-closed-message
hwinfo=$(ssh -t -o LogLevel=QUIET root@esxi.brad "esxcfg-info --hardware")
echo "Remote SSH call to ESXi to fetch RAM data complete. Begin parsing..."

# Try to find the memory information
# Input: |----Kernel Memory.........................................67073884 kilobytes
# Also remove everything but the digits
# https://stackoverflow.com/questions/17883661/how-to-extract-numbers-from-a-string
while read -r line; do
    # Check if we have the line we are looking for
    if [[ $line == *"Kernel Memory"* ]]
    then
        kmemline=$(echo "$line" | tr -d -c 0-9)
    fi
    if [[ $line == *"-Free."* ]]
    then
        freememline=$(echo "$line" | tr -d -c 0-9)
    fi
done <<< "$hwinfo"

# Convert to bytes, avoid kilobyte (1000 bytes) kibibyte (1024 bytes) misuse
# 4x16GB RAM = 64GB = 64 Gibibytes
# ESXi reports a kernel and physical memory of 67073884.
# Interpreted as kibibytes, this is 63.96 gibibytes
# Interpreted as kilobytes, this is 62.47 gibibytes
# We will ignore the ESXi-reported kilobyte string and interpret as kibibytes
# https://github.com/koalaman/shellcheck/wiki/SC2004 no need for $
# https://www.mirazon.com/storage-ram-size-doesnt-add/
kmem=$((kmemline * 1024))
freemem=$((freememline * 1024))

# Calculate used memory % as a float and used memory in bytes
# https://unix.stackexchange.com/questions/40786/how-to-do-integer-float-calculations-in-bash-or-other-languages-frameworks
used=$((kmem - freemem))
pcent=$(awk "BEGIN {print ($used/$kmem)*100}")


echo "Memory Used: $pcent%"
echo "Memory Used: $used bytes"
echo "Memory Free: $freemem bytes"


printf "\nPosting data to InfluxDB...\n\n"
# Get seconds since Epoch, which is timezone-agnostic
# https://serverfault.com/questions/151109/how-do-i-get-the-current-unix-time-in-milliseconds-in-bash
epoch_seconds=$(date +%s)

# Write the data to the database
curl -i -XPOST 'http://influx.brad:8086/write?db=local_reporting&precision=s' -u "$INFLUX1USER:$INFLUX1PASS" --data-binary "esxi_stats,host=esxi1,type=memory_usage percent=$pcent,free=$freemem,used=$used $epoch_seconds
esxi_stats,host=esxi1,type=cpu_usage cpu_num1=$cpu1,cpu_num2=$cpu2,cpu_num3=$cpu3,cpu_num4=$cpu4,cpu_num5=$cpu5,cpu_num6=$cpu6,cpu_num7=$cpu7,cpu_num8=$cpu8,cpu_num9=$cpu9,cpu_num10=$cpu10,cpu_num11=$cpu11,cpu_num12=$cpu12,datastoreTempC=$driveTempC $epoch_seconds"
