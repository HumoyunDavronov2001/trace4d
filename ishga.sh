#!/usr/bin/env bash
# TRACE4D serverini ishga tushirish
cd "$(dirname "$0")"
exec python3 -u yerosti_server.py --port 8342
