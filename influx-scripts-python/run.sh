#!/usr/bin/zsh
cd /root/influx-scripts-python/
/root/.pyenv/shims/pipenv run python3 esp.py
/root/.pyenv/shims/pipenv run python3 tasmota.py
/root/.pyenv/shims/pipenv run python3 apc.py