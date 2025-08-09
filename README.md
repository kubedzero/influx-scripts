# README

This repository tracks the Python scripts used to collect information about assorted network-connected devices. The Python dependencies are managed with `uv`, with one shell command `speedtest` required as well 



# Cron

* Data collection on a regular basis is desired, so using Cron and Crontab to periodically run the scripts is the best way of going about it
* `crontab -e` will open Cron for editing in Vim
  * As usual with Vim, `ESC` will be used to enter commands, `i` will be used to start inserting data, and then using `wq!` will write the changes and quit, forcefully. Cron will then be updated 
* `crontab -l` will show all the currently configured cron jobs
* Scheduling
  * `0,20,40 * * * *` will run a script every 20 minutes
  * `*/2 * * * *` will run a script every 2 minutes
  * `* * * * *` will run a script every minute
* I found that my speedtest script oftentimes reported slower speeds when running via cron than when I ran it manually. I found https://askubuntu.com/questions/744249/cronjob-under-ubuntu-runs-slow which suggested that Cron was running at a lower priority than my shell. Adding `nice -n 19` to add 19 to the current nice level should in theory mitigate this
  * https://stackoverflow.com/questions/14371576/nice-command-in-sh-script-for-cron-jobs
  * http://www.linuxclues.com/articles/15.htm



# APC Smart-UPS 750 Read Data

- http://www.apcupsd.org/manual/manual.html#modbus-driver When trying to adapt `apcupsd` to the new SMT750 though, it had only the most basic information outputting in USB mode. I had to update the configuration to `UPSTYPE modbus` and then I was able to get far more detailed output, pretty much the same as with the DLA1500. The only problem I found is that the data would stop updating after a few minutes, as if the modbus code didn't work fully. I would see the STARTTIME value in the output stop updating, and just spit out the same values over and over. `apcupsd` was still working since killing it would give "connection refused" messages, but it seems as if the modbus code is more half-baked. Sad.
- NUT (Network UPS Tools) splits its architecture into a Driver layer and a Server layer. Sadly for the Driver layer, it just ends up using `apcupsd` so even if I switched over to NUT for outputting data, it wouldn't help here. 
- My other option, now that I have the NMC, is to remove the UPS cable entirely and do monitoring over the network. This was always the objective, to keep cabling more simple
- https://www.apc.com/us/en/faqs/FA156048/ notes that "the APC PowerNet MIB file is required. The APC PowerNet reference guide for all supported products can be downloaded from the main APC website, by searching for "Powernet", or looking for SKU "SFPMIB""
  - I did this, and found 4.4.1 is the latest https://www.apc.com/us/en/product/SFPMIB441/powernet-mib-v4-4-1/. 
  - On that 4.4.1 page there is a link to download https://download.schneider-electric.com/files?p_enDocType=Firmware&p_File_Name=powernet441.mib&p_Doc_Ref=APC_POWERNETMIB_441_EN
  - I used this with Ireasoning MIB Browser on macOS https://www.ireasoning.com/mibbrowser.shtml  to find the values I wanted. I enabled SNMP v1 on the NMC while doing this testing, and disabled it in favor of SNMPv3 afterwards
- On macOS, `snmpget -v 1 -c public -O qUv apc.brad .1.3.6.1.4.1.318.1.1.1.3.3.1.0` outputs `1209`. Explaining the inputs: -v 1 sets to SNMP version 1, -c public sets the Community to Public, -O qUv sets output options of "quick print for easier parsing," "don't print units," and "print values only (not OID = value)." That allows us to get just the raw value as output, nice
      - Now let's try with SNMPV3, which doesn't use community and instead needs a SecurityName input
          - `snmpget -v 3 -u centos -O qUv apc.brad .1.3.6.1.4.1.318.1.1.1.3.3.1.0` does the trick! That also outputs 1209, perfect
          - Another fun trick is that multiple OIDs can be passed in with a single call. So `snmpget -v 3 -u centos -O qUv apc.brad .1.3.6.1.4.1.318.1.1.1.3.3.1.0 .1.3.6.1.4.1.318.1.1.1.2.3.2.0` outputs two lines, one with each OID output. With that, a single call could be made, and then parsed into separate variables. Theoretically that could keep execution effort down, but would make the script more complicated
          - I can use https://stackoverflow.com/questions/12722095/how-do-i-use-floating-point-arithmetic-in-bash to divide by 10 and round to a certain number of decimal places to adjust the high-precision Integer values into Float/Decimal Strings to pass into InfluxDB


# Authentication

- InfluxDB 2.x is moving to token-based authentication that needs to be passed with each write API call. In Python it's easy, just passing in the token that was created and the organization `InfluxDBClient(url=INFLUX_URL, token=INFLUX_TOKEN, org=INFLUX_ORG)` and then passing the particular bucket when writing the data `write_api.write(write_precision=WritePrecision.S, bucket=INFLUX_BUCKET, record=line_protocol_string_list)`
- Influx 1.x has HTTP Basic Auth as authentication, as documented in https://docs.influxdata.com/influxdb/v1.8/administration/authentication_and_authorization/
- I created a user with write access to the database that I write values to, and need to pass that username and password to `curl` when calling InfluxDB. I can do that by adding the curl flag `-u "$USER:$PASS"` and that will authenticate for me



# InfluxDB CLI

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



# SNMP

- I spent a good amount of time looking around for which SNMP library to use in Python. I ended up using https://www.pysnmp.com/ https://pypi.org/project/pysnmp-lextudio/ because it seems to be the forked successor of the most popular package after the author passed away, and a few other projects seem to have centered on using this particular fork (there are others). The documentation is also very good https://docs.lextudio.com/pysnmp/quick-start. https://github.com/etingof/pysnmp/issues/429 explains what happened, but `pysnmp-lextudio` was deprecated for v6 and v7 was carried on in `pysnmp` 
- I was looking for a native Python implementation, not one that relied on `net-snmp` or another system library that may make the script less portable across operating systems
- I found that `snmpwalk -v 2c -c public ipaddress HOST-RESOURCES-MIB::hrProcessorLoad`  was able to resolve values, but I'd get errors in Python such as `MIB file "NET-SNMP-EXTEND-MIB.py[co]" not found in search path (DirMibSource`.  It seems that `/usr/share/snmp/mibs` contained a bunch of extra MIB files that the CLI utility `snmpwalk` could reference, while Python didn't have those. I found https://github.com/etingof/pysnmp-mibs/tree/master/pysnmp_mibs which may have precompiled MIBs available, but the format might be out of date since they're years old. Instead, I just put the raw OIDs into Python and that worked fine `ObjectType(ObjectIdentity(.1.3.6.1.2.1.25.3.3.1.2.))`



# Speedtest

- I found that in 2025, there are no actively maintained widely adopted native Python libraries for doing internet speed tests. Ookla Speedtest, Fast.com, Akami Speedtest, Cloudflare Speedtest, nothing I could find
  - https://github.com/sivel/speedtest-cli thousands of stars but last updated in 2021
  - https://github.com/zpeters/speedtest deprecated 2020
  - https://pypi.org/project/akamai-speedtest/
- Instead, the best option I could find was to install the first-party Ookla speedtest CLI tool on the host alongside Python and then use a `subprocess.run()` to call the shell command from within Python. 
  - https://stackoverflow.com/questions/89228/how-do-i-execute-a-program-or-call-a-system-command this strongly recommends using subprocess.run instead of os.system
- The JSON output for download speed was `{'bandwidth': 21098621, 'bytes': 261577104, 'elapsed': 12800, 'latency': {'high': 208.025, 'iqm': 88.856, 'jitter': 17.118, 'low': 15.115}}` which has some interesting units. https://www.reddit.com/r/speedtest/comments/pvf3gj/deciphering_json_from_ookla_speedtest/ explains it, the bandwidth field is bytes per second using speedtest's secret sauce, divide by 125000 to get Mbps. Note that it does not end up calculating out to the same value as the bytes transferred over the elapsed time (in milliseconds)
- https://pimylifeup.com/raspberry-pi-internet-speed-monitor/comment-page-4/ found the undocumented `--accept-license --accept-gdpr` commands for speedtest that allow it to run without the interactive "please accept license" step on first execution
