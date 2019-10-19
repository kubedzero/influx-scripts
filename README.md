* https://itnext.io/upgrading-bash-on-macos-7138bd1066ba explains why Bash 3.2 is still on macOS and how to get Bash 4 with Homebrew
* https://www.shellcheck.net/ can offer suggestions to do shell scripting better
* https://github.com/lovesegfault/beautysh installed via pip is helpful to format shell script files from the command line
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