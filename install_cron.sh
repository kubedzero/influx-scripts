#!/usr/bin/bash

# Script to add Python execution to a crontab on a per minute basis
# https://stackoverflow.com/a/878647

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -euxo pipefail

# Write out current crontab
crontab -l > newcron
# Echo new cron into cron file
# https://github.com/koalaman/shellcheck/wiki/SC2164
# https://github.com/koalaman/shellcheck/wiki/SC2129
# UV will automatically create a .venv, install Python and dependencies, and run the files
{
  echo "* * * * * cd /root/influx-scripts || exit && /usr/bin/nice -n 10 /root/.local/bin/uv run tasmota-sensors.py"
  echo "* * * * * cd /root/influx-scripts || exit && /usr/bin/nice -n 10 /root/.local/bin/uv run tasmota-plugs.py"
  echo "* * * * * cd /root/influx-scripts || exit && /usr/bin/nice -n 10 /root/.local/bin/uv run apc.py"
  echo "0,30 * * * * cd /root/influx-scripts || exit && /usr/bin/nice -n 10 /root/.local/bin/uv run speedtest.py"
  echo "* * * * * cd /root/influx-scripts || exit && /usr/bin/nice -n 10 /root/.local/bin/uv run unraid.py"
} >> newcron
# Install new cron file and clean up temporary file
crontab newcron
rm newcron
