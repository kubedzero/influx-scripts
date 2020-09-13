#!/usr/bin/sh
# NOTE: /bin/sh on macOS, /usr/bin/sh on CentOS

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euo pipefail

# Get per-thread CPU utilization and memory utilization


# Call snmpwalk to get all the SNMP data from ESXi. -m MIB-FILE to define a mib file to use if we
# want to specify a particular object. -c public to identify the community. -v 2c to specify the
# SNMP version. Pipe the output to grep to grab only the CPU load, and store it.
bulkData=$(snmpwalk -m ALL -c public -v 2c esxi.brad|grep HOST-RESOURCES-MIB::hrProcessorLoad)
echo $bulkData
# Parse out CPU usage and get just the number
# The quotes around bulkdata preserve the newlines from grep, otherwise it becomes one line
# The quotes around the grep make the whitespace inclusive, so 1 doesn't grab 1, 10, 11, etc.
# Then cut out the first N characters from each line to leave only the number value
cpu1=$(echo "$bulkData" | grep "HOST-RESOURCES-MIB::hrProcessorLoad.1 " | cut -c 50-)
cpu2=$(echo "$bulkData" | grep HOST-RESOURCES-MIB::hrProcessorLoad.2 | cut -c 50-)
cpu3=$(echo "$bulkData" | grep HOST-RESOURCES-MIB::hrProcessorLoad.3 | cut -c 50-)
cpu4=$(echo "$bulkData" | grep HOST-RESOURCES-MIB::hrProcessorLoad.4 | cut -c 50-)
cpu5=$(echo "$bulkData" | grep HOST-RESOURCES-MIB::hrProcessorLoad.5 | cut -c 50-)
cpu6=$(echo "$bulkData" | grep HOST-RESOURCES-MIB::hrProcessorLoad.6 | cut -c 50-)
cpu7=$(echo "$bulkData" | grep HOST-RESOURCES-MIB::hrProcessorLoad.7 | cut -c 50-)
cpu8=$(echo "$bulkData" | grep HOST-RESOURCES-MIB::hrProcessorLoad.8 | cut -c 50-)
cpu9=$(echo "$bulkData" | grep HOST-RESOURCES-MIB::hrProcessorLoad.9 | cut -c 50-)
cpu10=$(echo "$bulkData" | grep HOST-RESOURCES-MIB::hrProcessorLoad.10 | cut -c 51-)
cpu11=$(echo "$bulkData" | grep HOST-RESOURCES-MIB::hrProcessorLoad.11 | cut -c 51-)
cpu12=$(echo "$bulkData" | grep HOST-RESOURCES-MIB::hrProcessorLoad.12 | cut -c 51-)

# Get the SSD/datastore name with `esxcli storage core device list |grep t10`
datastoreDeviceName=t10.NVMe____Samsung_SSD_970_PRO_512GB_______________803BB19155382500
# Now get the SSD info from the remote host using passwordless SSH
hwinfo=$(ssh -t root@esxi.brad "esxcli storage core device smart get --device-name $datastoreDeviceName")

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
driveTemp=$(echo $driveTemp | tr -s ' ')

# Use IFS to split into an array with space delimiter
IFS=' ' read -ra driveTempArr <<< "$driveTemp"

# Get the third element, since "Drive" is 0, "Temperature" is 1, current temp is 2, and max allowed temp is 3
driveTempC=${driveTempArr[2]}

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
echo -e "datastoreTemp: $driveTempC C\n"


# Write the data to the database
curl -i -XPOST 'http://influx.brad:8086/write?db=local_reporting' --data-binary "esxi_stats,host=esxi1,type=cpu_usage cpu_num1=$cpu1,cpu_num2=$cpu2,cpu_num3=$cpu3,cpu_num4=$cpu4,cpu_num5=$cpu5,cpu_num6=$cpu6,cpu_num7=$cpu7,cpu_num8=$cpu8,cpu_num9=$cpu9,cpu_num10=$cpu10,cpu_num11=$cpu11,cpu_num12=$cpu12,datastoreTempC=$driveTempC"


# Now get the hardware info from the remote host using passwordless SSH
hwinfo=$(ssh -t root@esxi.brad "esxcfg-info --hardware")

# Try to find the memory information
while read -r line; do
    # Check if we have the line we are looking for
    if [[ $line == *"Kernel Memory"* ]]
    then
        kmemline=$line
    fi
    if [[ $line == *"-Free."* ]]
    then
        freememline=$line
    fi
done <<< "$hwinfo"

# Remove the long string of .s
kmemline=$(echo $kmemline | tr -s '[.]')
freememline=$(echo $freememline | tr -s '[.]')

# Parse out the memory values from the strings
# First split on the only remaining . in the strings
IFS='.' read -ra kmemarr <<< "$kmemline"
kmem=${kmemarr[1]}
IFS='.' read -ra freememarr <<< "$freememline"
freemem=${freememarr[1]}
# Now break it apart on the space
IFS=' ' read -ra kmemarr <<< "$kmem"
kmem=${kmemarr[0]}
IFS=' ' read -ra freememarr <<< "$freemem"
freemem=${freememarr[0]}

# Now we can finally calculate used percentage
used=$((kmem - freemem))
used=$((used * 100))
pcent=$((used / kmem))


echo "Memory Used %: $pcent%"
echo "Memory Used: $used"
echo -e "Memory Free: $freemem\n"

# Get seconds since Epoch, which is timezone-agnostic
# https://serverfault.com/questions/151109/how-do-i-get-the-current-unix-time-in-milliseconds-in-bash
epochseconds=$(date +%s)

# Write the data to the database
curl -i -XPOST 'http://influx.brad:8086/write?db=local_reporting&precision=s' --data-binary "esxi_stats,host=esxi1,type=memory_usage percent=$pcent,free=$freemem,used=$used $epochseconds"