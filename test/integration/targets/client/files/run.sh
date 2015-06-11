#!/bin/bash

spewtils connect state:waiting tags:app:test-stack | env

spewtils await appliance:test-server SERVER | env
spewtils publish state:running

echo "pong" | ncat "$SERVER_IP" -p "$SERVER_PORT"
