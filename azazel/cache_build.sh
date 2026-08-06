#!/bin/sh
# azazel shared-cache build: compute the model-derived key, and if that exact
# build is already in a shared artifact store, restore its output and skip the
# build entirely. Otherwise build, then store the output under the key.
#
# Two free backends, no paid infrastructure:
#   - GitHub Releases (default when a repo is known): assets named <key>.tar on a
#     single release act as a content-addressed store, free on public repos and
#     reachable from any machine or CI runner via `gh`. Set the repo with
#     AZAZEL_CACHE_REPO=owner/repo (or it is read from the current git remote),
#     and the release tag with AZAZEL_CACHE_RELEASE (default "cache").
#   - Local directory: set SHARED=/path (a shared mount, or synced folder).
#
# This is the transferable half of a remote cache — caching, not remote
# execution — with the key computed from the pinned model instead of discovered
# by compiling.
set -eu
cd "$(dirname "$0")"

KEY=$(sh cache_key.sh)
ASSET="$KEY.tar"

restore() { # <tarfile>
    rm -rf zig-out && mkdir -p zig-out && tar -xf "$1" -C zig-out
    echo "[azazel-cache] HIT  $KEY"
}

build_and_tar() { # <out-tar>
    echo "[azazel-cache] MISS $KEY — building"
    sh gen_build_spec.sh
    zig build
    tar -cf "$1" -C zig-out .
}

# Resolve the GitHub backend: explicit repo, else the current git remote.
REPO="${AZAZEL_CACHE_REPO:-}"
if [ -z "$REPO" ] && command -v gh >/dev/null 2>&1; then
    REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
fi
REL="${AZAZEL_CACHE_RELEASE:-cache}"

# Prefer the free GitHub Releases backend when gh + a repo are available and
# SHARED was not explicitly requested.
if [ -z "${SHARED:-}" ] && [ -n "$REPO" ] && command -v gh >/dev/null 2>&1; then
    tmp=$(mktemp -d)
    if gh release download "$REL" --repo "$REPO" --pattern "$ASSET" --dir "$tmp" >/dev/null 2>&1; then
        restore "$tmp/$ASSET"; rm -rf "$tmp"; exit 0
    fi
    build_and_tar "$tmp/$ASSET"
    gh release view "$REL" --repo "$REPO" >/dev/null 2>&1 || \
        gh release create "$REL" --repo "$REPO" --title "azazel shared cache" \
            --notes "Content-addressed build artifacts, keyed by the azazel build model." >/dev/null 2>&1 || true
    if gh release upload "$REL" "$tmp/$ASSET" --repo "$REPO" --clobber >/dev/null 2>&1; then
        echo "[azazel-cache] uploaded $KEY to $REPO ($REL)"
    else
        echo "[azazel-cache] built $KEY (upload skipped: no write access to $REPO)"
    fi
    rm -rf "$tmp"
    exit 0
fi

# Local-directory backend.
SHARED="${SHARED:-$HOME/.azazel-shared-cache}"
mkdir -p "$SHARED"
if [ -f "$SHARED/$ASSET" ]; then
    restore "$SHARED/$ASSET"
    exit 0
fi
build_and_tar "$SHARED/$ASSET"
echo "[azazel-cache] stored $KEY in $SHARED"
