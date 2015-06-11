#!/bin/bash

set -e

eval export $(spewtils connect state:waiting tags:app:test-stack)

eval export $(spewtils await "(appliance:test-server AND state:running)" SERVER)
spewtils publish state:running

echo "connect: $SERVER_IP4:$SERVER_PORT"
echo "ping" | ncat "$SERVER_IP4" "$SERVER_PORT"
