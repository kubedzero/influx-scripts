#!/usr/bin/zsh
cd /root/influx-scripts-python/
/root/.pyenv/shims/pipenv run python3 tasmota-sensors.py
/root/.pyenv/shims/pipenv run python3 tasmota-plugs.py
/root/.pyenv/shims/pipenv run python3 apc.py