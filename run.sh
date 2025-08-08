#!/usr/bin/bash

# Script to help execute on Linux Debian CT/LXC
cd /root/influx-scripts/
# UV will automatically create a .venv, install Python and dependencies, and run the files
/root/.local/bin/uv run tasmota-sensors.py
/root/.local/bin/uv run tasmota-plugs.py
/root/.local/bin/uv run apc.py
