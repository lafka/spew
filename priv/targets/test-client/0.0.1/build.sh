#!/bin/bash

command -v spewtils

SPEWHOST=http://127.0.0.1/ spewtils buildroot "$BUILDDIR" curl busybox bash ncat
