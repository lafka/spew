#!/bin/sh

set -e

self="$(dirname $(realpath $0))"

for vsn in archive-unsigned archive-gpg-signed; do
	dir=$(mktemp -d)

	cd $dir

	cat > $dir/SPEWMETA << EOF
TARGET=spew
VSN=$vsn
SRCREF=nil
SRCFLAVOUR=nil
BUILDDATE=2015-05-11T11:20:50+00:00
BUILDUNAME=Linux nyx.x 3.19.3-3-ARCH #1 SMP PREEMPT Wed Apr 8 14:10:00 CEST 2015 x86_64 GNU/Linux
EOF

	target=$self/../builds/spew/$vsn/$vsn.tar
	mkdir -p "$(dirname "$target")"
	rm -vf "$target" "$target.asc"
	echo "generating $target"
	(cd "$dir" && tar cf "$target" .)
	rm -rf "$dir"
done

echo "signing $target"
gpg --armor --detach-sign "$self/../builds//spew/archive-gpg-signed/archive-gpg-signed.tar"
