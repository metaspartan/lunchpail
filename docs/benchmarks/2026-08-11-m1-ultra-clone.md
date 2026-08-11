# M1 Ultra APFS clone canary — 2026-08-11

This storage canary verifies Lunchpail's compatibility clone path on a real
macOS VM. It measures clone publication only, not boot or SSH readiness.

## Environment

- host: Apple M1 Ultra, 128 GiB unified memory
- host OS: macOS 27.0 build `26A5378n`
- source guest: stopped macOS 26.5.2 Tahoe VM
- source disk logical size: 161,061,273,600 bytes (150 GiB)
- source auxiliary storage logical size: 33,579,164 bytes
- source and destination: same APFS data volume
- comparison runtime: Lume 0.5.3

## Result

```json
{
  "elapsedSeconds": 0.004490017890930176,
  "logicalDiskBytes": 161061273600,
  "usedCopyOnWrite": true
}
```

The destination manifest then passed full
`VZVirtualMachineConfiguration.validate()`. Lunchpail generated a new
`VZMacMachineIdentifier` and locally administered MAC address, retained the
compatible hardware model, and published owner-only VM storage. Current builds
do not inherit portable host-directory shares during cloning.

An earlier integration clone of the same source was booted to macOS 26.5.2 and
obtained its own network lease before it was shut down through Lunchpail's
signal-aware runner. A concurrent clone attempt while that VM was running was
rejected without publishing a partial destination.

## Lume comparison

Five warm, end-to-end CLI runs cloned the same stopped source to unique
destinations on the same APFS volume. Timing includes process startup and
manifest work for both tools.

| Runtime | Samples (seconds) | p50 | p95 nearest-rank |
|---|---|---:|---:|
| Lunchpail | 0.03149, 0.02804, 0.02820, 0.02913, 0.02881 | 0.02881 | 0.03149 |
| Lume 0.5.3 | 2.20887, 2.21757, 2.22882, 2.21839, 2.22501 | 2.21839 | 2.22882 |

Lunchpail's p50 publication latency was 77.0× lower in this narrow test. Every
Lunchpail result reported copy-on-write and produced a validating manifest.
This does not measure boot-to-SSH latency or unique physical allocation.

## Interpretation

`clonefile` success is the correctness signal for the zero-copy APFS path.
Common tools such as `du` can charge shared extents to both paths, so this run
does not claim a precise unique-allocated-byte number. Tart comparison, unique
extent accounting, and boot-to-SSH measurements remain release work. Lunchpail
deliberately fails closed when copy-on-write is unavailable unless the caller
passes `--allow-full-copy`.
