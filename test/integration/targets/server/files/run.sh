#!/bin/bash

PORT=$((($RANDOM % 16384) + 1024))

runapp() {
	echo "ping" | ncat -l -p "$PORT" &
	spewtils publish state:running
	fg
}

spewtils connect port:inet state:waiting tags:app:test-stack | env

spewtils publish-after \
	state:stopped exit_status:\$exit_status? \
	-- runapp $@

