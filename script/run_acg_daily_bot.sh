#!/bin/sh
set -eu
export PATH=/usr/local/bin:/usr/bin:/bin
date -Iseconds
exec python3 /home/muwei/discourse-docker-preview/acg-daily/translate_titles.py
