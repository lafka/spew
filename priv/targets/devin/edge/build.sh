#!/bin/bash

set -ex

env

spew-build load-build alpine/edge

sudo chroot "$BUILDDIR" apk update
sudo chroot "$BUILDDIR" apk add alpine-sdk elixir gnupg
