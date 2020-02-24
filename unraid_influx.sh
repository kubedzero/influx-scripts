#!/bin/sh
# NOTE: /bin/sh on macOS, /usr/bin/sh on CentOS

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail

# Fetch HDD active/standby states, temp, CPU, RAM, and more from unRAID

# Assume passwordless SSH has been set up and run a command on UnRAID to fetch
# Then parse the value and update the passback value
# $1 is the drive letter (sda, sdb) and $2 is the passback value
getActiveStandbyState () {

    # https://www.cyberciti.biz/faq/unix-linux-execute-command-using-ssh/
    # https://stackoverflow.com/questions/22009364/is-there-a-try-catch-command-in-bash
    # https://superuser.com/questions/457316/how-to-remove-connection-to-xx-xxx-xx-xxx-closed-message
    # run a remote command on the host and store its value, avoiding "Connection to x closed" message
    # run it with an OR conditional so a bad remote command doesn't cause `set` to end the execution
    rawResponse=$(ssh -t -o LogLevel=QUIET root@poorbox.brad "hdparm -C /dev/$1 2>&1") || printf "SSH remote command failure for /dev/$1. "

    # if the response contains "No such file or directory" in the response
    # or "missing sense data" the disk isn't installed so we should mark as -1 error.
    # Else if it contains "active/idle" we shouldmark as 1.
    # lse if it contains "standby" we should mark 0
    # https://stackoverflow.com/questions/229551/how-to-check-if-a-string-contains-a-substring-in-bash
    # https://linuxize.com/post/bash-if-else-statement/
    if [[ $rawResponse == *"No such file or directory"* ]]; then
        echo "Disk /dev/$1 is not installed, setting Active state to -1"
        diskState=-1
    elif [[ $rawResponse == *"missing sense data"* ]]; then
        echo "Disk /dev/$1 is invalid, setting Active state to -1"
        diskState=-1
    elif [[ $rawResponse == *"active/idle"* ]]; then
        echo "Disk /dev/$1 is active/idle, setting Active state to 1"
        diskState=1
    elif [[ $rawResponse == *"standby"* ]]; then
        echo "Disk /dev/$1 is in standby, setting Active state to 0"
        diskState=0
    else
        echo "Unhandled response, setting Active state to -1"
        diskState=0
    fi

    # set passback value to the parsed value
    eval "$2=$diskState"
}

# Assume passwordless SSH to fetch and parse temperature and update the passback value
# $1 is the drive letter (sda, sdb), $2 is the Active state, $3 is the passback value
getDiskTemp () {

    # https://www.tldp.org/LDP/abs/html/comparison-ops.html
    # Only process if the status code is not in an error state, aka 0 or 1. Don't wrap integer in quotes
    # Can also do if (( $(bc <<< "$2 > -1") )) ; then
    if [ $2 -gt -1 ]; then

        # https://www.cyberciti.biz/faq/unix-linux-execute-command-using-ssh/
        # https://superuser.com/questions/457316/how-to-remove-connection-to-xx-xxx-xx-xxx-closed-message
        # https://unix.stackexchange.com/questions/66170/how-to-ssh-on-multiple-ipaddress-and-get-the-output-and-error-on-the-local-nix
        # run a remote command on the host and store its value, avoiding "Connection to x closed" message
        # run it with an OR conditional so a bad remote command doesn't cause `set` to end the execution
        # make sure STDERR is being redirected to STDOUT the way the normal shell is configured
        rawResponse=$(ssh -t -o LogLevel=QUIET root@poorbox.brad "smartctl -A /dev/$1 2>&1")  || printf "SSH remote command failure for /dev/$1. "

        # https://superuser.com/questions/241018/how-to-replace-multiple-spaces-by-one-tab
        # https://stackoverflow.com/questions/800030/remove-carriage-return-in-unix
        # Find line mentioning Temp, reduce repeated spaces to one, split on space, grab field, remove carriage return
        diskTemp=$(echo "$rawResponse" | grep "Temperature" | tr --squeeze-repeats '[:space:]' | cut -d ' ' -f10 | tr -d '\r')

        # https://www.cyberciti.biz/faq/unix-linux-bash-script-check-if-variable-is-empty/
        # if variable is empty, make sure to populate it with an error value
        if [ -z "$diskTemp" ]; then
            echo "Disk temperature of /dev/$1 was empty. Setting to -1"
            diskTemp=-1
        else
            echo "Disk temperature of /dev/$1 is [$diskTemp]"
        fi

    else
        echo "Disk /dev/$1 is not installed, setting temp to -1"
        diskTemp=-1
    fi

    # set passback value to the parsed value
    eval "$3=$diskTemp"
}

# https://www.unix.com/unix-for-dummies-questions-and-answers/123480-initializing-multiple-variables-one-statement.html
# Define our HDD active/standby variables
sdaActive=sdbActive=sdcActive=sddActive=sdeActive=sdfActive=sdgActive=sdhActive="UNFILLED"

# Fetch HDD states with passwordless SSH executing hdparm
echo -e "\n\nGetting Disk States"
getActiveStandbyState "sda" sdaActive
getActiveStandbyState "sdb" sdbActive
getActiveStandbyState "sdc" sdcActive
getActiveStandbyState "sdd" sddActive
getActiveStandbyState "sde" sdeActive
getActiveStandbyState "sdf" sdfActive
getActiveStandbyState "sdg" sdgActive
getActiveStandbyState "sdh" sdhActive

# Use the HDD Active state and passwordless SSH to get temperature value
# Define our HDD temp variables
sdaTempC=sdbTempC=sdcTempC=sddTempC=sdeTempC=sdfTempC=sdgTempC=sdhTempC="UNFILLED"

# Fetch HDD states with passwordless SSH executing smartctl
echo -e "\n\nGetting Disk Temperatures"
getDiskTemp "sda" $sdaActive sdaTempC
getDiskTemp "sdb" $sdbActive sdbTempC
getDiskTemp "sdc" $sdcActive sdcTempC
getDiskTemp "sdd" $sddActive sddTempC
getDiskTemp "sde" $sdeActive sdeTempC
getDiskTemp "sdf" $sdfActive sdfTempC
getDiskTemp "sdg" $sdgActive sdgTempC
getDiskTemp "sdh" $sdhActive sdhTempC

#Write the data to the database
echo -e "\n\nPosting data to InfluxDB\n"
curl -i -XPOST 'http://influx.brad:8086/write?db=local_reporting' --data-binary "unraid,host=poorbox,type=diskActive sdaActive=$sdaActive,sdbActive=$sdbActive,sdcActive=$sdcActive,sddActive=$sddActive,sdeActive=$sdeActive,sdfActive=$sdfActive,sdgActive=$sdgActive,sdhActive=$sdhActive"
curl -i -XPOST 'http://influx.brad:8086/write?db=local_reporting' --data-binary "unraid,host=poorbox,type=diskTemp sdaTempC=$sdaTempC,sdbTempC=$sdbTempC,sdcTempC=$sdcTempC,sddTempC=$sddTempC,sdeTempC=$sdeTempC,sdfTempC=$sdfTempC,sdgTempC=$sdgTempC,sdhTempC=$sdhTempC"