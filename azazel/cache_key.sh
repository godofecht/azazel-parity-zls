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
import json, sys, os, re
# Hash only the sources this build actually compiles: walk the @import graph
# from each module root and include only files reachable through it. This is
# "compile only what you use" applied to the cache key — a .zig file that sits
# under a module root'"'"'s directory but is never imported does not affect the
# build, so it must not affect the key. Following the real import edges (instead
# of every file in the tree) stops such files from spuriously invalidating the
# cache. Only imports that resolve to a sibling .zig file are followed; package
# imports (@import("std"), or a named dependency) do not end in .zig and are
# pinned separately via build.zig.zon, so they are skipped here.
IMPORT = re.compile(r"@import\(\s*\"([^\"]+)\"\s*\)")
roots = [m["root"] for m in json.load(sys.stdin)["modules"].values()]
seen, stack = set(), [os.path.normpath(r) for r in roots if os.path.isfile(r)]
while stack:
    f = stack.pop()
    if f in seen:
        continue
    seen.add(f)
    try:
        src = open(f, "r", encoding="utf-8", errors="replace").read()
    except OSError:
        continue
    base = os.path.dirname(f)
    for spec in IMPORT.findall(src):
        if not spec.endswith(".zig"):
            continue
        cand = os.path.normpath(os.path.join(base, spec))
        if os.path.isfile(cand) and cand not in seen:
            stack.append(cand)
for f in sorted(seen):
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
