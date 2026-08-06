# Shared content-addressed cache

`cache_key.sh` and `cache_build.sh` turn Azazel's build-as-data into a portable,
shareable artifact cache — the transferable half of a remote build cache, without
the remote-execution machinery.

## The key is computed from the model, not discovered by compiling

`cache_key.sh` prints a content key for the build, computed **without invoking the
compiler**, from:

- the normalized build model (`cue export`),
- every `.zig` source under each module root (content-hashed),
- the pinned dependency identities in `build.zig.zon` (url + hash),
- the toolchain (the model's preferred lane and the resolved `zig version`).

Identical inputs produce an identical key on any machine. Over-invalidation is
sound: a superfluous miss just rebuilds; a stale hit cannot happen, because any
changed input changes the key.

## Skip the build on a hit — over a free store

`cache_build.sh` computes the key and, if that exact build is already stored,
restores `zig-out` and skips the build; otherwise it builds and stores the output
under the key. Two backends, both free — no paid infrastructure:

**GitHub Releases (default, shareable across machines + CI).** Artifacts are
assets named `<key>.tar` on a single release, free on public repos and reachable
from any machine or CI runner via `gh`:

```sh
AZAZEL_CACHE_REPO=owner/azazel-cache  sh cache_build.sh
```

The repo defaults to the current git remote if unset; the release tag defaults to
`cache` (`AZAZEL_CACHE_RELEASE`). The first machine to build a given input set
uploads the result; every other machine and CI run downloads it.

**Local directory (a shared mount or synced folder).**

```sh
SHARED=/path/to/shared/store  sh cache_build.sh
```

## Why Zig's own cache doesn't already do this

Zig's cache is local and content-addressed per artifact, so a warm rebuild on the
*same* machine is fast. But a fresh machine with an empty `~/.cache/zig` has to
rebuild from scratch. Azazel can compute the whole-build key from the committed
model *before* running the compiler, so a fresh machine addresses the shared
store and restores the finished artifact instead of building.

Measured (libvaxis slice, zigimg + uucode): a fresh machine cold-builds in ~9.3s;
a second fresh machine with an empty Zig cache restores the (working) artifact
instead of building — ~0.6s from a local store, or ~2.9s over the free GitHub
Releases backend (the extra time is the network download). Either way a fresh
machine skips the compile, which Zig's local cache alone cannot do.
