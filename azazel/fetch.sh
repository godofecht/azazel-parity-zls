#!/bin/sh
set -eu
ZLS_COMMIT=8da87d4f3305a550e7b739bad764e34bf1e46a08
DIR=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$DIR/vendor"
if [ -f "$DIR/vendor/Uri.zig" ]; then echo "already staged"; exit 0; fi
curl -sL "https://raw.githubusercontent.com/zigtools/zls/$ZLS_COMMIT/src/Uri.zig" -o "$DIR/vendor/Uri.zig"
echo "Uri.zig staged"
