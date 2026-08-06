#!/bin/sh
# azazel cache-key: a portable content key for this build, computed from the
# model and its inputs WITHOUT invoking the compiler. Identical inputs produce
# an identical key on any machine, so it can address a shared artifact cache — a
# remote cache without the remote-execution machinery. The key covers:
#   - the normalized build model (cue export)
#   - every .zig source under each module root's tree (content-hashed)
#   - the pinned dependency identities from build.zig.zon (url + hash)
#   - the toolchain: the model's preferred lane and the resolved zig version
# Over-invalidation is sound: a superfluous miss just rebuilds; a stale hit
# cannot happen because any changed input changes the key.
set -eu
cd "$(dirname "$0")"

MODEL=$(cue export -e build)

SRC_HASHES=$(printf '%s' "$MODEL" | python3 -c '
import json, sys, os
d = json.load(sys.stdin)
dirs = set(os.path.dirname(m["root"]) or "." for m in d["modules"].values())
files = set()
for base in dirs:
    if not os.path.isdir(base):
        # a single-file root whose dir was already added; also cover the file
        continue
    for dp, _, fs in os.walk(base):
        for f in fs:
            if f.endswith(".zig"):
                files.add(os.path.join(dp, f))
for m in d["modules"].values():
    if os.path.isfile(m["root"]):
        files.add(m["root"])
for f in sorted(files):
    print(f)
' | while IFS= read -r f; do [ -f "$f" ] && shasum -a 256 "$f"; done)

DEPS=$( [ -f build.zig.zon ] && grep -E '\.url|\.hash' build.zig.zon | sed 's/^[[:space:]]*//' | sort || true )
LANE=$(printf '%s' "$MODEL" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("toolchain",{}).get("zig",{}).get("preferred",""))')
ZIGV=$(zig version 2>/dev/null || echo unknown)
# Artifacts are platform-specific: a macOS build and a Linux build of the same
# model produce different bytes, so the host OS+arch is part of the key. Without
# this a cross-platform hit would restore the wrong binary.
HOST=$(uname -sm 2>/dev/null || echo unknown)

printf '%s\n%s\n%s\nlane=%s\nzig=%s\nhost=%s\n' "$MODEL" "$SRC_HASHES" "$DEPS" "$LANE" "$ZIGV" "$HOST" | shasum -a 256 | cut -d' ' -f1
