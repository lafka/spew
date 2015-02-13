#!/bin/bash

set -e

command -v spew-build  >&2 || {
	echo "error: spew-build not found" >&2;
	exit 1;
}

dir="$(dirname "$(realpath "$0")")"

rm -rvf "$dir/builds/test-{client,server}"

export http_proxy=${http_proxy:-$HTTP_PROXY}
export SPEW_TARGETDIRS="$dir/targets"
export SPEW_BUILDS="$dir/builds"

mkdir -p "$SPEW_BUILDS"

spew-build delete-build busybox/0.0.1 test-client/0.0.1 test-server/0.0.1

spew-build build busybox/0.0.1
spew-build build test-client/0.0.1
spew-build build test-server/0.0.1

