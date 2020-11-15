# README

This repository captures the various scripts used to capture the state of various appliances on the network and report them to InfluxDB. 



## Bash Versions

* Bash 3.x or 4.x is commonly installed by default, but one of the utilities I wanted to use, `readarray -d` is only available in newer versions.

* https://itnext.io/upgrading-bash-on-macos-7138bd1066ba explains why Bash 3.2 is still on macOS and how to get Bash 4 with Homebrew

  * https://apple.stackexchange.com/questions/55989/change-my-shell-to-a-different-bash-version-at-usr-local-bin-bash change the default shell per username by editing `/etc/shells` and then running `chsh -s /usr/local/bin/bash username` to set the version you want for your username.

  * ```
    [user@localhost ~]# cat /etc/shells 
    /bin/sh
    /bin/bash
    /usr/bin/sh
    /usr/bin/bash
    [user@localhost ~]# echo /usr/local/sbin/bash >> /etc/shells
    [user@localhost ~]# chsh -s /usr/local/sbin/bash user
    Changing shell for user.
    Shell changed.
    ```

* https://www.ramoonus.nl/2019/01/08/bash-5-0-installation-for-linux/ has instructions for installing Bash 5.x on Linux

  * ```
    sudo yum groupinstall "Development Tools" "Legacy Software Development"
    wget http://ftp.gnu.org/gnu/bash/bash-5.0.tar.gz
    tar xf bash-5.0.tar.gz
    cd bash-5.0
    ./configure
    make
    sudo make install
    sh
    ```

* DEFAULT: CentOS has Bash installed at `/usr/bin/sh` while macOS has it installed at `/bin/sh`

* NEW: CentOS has updated Bash installed at `/usr/local/sbin/bash` while macOS has it at `/usr/local/bin/bash` when installed via Homebrew



## Shell Scripts

* Most of my scripts are done entirely using Bash/CLI commands, as opposed to writing Python, Perl, PHP, or other scripts. 
* https://www.shellcheck.net/ can offer suggestions on optimizing or bug fixing shell scripts
  * For example, it corrected `speedtestresult=$(/usr/bin/speedtest --server-id=$selectedserver --precision=0 --progress=no)` to `speedtestresult=$(/usr/bin/speedtest --server-id="$selectedserver" --precision=0 --progress=no)`, wrapping in a "Double quote to prevent globbing and word splitting"
  * https://github.com/koalaman/shellcheck/wiki/SC2004 is another error, showing `echo $(($n + ${arr[i]}))` can be replaced by `echo $((n + arr[i]))` because "The `$` or `${..}` on regular variables in arithmetic contexts is unnecessary"
* https://github.com/lovesegfault/beautysh 
  * installed via pip 
  * It is helpful to format shell script files from the command line. Use with `beautysh esp_influx.sh esxi_influx.sh speedtest_influx.sh supermicro_ipmi_influx.sh unraid_influx.sh ups_influx.sh` to run on multiple files at once
* `command1 || command2` A double-pipe can follow a known failing command to offer an alternative command that will succeed. If there's a command that consistently throws error codes, https://stackoverflow.com/questions/22009364/is-there-a-try-catch-command-in-bash 
  * `rawResponse=$(ssh -t root@poorbox.brad "hdparm -C /dev/sdg") && echo "executing" || echo "executing"` works in the script. Run it with an OR conditional so a bad remote command doesn't cause `set` to end the execution



## Pip

* Package installer for Python

* https://pip.pypa.io/en/stable/

* Installation instructions are at https://pip.pypa.io/en/stable/installing/

* Alternative install is to install Python with Homebrew, as per https://docs.python-guide.org/starting/install3/osx/ `brew install python`

  * ```
    Python has been installed as
      /usr/local/bin/python3
    
    Unversioned symlinks `python`, `python-config`, `pip` etc. pointing to
    `python3`, `python3-config`, `pip3` etc., respectively, have been installed into
      /usr/local/opt/python@3.8/libexec/bin
    
    You can install Python packages with
      pip3 install <package>
    They will install into the site-package directory
      /usr/local/lib/python3.8/site-packages
    ```

  * Note that I'll then have to add `/usr/local/opt/python@3.8/libexec/bin` to the PATH if I want to reference using unversioned names. 



## Bash Tricks

* `printf '%s\n' "${my_array[@]}"` to print array elements on separate lines https://stackoverflow.com/questions/15691942/print-array-elements-on-separate-lines-in-bash 

*  `echo $?` to get the exit code integer of the last-run command https://www.cyberciti.biz/faq/bash-get-exit-code-of-command/

  * 0 is no issue, anything else is an error

*  `tr -d '\r'` can remove carriage returns that otherwise result in weird parsing https://stackoverflow.com/questions/800030/remove-carriage-return-in-unix

* `printf "\nhello\n"` should be used instead of `echo -e "\nhello\n"` as `printf` works more reliably with newline interpretation https://stackoverflow.com/questions/11193466/echo-without-newline-in-a-shell-script

  * https://stackoverflow.com/questions/8467424/echo-newline-in-bash-prints-literal-n

* `set -euo pipefail` should be one of the first lines in all scripts, as it will halt the script upon encountering an error https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/

  * `set -euxo pipefail` can optionally be used to print out each command and its output inside the shell script, which can be helpful for figuring out if everything is iterating or being stored as expected

* `speedtestservers=(603 5754 17587 18531)` define an array of numbers and then get a single random element from that array with `selectedserver=${speedtestservers[$RANDOM % ${#speedtestservers[@]}]}`

  * `$RANDOM` will return a random number every time, `%` is modulo, and `${#speedtestservers[@]}` will return the number of elements in the array
  * https://www.christianroessler.net/tech/2015/bash-array-random-element.html
  * Or get a specific one with `driveTempC=${driveTempArr[2]}`

* `ping=$(echo "$speedtestresult" | awk '/Latency/{print $2}')` Given a multi-line input, piping it to `awk`, regex matching on a string "Latency" and then pulling the third element out of that line (zero-indexed)

* Another way of declaring an array of strings, even allowing it to be spread across lines!

  * ```
    declare -a EspDestArray=(
        "nodemcu1"
        "nodemcu2"
        "nodemcu3"
        "nodemcu4"
    )
    ```

  * https://linuxhint.com/bash_loop_list_strings/

* `used=$((kmem - freemem))`  or `used=$((used * 100))` or `pcent=$((used / kmem))` shows arithmetic, or addition/subtraction/multiplication/division of numbers and variables can be done within double parentheses

* `if (( $(bc <<< "$currentDataValue < 0.0") )) ; then` is an example of using `bc` to compare floats to integers and possible other stuff. Otherwise, decimal/float values may not be correctly interpreted

* Bash Integer and String arithmetic

  * https://kapeli.com/cheat_sheets/Bash_Test_Operators.docset/Contents/Resources/Documents/index
  * https://tldp.org/LDP/abs/html/comparison-ops.html

* `epochseconds=$(date +%s)` will get the current number of system time seconds since epoch in 1970 

  * https://serverfault.com/questions/151109/how-do-i-get-the-current-unix-time-in-milliseconds-in-bash
  * `date +%s%N` gives nanoseconds, meaning `echo $(($(date +%s%N)/1000000))` could give milliseconds and `echo $(($(date +%s%N)/1000))` could give microseconds

* Variable standards: snake case with all lower case and underscores, no camelCase, no all caps

  * https://stackoverflow.com/questions/673055/correct-bash-and-shell-script-variable-capitalization 

* `sed -n ${i}p <<< $shareNames` when given an integer `$i` can grab a specific line from an input with multiple lines. 

  * https://stackoverflow.com/questions/15777232/how-can-i-echo-print-specific-lines-from-a-bash-variable

* `bulkData=$(snmpwalk -m ALL -c public -v 2c esxi.brad)` can be used to call an IP address and fetch all possible SNMP data.  

  * `-c` specifies the "community" which in this case is `public`
  * `-v 2c` specifies the SNMP version, which in this case is version 2C

* `ssh -t root@esxi.brad "esxcli storage core device smart get --device-name $datastoreDeviceName"` can be used to execute a command as another user on another host, via SSH.

  * https://www.cyberciti.biz/faq/unix-linux-execute-command-using-ssh/
  * `rawResponse=$(ssh -t -o LogLevel=QUIET root@poorbox.brad "hdparm -C /dev/$1 2>&1")` we can add `-o LogLevel=QUIET` to remove the `connection to xx.xxx.xx.xxx closed` outputs https://superuser.com/questions/457316/how-to-remove-connection-to-xx-xxx-xx-xxx-closed-message

* While loop iterating over many lines, and an inner IF conditional for a specific line's contents

  * ```
    while read -r line; do
        # Check if the line contains the string
        if [[ $line == *"Drive Temperature"* ]]
        then
            driveTemp=$line
        fi
    done <<< "$hwinfo"
    ```

  * `hwinfo` is sent into the while loop on the last line using `<<<` and each iteration of the loop calls `read -r` on the input, setting the current line to the variable `line`

  * `if [[ $line == *"Drive Temperature"* ]]` is checking the current line's contents to see if the string "Drive Temperature" shows up anywhere. `*` characters before and after mean any characters can come before or after. 

* `singleSpaced=$(echo $manySpaced | tr -s ' ')` can reformat a string to remove or "squeeze" consecutive instances of a character into only one instance. 

  * `-s ' '` and `--squeeze-repeats ' '` are identical in operation
  * `Drive Temperature         43     81         N/A    N/A` would be squeezed to `'Drive Temperature 43 81 N/A N/A'`
  * https://unix.stackexchange.com/questions/109835/how-do-i-use-cut-to-separate-by-multiple-whitespace
  * `tr --squeeze-repeats '[.]'` note the extra square brackets would be needed to denote a period, since a period is a special regex character otherwise

* `IFS=' ' read -ra driveTempArr <<< "$driveTemp"` can take a single-spaced string as input and convert it to an array, where the delimiter is a space

  * We can then fetch a specific item from that array using zero-indexing `driveTempC=${driveTempArr[2]}`
  * `IFS='.' read -ra kmemarr <<< "$kmemline"` would break apart on a period instead of a space

* `cpu5=$(echo "$bulkData" | cut -c 50-)` the `cut` command can be used to chop off bits of a string

  * In this case, chop off the first 49 bytes of the line, leaving the string of the 50th character to the end (as defined by the `-`)
  * No `-`  in the command would result in grabbing a single character
  * `utilVoltage=$(echo "${linesplitdata[$i-1]}" | cut -d' ' -f3 )` would print a line of an array, split on space, and take the field containing the string we want
  * https://unix.stackexchange.com/questions/191122/how-to-split-the-string-after-and-before-the-space-in-shell-script
  * `cut -d '|' -f2` is an example of cutting on a pipe character and grabbing the second field. Extended, `parsedValue=$(echo "$bulkData" | grep "$1" | cut -d '|' -f2 | tr -d '[:space:]')` will print some data, find a particular line, grab the second field after splitting on pipe, and then delete all instances of space characters
  * https://stackoverflow.com/questions/9018691/how-to-separate-fields-with-pipe-character-delimiter
  * https://stackoverflow.com/questions/369758/how-to-trim-whitespace-from-a-bash-variable

* `readarray -t linesplitdata <<<"$bulkData"` splits the data into an array with one line per element

  * Bash 4 is the first version to support this

* Looping over an array of strings

  * https://stackoverflow.com/questions/8880603/loop-through-an-array-of-strings-in-bash

  * ```
    for (( i=1; i<${arraylength}+1; i++ ));
    do
        echo ${linesplitdata[$i-1]}
    done
    ```

* Case/switch statement based on an input string and "does the input contain any of these case strings"

  * ```
        case ${linesplitdata[$i-1]} in
            *"Battery Capacity..."*)
                batteryCapacity=$(echo "${linesplitdata[$i-1]}" | cut -d' ' -f3 ) ;;
            *"Load..."*)
                loadWatts=$(echo "${linesplitdata[$i-1]}" | cut -d' ' -f2 )
                loadPercent=$(echo "${linesplitdata[$i-1]}" | cut -d' ' -f3 | cut -d'(' -f2) ;;
        esac
    ```

  * https://stackoverflow.com/questions/22712156/bash-if-string-contains-in-case-statement

  * Double semicolons note the end of a particular switch case, and `esac` notes the end of the switch statement

  * NOTE: Ignore the `*"Load..."*)` weird format, it's trying to match based on a parenthesis ending the line, and that is not key to the switch case working. 

* If Conditional

  * ```
    if [[ $utilVoltage != "UNFILLED" || $loadPercent != "UNFILLED" ]]; then
        echo "Success!"
    else
        echo "Failure."
    fi
    ```

  * double pipes act as OR conditionals here, meaning if any one of these matches the string `UNFILLED` then it will evaluate false/failure

  * The double square brackets indicate the bounds of what should be evaluated as a conditional, and the semicolon ends that section. 

* `webdata=$(curl --silent "${EspIpArray[$i-1]}" --max-time 5 || true)` to get the contents of a webpage into a variable, in this case it is two lines of CSV data

  * https://stackoverflow.com/questions/3742983/how-to-get-the-contents-of-a-webpage-in-a-shell-variable
  * `--silent` to hide the download prgress from the output
  * `--max-time` to time out the operation if the link is down
  * `|| true` because pipefail -e recognizes curl no response as a failure and will end the script here otherwise https://stackoverflow.com/questions/22009364/is-there-a-try-catch-command-in-bash 

* Confirm an array is a certain length. If it is not, print an error message and `continue` to skip the current loop

  * ```
    if [ ! "${#linesplitwebdata[@]}" -eq "2" ]; then
            # https://stackoverflow.com/questions/8467424/echo-newline-in-bash-prints-literal-n
            # use `echo -e` to interpret newlines rather than just printing \n
            echo -e "Expected 2 lines of HTTP output, got:" ${#linesplitwebdata[@]} "\n"
            continue
        fi
    ```

  * https://stackoverflow.com/questions/13101621/checking-if-length-of-array-is-equal-to-a-variable-in-bash

  * https://stackoverflow.com/questions/9146136/check-if-file-exists-and-continue-else-exit-in-bash

* `readarray -d , -t headercsvsplit <<<"${linesplitwebdata[0]}"` to specify comma as a delimiter, and then to remove the trailing delimiter, all from a particular array element and into a new array

  * `-d` specifies comma delimiter, `-t` removes trailing delimiter
  * `-d` introduced in bash 4.4

* `headercsvsplit[$j-1]="$( echo "${headercsvsplit[$j-1]}" | xargs echo -n)"` to give an example of `xargs echo -n` trimming whitespace from a bash variable 

  * https://stackoverflow.com/questions/369758/how-to-trim-whitespace-from-a-bash-variable

* Create a function and return a string value from it. given bulkData + metricName + passback value, retrieves that metric's current value

  * ```
    getMetricValueFromBulkData () {
    
        parsedValue=$(echo "$bulkData" | grep "$1" | cut -d '|' -f2 | tr -d '[:space:]')
    
        # set passback value to the parsed value
        eval "$2=$parsedValue"
    }
    ```

  * https://stackoverflow.com/questions/3236871/how-to-return-a-string-value-from-a-bash-function

  * Arguments: `$1` is bulkData, `$2` is metricName, `$3` is passback value

  * A sample call would then be:

  * ```
    systemTempC="UNFILLED"
    getMetricValueFromBulkData "System Temp" systemTempC
    echo "$systemTempC"
    ```

  * note that the second argument is a reference rather than the value, which is necessary to update the passed-in variable

* `cpuTempC=systemTempC=peripheralTempC="UNFILLED"` to initialize multiple variables at the same time and set them all to the same value, instead of one per line

  * https://www.unix.com/unix-for-dummies-questions-and-answers/123480-initializing-multiple-variables-one-statement.html

* `tr -d '[:space:]'` will delete all instances of space characters from a given input

  * https://superuser.com/questions/537509/nice-commands-in-a-sh-script-for-cron-jobs

* `if [[ $rawResponse == *"No such file or directory"* ]]; then` as an example of checking if a substring exists

  * https://stackoverflow.com/questions/229551/how-to-check-if-a-string-contains-a-substring-in-bash

* `if [ "$2" -gt -1 ]; then` checks that an argument is greater than the integer -1, which we're using in this case to confirm it's not in an error state. 

  * Note that the integer should not be wrapped in quotes
  * `if (( $(bc <<< "$2 > -1") )) ; then` does the exact same thing
  * https://www.tldp.org/LDP/abs/html/comparison-ops.html

* `if [ -z "$diskTemp" ]; then` will check if a variable is currently empty

  * https://www.cyberciti.biz/faq/unix-linux-bash-script-check-if-variable-is-empty/



## Cron

* We want to collect data on a regular basis, so using Cron and Crontab to periodically run the scripts is the best way of going about it. 
* `crontab -e` will open Cron for editing in Vim. 
  * As usual with Vim, `ESC` will be used to enter commands, `i` will be used to start inserting data, and then using `wq!` will write the changes and quit, forcefully. Cron will then be updated. 
* `crontab -l` will show all the currently configured cron jobs
* Scheduling
  * `0,20,40 * * * *` will run a script every 20 minutes
  * `*/2 * * * *` will run a script every 2 minutes
  * `* * * * *` will run a script every minute
* I found that my speedtest script oftentimes reported slower speeds when running via cron than when I ran it manually. I found https://askubuntu.com/questions/744249/cronjob-under-ubuntu-runs-slow which suggested that Cron was running at a lower priority than my shell. Adding `nice -n 19` to add 19 to the current nice level should in theory mitigate this
  * https://stackoverflow.com/questions/14371576/nice-command-in-sh-script-for-cron-jobs
  * http://www.linuxclues.com/articles/15.htm



## Cyberpower CP1350PFCLCD Read Data

I found https://www.cyberpowersystems.com/product/software/power-panel-personal/powerpanel-for-linux/ which allows a utility like `pwrstat -status` to print out the following:

	Properties:
		Model Name................... CP1350PFCLCD
		Firmware Number.............. CRCA102-3I1
		Rating Voltage............... 120 V
		Rating Power................. 810 Watt
	
	Current UPS status:
		State........................ Normal
		Power Supply by.............. Utility Power
		Utility Voltage.............. 123 V
		Output Voltage............... 123 V
		Battery Capacity............. 100 %
		Remaining Runtime............ 34 min.
		Load......................... 162 Watt(20 %)
		Line Interaction............. None
		Test Result.................. Unknown
		Last Power Event............. None

* Install `wget` first on CentOS with `sudo yum install wget -y` and then copy link from the above page for 32 or 64 bit depending on your CentOS version. It may look similar to `wget https://dl4jz3rbrsfum.cloudfront.net/software/powerpanel-132-0x86_64.rpm`
* Then install the utility with `yum install powerpanel-132-0x86_64.rpm  -y`
* The utility `pwrstat` should then be installed.  I confirmed I have 1.3.2 installed currently by running `pwrstat -version`



## IPMI ESXi sensor readings

* Installed IPMITool with `yum install ipmitool` on CentOS
* I found that setting up an Administrator user in the IPMI Supermicro web UI and running `ipmitool -H x9srw.brad -U ipminetworkuser -P ipminetworkpass sensor` yielded pipe-character separated columns for each sensor installed. 
* `bulkData=$(ipmitool -H x9srw.brad -U ipminetworkuser -P ipminetworkpass sensor)` as an example of calling an IPMI tool over the network for read only access
  * `-H` defines the IP address to connect
  * `-U` for the user, `-P` for password
  * `sensor` is one of many options for return data
  * Output data will be pipe-delimited, also containing whitespace
  * `/usr/bin/ipmitool` on CentOS, `/usr/local/bin/ipmitool` on macOS



##ESXi Memory reading

* I have four 16GB modules installed in my ESXi host.
* `esxcli hardware memory get` shows ` Physical Memory: 68683657216 Bytes` 
* The above command confirms my physical memory is 68683657216 bytes or 63.97 gibibytes or 68.68 gigabytes or 67073884 kibibytes.
* Running `esxcfg-info --hardware` (plus `grep -e "\-Free\." -e "Kernel Memory"` on another computer) gives the following memory-specific lines
* `|----Kernel Memory.........................................67073884 kilobytes`
* `|----Free..................................................14773600 kilobytes`
* When interpreted as the labeled kilobytes, we see: Kernel Memory: 62.47 gibibytes, 67.07 gigabytes, 63966 mebibytes
* When interpreted as kibibytes though, we see: Kernel Memory: 63.97 gibibytes, 68.68 gigabytes, 65501 mebibytes. 
  * Wait! This matches the physical memory exactly
* https://www.mirazon.com/storage-ram-size-doesnt-add/ confirms that RAM's marketing GB is actually Gibibyte rather than Gigabyte. Meanwhile, HDDs sold in TB  are usually referencing Terabytes rather than Tebibytes.
  * 8GB RAM = 8192 mebibytes = 8 gibibytes = 8.6 gigabytes
  * 8TB Hard Drive = 8000 gigabytes = 8 terabytes  = 7.28 tebibytes
* Reddit confirmed my suspicion that ESXi is reporting kibibytes in actuality but labeling them as kilobytes. 

## Unraid HDD and system readings

* Requires passwordless SSH to be set up, so logging in doesn't need to be interactive

  * https://forums.unraid.net/topic/51160-passwordless-ssh-login/ has notes on passwordless SSH setup for Unraid specifically. Unraid is special because it creates an OS in RAM off files on a USB drive, so persistent setup can be difficult

  * SSH key exists on my script-executing host at `/root/.ssh/id_rsa.pub` 

    * https://linuxize.com/post/how-to-setup-passwordless-ssh-login/
    * https://www.tecmint.com/ssh-passwordless-login-using-ssh-keygen-in-5-easy-steps/
    * run `ssh-keygen -t rsa` to generate that file

  * Technically, the preinstalled command `ssh-copy-id root@poorbox.brad` will work

  * In the background, it is doing `cat ~/.ssh/id_rsa.pub | ssh remote_username@server_ip_address "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"` all in one to create the ssh directory and authorized_keys file and then add your key to it and chmod everything to have the right permissions.

  * ```
    [root@grafana ~]# ssh-copy-id root@poorbox.brad
    /usr/bin/ssh-copy-id: INFO: Source of key(s) to be installed: "/root/.ssh/id_rsa.pub"
    /usr/bin/ssh-copy-id: INFO: attempting to log in with the new key(s), to filter out any that are already installed
    /usr/bin/ssh-copy-id: INFO: 1 key(s) remain to be installed -- if you are prompted now it is to install the new keys
    root@poorbox.brad's password: 
    
    Number of key(s) added: 1
    
    Now try logging into the machine, with:   "ssh 'root@poorbox.brad'"
    and check to make sure that only the key(s) you wanted were added.
    ```

  * We can validate that on the Unraid side, in the `/root/.ssh/authorized_keys` file we see `ssh-rsa <abbreviated-public-key> root@centOS-VM` and if we change the DNS name or IP of the originating SSH connection, this may not work. I experimented by changing it to another valid name + a different IP and those both seemed to work, so maybe we're lucky or maybe it just needs to be restarted.

  * unRAID is special though in that it stores all persistent data in `/boot` and recreates the `/root` directory on each boot, meaning we'll have to recreate the `authorized_keys` file each time we boot unRAID.

    * The thread https://forums.unraid.net/topic/51160-passwordless-ssh-login/ has a bunch of different suggestions, and the more typical suggestion is to make a custom script that does the above copying and chmodding and then add that script to the `/boot/config/go` file to be executed at startup.
    * The thread also mentions that the `ssh` plugin is preinstalled and has some default behavior, so I want to try that.
    * Another place that's mentioned is https://www.reddit.com/r/unRAID/comments/dlo9r6/help_with_persistent_ssh_on_unraid/f4u4s5q/ saying "For this reason I use the SSH plugin from `docgyver` which can be found in a Community Applications search. After you install that, place your public key in this location: `/boot/config/plugins/ssh/<user>/.ssh/authorized_keys`"
    * that thread yielded `install -d -m700 /root/.ssh install -m600 /boot/config-user/ssh/authorized_keys /root/.ssh/` which I can then modify and add to my own go file, I believe.
    * `cp /root/.ssh/authorized_keys /boot/config/ssh/authorized_keys`  to get the temporary file to a permanent home on the /boot USB memory
    * I found out `install` is meant for multiple files and therefore doesn't do renaming. Anyway, then add the following to `/boot/config/go` in two separate lines:`install -d -m700 /root/.ssh` and then `install -m600 /boot/config/ssh/authorized_keys /root/.ssh/`
    * After that, running SSH from my script-running host works fine

* Found an issue. Trying to call `rawResponse=$(ssh -t root@poorbox.brad "hdparm -C /dev/sdg")` in the code would exit the script before continuing. This is due to `set -e` being used and `ssh -t root@poorbox.brad "hdparm -C /dev/sdg"` returning exit status 2 rather than 0 as it should. Exit status 2 means misuse of a command, probably because it's an empty response. I was able to find this out because `echo $?` returns the last exit code

  * https://www.cyberciti.biz/faq/bash-get-exit-code-of-command/
  * https://unix.stackexchange.com/questions/279777/how-to-catch-and-handle-nonzero-exit-status-within-a-bash-function
  * I actually ended up finding that `rawResponse=$(ssh -t root@poorbox.brad "hdparm -C /dev/sdg") && echo "executing" || echo "executing"` returns exit code 0 so maybe this will work.  https://stackoverflow.com/questions/22009364/is-there-a-try-catch-command-in-bash
  * https://stackoverflow.com/questions/22009364/is-there-a-try-catch-command-in-bash proposed another method of using `set +e` to turn off error handling before and then `set -e` turning it back on after. I didn't end up doing this though. 

* I had another issue where parsing the SMART status with `diskTemp=$(echo "$rawResponse" | grep "Temperature" | tr --squeeze-repeats '[:space:]' | cut -d ' ' -f10 | tr -d '\n')` and then trying to print it `echo "x $diskTemp y"` would leave weird output ` y35`

  * https://www.unix.com/shell-programming-and-scripting/146992-how-see-hidden-characters.html shows how to print normally invisible characters so I could see what was happening, turns out there's the ^M character when I run `echo "x $diskTemp y" | cat -v` I get `x 35^M y`
  * https://unix.stackexchange.com/questions/134695/what-is-the-m-character-called it's a carriage return so adding a final `tr -d '\r'` got it removed https://stackoverflow.com/questions/800030/remove-carriage-return-in-unix

* Another bug: I found that the `SG_IO: bad/missing sense data, sb[]: 70 ` line of the output when running `rawResponse=$(ssh -t -o LogLevel=QUIET root@poorbox.brad "hdparm -C /dev/sda")` doesn't show up when running via my Cron, even though both are executing on a remote host and should in theory be hitting the same hdparm. 

  * Running `ssh -t -o LogLevel=QUIET root@poorbox.brad "which hdparm"` in the cli gives me `/usr/sbin/hdparm` but Cron gives me the same thing. I thought it might have to do with STDERR and STDOUT being different but `ssh -t -o LogLevel=QUIET root@poorbox.brad "hdparm -C /dev/sda" > out 2> err` both prints to STDOUT. This might just mean I need to do error handling better in diskTemp and catch missing responses, since sda and sdb now show up as idle.
  * I found the fix. We need to include console redirection in the remote command, so `2>&1` needs to be added so the remote SSH command is `ssh -t -o LogLevel=QUIET root@poorbox.brad "hdparm -C /dev/$1 2>&1"` and then remote call works the same way as our shell https://unix.stackexchange.com/questions/66170/how-to-ssh-on-multiple-ipaddress-and-get-the-output-and-error-on-the-local-nix

* I had the old script running as PHP on unRAID itself that used to do what this script did. It's no longer being used, so these notes are just for if I need to run a Cron job on Unraid locally again. 

  * As https://forums.unraid.net/topic/42475-crontab-added-through-go-script-not-working/ notes, any `.cron` file under the directory `/boot/config/plugins/dynamix` will get loaded into the crontab. 
  * I had a `diskstats.cron` file there with `\* * * * * /usr/bin/php /boot/myScripts/hdStats.php &> /dev/null`. I've moved it out of the directory and run `update_cron` to reload the crontab without a reboot, and then ran `cat /etc/cron.d/root` to check what the current cron setup was (note that `crontab -l` isn't what you want here)


## Authentication

- InfluxDB 2.x is moving to token-based authentication that needs to be passed with each write API call.
- Influx 1.x has HTTP Basic Auth as authentication, as documented in https://docs.influxdata.com/influxdb/v1.8/administration/authentication_and_authorization/
- I created a user with write access to the database that I write values to, and need to pass that username and password to `curl` when calling InfluxDB. I can do that by adding the curl flag `-u "$USER:$PASS"` and that will authenticate for me
- To load the variables from outside the script, I can use `source` to load a file's lines as variables https://linuxize.com/post/bash-source-command which should be portable between running manually and running in Cron.



## InfluxDB CLI

* Enter into the Influx prompt with `influx` or `influx -precision rfc3339`
  * By default, timestamps print out in nanoseconds which  is unreadable. Initialize Influx with `influx -precision rfc3339` to get full date printouts
  * Exit with `exit` or `CTRL + D` 
  * More info at https://docs.influxdata.com/influxdb/v1.8/tools/shell/
* Databases are where each set of data is stored. 
  * `show databases` will list all the options
  * `use local_reporting` will  select the DB named `local_reporting`
* Series exist within databases, and broadly categorize data
  * `show series` will show all the series+tag combinations inside the chosen database
* Tags are optional parts of data points separate from the data fields themselves and intended to be used for common queries, rather than constantly changing data
  * They are key-value pairs
  * A sensor name, measurement category, or serial number could be a relatively fixed variable stored as a tag. For example, the key might be `hostname` while the value is `nodemcu3`
  * "In general, fields should not contain commonly-queried metadata." This is according to https://docs.influxdata.com/influxdb/v1.8/concepts/key_concepts/ so this means tags are a better place. 
  * When querying by tag, single quotes must be used. `select * from ups_data where ups = 'cyberpower' and time > now() - 5m  LIMIT 10` will  show data due to the single quotes but `select * from ups_data where ups = "cyberpower" and time > now() - 5m  LIMIT 10` will not, because the tag key `ups`
  * View what tags are in a series by running `show tag keys from "speedtest"`
* Fields are the "columns" in the "table" where actual measurement data is stored, such as temperature, CPU, free space, or something else. 
  * They can be listed along with their data types (float, string, etc) for a particular series by running `show field keys from "speedtest"`
* Delete Data
  * https://docs.influxdata.com/influxdb/v1.7/query_language/database_management/ has information
  * If I added in the wrong timestamp and want to delete data in a series before a certain date, I could say `DELETE FROM "speedtest" WHERE time < '1977-01-01'` or `DELETE FROM "speedtest" WHERE time > now()-30m`
* Copy or back up a series
  * `SELECT "metric","value" INTO speedtestnew FROM speedtest`
  * It could be used to remove a particular field
  * `SELECT "metric","value" INTO speedtestnew FROM speedtest GROUP BY *` is a better query. https://docs.influxdata.com/influxdb/v1.8/query_language/explore-data/#group-by-tags and https://www.influxdata.com/blog/tldr-influxdb-tech-tips-january-05-2016/ recommend "that you always include `GROUP BY *` in your `INTO` queries as that clause preserves all tags in the original data as tags in the destination data." Otherwise, the tags will be converted to fields and some query possibilities and optimizations may be lost. 
* Querying
  * Adding `ORDER BY time DESC` will give us the most recent results first
  * Adding `LIMIT 10` will limit to 10 results
  * `select * FROM "diskstats" ORDER BY time DESC LIMIT 10` combines both of these

