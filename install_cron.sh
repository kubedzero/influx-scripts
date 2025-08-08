#!/usr/bin/bash

# Script to add Python execution to a crontab on a per minute basis
# https://stackoverflow.com/a/878647

# Write out current crontab
crontab -l > newcron
# Echo new cron into cron file
echo "* * * * * /root/influx-scripts/run.sh" >> newcron
# Install new cron file
crontab newcron
rm newcron