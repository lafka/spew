#!/bin/bash

ALPINE_MIRROR=${ALPINE_MIRROR:-"http://distrib-coffee.ipsl.jussieu.fr/pub/linux/alpine/alpine/"}

sudo apk \
	-X "$ALPINE_MIRROR/edge/main" \
	-X "$ALPINE_MIRROR/edge/testing" \
	-U --allow-untrusted --root "$BUILDDIR" --initdb add alpine-base

mkdir -p "$BUILDDIR/etc/apk"
grep -q "$ALPINE_MIRROR" "$BUILDDIR/etc/apk/repositories" ||
	(
		sudo su -c "echo \"$ALPINE_MIRROR/edge/main\" > \"$BUILDDIR/etc/apk/repositories\"";
		sudo su -c "echo \"$ALPINE_MIRROR/edge/testing\" >> \"$BUILDDIR/etc/apk/repositories\"";
	)

sudo su -c "echo 'nameserver 8.8.8.8' > \"$BUILDDIR/etc/resolv.conf\""

# allowing chmod'ing
sudo su -c "echo 'kernel.grsecurity.chroot_deny_chmod = 0' >> \"$BUILDDIR/etc/sysctl.conf\""

