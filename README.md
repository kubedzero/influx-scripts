* https://itnext.io/upgrading-bash-on-macos-7138bd1066ba explains why Bash 3.2 is still on macOS and how to get Bash 4 with Homebrew
* https://www.shellcheck.net/ can offer suggestions to do shell scripting better
* https://github.com/lovesegfault/beautysh installed via pip is helpful to format shell script files from the command line. Use with `beautysh file1.sh` to run
* Installed Bash 5 on macOS which had readarray -d but Bash 4.2 on CentOS did not have it. Updating to bash 5 with https://www.ramoonus.nl/2019/01/08/bash-5-0-installation-for-linux/ and then changing line1 to point to the compiled version
* https://apple.stackexchange.com/questions/55989/change-my-shell-to-a-different-bash-version-at-usr-local-bin-bash change the default shell per username by editing `/etc/shells` and then running `chsh -s /usr/local/bin/bash username` to set the version you want for your username.
```
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


### Speedtest
`speedtest-cli --list` from https://github.com/sivel/speedtest-cli/releases yields the following top results for a San Francisco IP
```
Retrieving speedtest.net configuration...
 5026) AT&T (San Francisco, CA, United States) [1.20 km]
  603) Unwired (San Francisco, CA, United States) [1.20 km]
 5754) Fastmetrics Inc. (San Francisco, CA, United States) [1.20 km]
 1783) Comcast (San Francisco, CA, United States) [1.20 km]
17587) Wiline Networks (San Francisco, CA, United States) [1.20 km]
18531) Wave (San Francisco, CA, United States) [1.20 km]
 8228) Race Communications (San Francisco, CA, United States) [1.20 km]
```

The ID can then be used to identify which server to test against
`speedtest-cli --server 5026` over the following servers yielded these rough results:

*  5026) AT&T - 400 down 600 up 10ms ping
*   603) Unwired - 824 down 900 up 10ms ping
*  5754) Fastmetrics Inc. - 842 down 834 up 4ms ping
*  1783) Comcast - 663 down 730 up 6ms ping
* 17587) Wiline Networks - 760 down 900 up 7ms
* 18531) Wave - 818 down 741 up 4ms
*  8228) Race Communications - 470 down 430 up 17ms ping


With this list we can then make an exclusion based or an inclusion based list to test against:

* (recommended) `speedtest-cli --server 603 --server 5754 --server 17587 --server 18531`
* `speedtest-cli --exclude 5026 --exclude 1783 --exclude 8228`

`speedtest-cli --simple` removes the "testing from IP address" and selected server information, yielding just the following:

```
Ping: 5.658 ms
Download: 792.40 Mbit/s
Upload: 679.89 Mbit/s
```

It can also output in CSV format, which is friendlier to parse with `readarray`
`speedtest-cli --csv` yields `5754,Fastmetrics Inc.,"San Francisco, CA",2019-09-30T02:03:33.370153Z,1.2028609595919466,5.422,294294532.37465966,211767289.37021893,,136.24.206.17` and we know the schema from running `speedtest-cli --csv-header` which yields `Server ID,Sponsor,Server Name,Timestamp,Distance,Ping,Download,Upload,Share,IP Address`

* Print array https://stackoverflow.com/questions/15691942/print-array-elements-on-separate-lines-in-bash with `printf '%s\n' "${my_array[@]}"`



* The simplest method is to just use the `--simple` printout and then using `awk` to fetch the value from each line that we want. 



### Cyberpower CP1350PFCLCD Read Data

The CentOS VMs for PowerPanel Business edition Local/Agent sometimes presenst connection refused messages, or doesn't start up. All I really want to do is scrape the data and I found https://www.cyberpowersystems.com/product/software/power-panel-personal/powerpanel-for-linux/ which allows a utility like `pwrstat -status` to print out the following:



```
The UPS information shows as following:

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

```



There! That gives me voltage, capacity, load, everything I want. It's easy to install on CentOS too.



* Get `wget` with `sudo yum install wget -y` and then copy link from the above page for 32 or 64 bit depending on your CentOS version. It may look similar to `wget https://dl4jz3rbrsfum.cloudfront.net/software/powerpanel-132-0x86_64.rpm`
* Then install the utility with `yum install powerpanel-132-0x86_64.rpm  -y`
* The utility `pwrstat` should then be installed.  



Interestingly when running `influx` to check on the data I found the following:



```
> select * from ups_data where ups = "cyberpower" and time > now() - 5m  LIMIT 10
> select * from ups_data where ups = 'cyberpower' and time > now() - 5m  LIMIT 10
name: ups_data
time                batteryCapacity denhost1.value host loadPercent loadWatts outputVoltage remainingRuntime sensor ups        utilVoltage
----                --------------- -------------- ---- ----------- --------- ------------- ---------------- ------ ---        -----------
1571465909800900133 100                                 20          162       123           34                      cyberpower 123
> exit

```

Wrapping the search string in double quotes didn't allow data to be found, but single quotes was fine. 



## IPMI ESXi sensor readings

* Installed IPMITool with `yum install ipmitool` on CentOS
* I found setting up an Administrator user in the IPMI Supermicro web UI and running `ipmitool -H x9srw.brad -U ipminetworkuser -P ipminetworkpass sensor` yielded pipe-character separated columns for each sensor installed. 
* https://linuxize.com/post/bash-functions/ shows how to define a function, no input variables need to be explicitly defined and instead are just accessible with `$1` indexed values
* SCP'd it over to the server and ran `crontab -e` and then added the line `\* * * * * /root/supermicro_ipmi_influx.sh` to get it running every minute



## UnRAID Hard drive and System readings

* I want to get HDD active/standby state, temperature, CPU usage, RAM usage, and array free space

* I want to run the script on CentOS rather than having it run from UnRAID and post data from there. 

* https://forums.unraid.net/topic/51160-passwordless-ssh-login/ has notes on passwordless SSH setup for unRAID specifically

  * SSH key exists on my script-executing host at `/root/.ssh/id_rsa.pub` (if not follow https://linuxize.com/post/how-to-setup-passwordless-ssh-login/ or https://www.tecmint.com/ssh-passwordless-login-using-ssh-keygen-in-5-easy-steps/ and run `ssh-keygen -t rsa` to generate that file)

  * Technically the preinstalled command `ssh-copy-id root@poorbox.brad` will work. In the background, it is doing `cat ~/.ssh/id_rsa.pub | ssh remote_username@server_ip_address "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"` all in one to create the ssh directory and authorized_keys file and then add your key to it and chmod everything to have the right permissions.

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

  * We note that on the unRAID side in the `/root/.ssh/authorized_keys` file we see `ssh-rsa <abbreviated-public-key> root@centOS-VM` and if we change the DNS name or IP of the originating SSH connection, this may not work. I experimented by changing it to another valid name + a different IP and those both seemed to work, so maybe we're lucky or maybe it just needs to be restarted.

  * unRAID is special though in that it stores all persistent data in `/boot` and recreates the `/root` directory on each boot, meaning we'll have to recreate the `authorized_keys` file each time we boot unRAID. The thread https://forums.unraid.net/topic/51160-passwordless-ssh-login/ has a bunch of different suggestions, and the more typical suggestion is to make a custom script that does the above copying and chmodding and then add that script to the `/boot/config/go` file to be executed at startup. The thread also mentions that the `ssh` plugin is preinstalled and has some default behavior, so I want to try that. Another place that's mentioned is https://www.reddit.com/r/unRAID/comments/dlo9r6/help_with_persistent_ssh_on_unraid/f4u4s5q/ saying "For this reason I use the SSH plugin from docgyver which can be found in a Community Applications search. After you install that place your public key in this location /boot/config/plugins/ssh/<user>/.ssh/authorized_keys ."

  * Turns out an extra plugin is needed for that automatic setup. However, that thread yielded `install -d -m700 /root/.ssh install -m600 /boot/config-user/ssh/authorized_keys /root/.ssh/` which I can then modify and add to my own go file, I believe. `cp /root/.ssh/authorized_keys /boot/config/ssh/authorized_keys`  (found out `install` is meant for multiple files and therefore doesn't do renaming) and then add the following to `/boot/config/go` in two separate lines:`install -d -m700 /root/.ssh` and then `install -m600 /boot/config/ssh/authorized_keys /root/.ssh/`

  * After that, running SSH from my script-running host works fine

  * Found an issue. Trying to call `rawResponse=$(ssh -t root@poorbox.brad "hdparm -C /dev/sdg")` in the code would exit the script before continuing. This is due to `set -e` being used and `ssh -t root@poorbox.brad "hdparm -C /dev/sdg"` returning exit status 2 rather than 0 as it should. Exit status 2 means misuse of a command, probably because it's an empty response. I was able to find this out because `echo $?` returns the last exit code

    * https://www.cyberciti.biz/faq/bash-get-exit-code-of-command/
    * https://unix.stackexchange.com/questions/279777/how-to-catch-and-handle-nonzero-exit-status-within-a-bash-function
    * I actually ended up finding that `rawResponse=$(ssh -t root@poorbox.brad "hdparm -C /dev/sdg") && echo "executing" || echo "executing"` returns exit code 0 so maybe this will work.  https://stackoverflow.com/questions/22009364/is-there-a-try-catch-command-in-bash
    * https://stackoverflow.com/questions/22009364/is-there-a-try-catch-command-in-bash proposed another method of using `set +e` to turn off error handling before and then `set -e` turning it back on after.

  * I had another issue where parsing the SMART status with `diskTemp=$(echo "$rawResponse" | grep "Temperature" | tr --squeeze-repeats '[:space:]' | cut -d ' ' -f10 | tr -d '\n')` and then trying to print it `echo "x $diskTemp y"` would leave weird output ` y35`

    * https://www.unix.com/shell-programming-and-scripting/146992-how-see-hidden-characters.html shows how to print normally invisible characters so I could see what was happening, turns out there's the ^M character when I run `echo "x $diskTemp y" | cat -v` I get `x 35^M y`
    * https://unix.stackexchange.com/questions/134695/what-is-the-m-character-called it's a carriage return so adding a final `tr -d '\r'` got it removed https://stackoverflow.com/questions/800030/remove-carriage-return-in-unix

  * https://stackoverflow.com/questions/11193466/echo-without-newline-in-a-shell-script printf should be used when wanting to avoid newlines, echo behavior is more unreliable

  * I had the old script running as PHP on unRAID itself, and as https://forums.unraid.net/topic/42475-crontab-added-through-go-script-not-working/ notes any `.cron` file under the directory `/boot/config/plugins/dynamix` will get loaded into the crontab. I had a `diskstats.cron` file there with `\* * * * * /usr/bin/php /boot/myScripts/hdStats.php &> /dev/null`. I've moved it out of the directory and run `update_cron` to reload the crontab without a reboot, and then ran `cat /etc/cron.d/root` to check what the current cron setup was (note that `crontab -l` isn't what you want here)

  * WEIRD. I found that the `SG_IO: bad/missing sense data, sb[]: 70 ` line of the output when running `rawResponse=$(ssh -t -o LogLevel=QUIET root@poorbox.brad "hdparm -C /dev/sda")` doesn't show up when running via Cron, even though both are executing on a remote host and should in theory be hitting the same hdparm. Running `ssh -t -o LogLevel=QUIET root@poorbox.brad "which hdparm"` in the cli gives me `/usr/sbin/hdparm` but Cron gives me the same thing. I thought it might have to do with STDERR and STDOUT being different but `ssh -t -o LogLevel=QUIET root@poorbox.brad "hdparm -C /dev/sda" > out 2> err` both prints to STDOUT. This might just mean I need to do error handling better in diskTemp and catch missing responses, since sda and sdb now show up as idle.

  * I found the fix. We need to include console redirection in the remote command, so `2>&1` needs to be added so the remote SSH command is `ssh -t -o LogLevel=QUIET root@poorbox.brad "hdparm -C /dev/$1 2>&1"` and then Cron works the same way as our shell https://unix.stackexchange.com/questions/66170/how-to-ssh-on-multiple-ipaddress-and-get-the-output-and-error-on-the-local-nix