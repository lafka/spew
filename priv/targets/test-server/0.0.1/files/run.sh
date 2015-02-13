#!/bin/bash

set -e

PORT=$((($RANDOM % 16384) + 1024))

eval export $(spewtils connect "port:$PORT" state:waiting tags:app:test-stack)

spewtils publish state:running
echo "listening 0.0.0.0:$PORT"
echo "pong" | ncat -l -p "$PORT"
spewtils publish state:stopped exit_status:$?
