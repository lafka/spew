#!/bin/bash

SPEWHOST=http://127.0.0.1/ ./priv/spewtils buildroot "$BUILDDIR" curl bash busybox ncat

