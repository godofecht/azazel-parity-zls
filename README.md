# azazel-parity-zls

[zls](https://github.com/zigtools/zls)'s `Uri` — a self-contained std-only URI
parse/normalize module — built two ways, to prove and compare
[azazel](https://github.com/godofecht/azazel) and
[zaza](https://github.com/godofecht/zaza).

Both build a consumer that parses `https://example.com/a/../b` and prints the
normalized raw string, on Zig `0.17.0-dev.892` (zls's real toolchain family).
azazel reaches it through its `"0.17"` lane.

Neither vendors zls's source; each stages the single `Uri.zig` file at a pinned
commit with its own `fetch.sh`.

## Pinned upstream

| | |
|---|---|
| Repository | https://github.com/zigtools/zls |
| Commit | `8da87d4f3305a550e7b739bad764e34bf1e46a08` |
| File | `src/Uri.zig` |
| Zig | `0.17.0-dev.892+54537285c` |

## Build it

```sh
cd azazel && ./fetch.sh && sh gen_build_spec.sh && zig build && ./zig-out/bin/consumer
cd zaza  && ./fetch.sh && zig build run
```

Both print `zls uri: raw=https://example.com/a/../b`.

## Comparison

Clean-cache builds with dependencies pre-fetched, Apple Silicon, fastest of two runs.


| Build | Clean build | Config |
|-------|-------------|--------|
| azazel | 3.5 s | `project.cue` — 14 lines · 435 B |
| zaza | 3.3 s | `build.zig` — 12 lines · 734 B |

The upstream's full build is not reproduced here (see the note below), so no native time is listed.

**This is one of two repos where zaza's few lines undercut the CUE; zls's full build needs deps that don't compile on the available 0.17 toolchains.**

