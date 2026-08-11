# M1 Ultra VM inventory benchmark — 2026-08-11

This benchmark measures warm, end-to-end CLI inventory latency. It includes
process startup, VM discovery, manifest validation, sorting, JSON encoding, and
process exit. It does not measure VM boot or guest execution.

## Environment

- host: Apple M1 Ultra, 128 GiB unified memory
- host OS: macOS 27.0 build `26A5378n`
- Lunchpail: release build from the 2026-08-11 working tree
- comparison runtime: Lume 0.5.3
- inventory: the same stopped local macOS VM set
- warmups: 3 per runtime
- measured samples: 30 per runtime

## Result

| Runtime | p50 | p95 nearest-rank |
|---|---:|---:|
| Lunchpail | 16.67 ms | 18.49 ms |
| Lume 0.5.3 | 27.80 ms | 30.80 ms |

Lunchpail was 1.67× faster at p50 in this narrow comparison.

## Raw samples

```json
{
  "lunchpailSeconds": [
    0.017701042, 0.019347542, 0.018205834, 0.018493292, 0.016681291,
    0.016780667, 0.017435333, 0.018470959, 0.016814041, 0.016526875,
    0.016692916, 0.016190917, 0.016360334, 0.018135958, 0.016443709,
    0.016660625, 0.016069334, 0.016110500, 0.016342000, 0.016573625,
    0.016022875, 0.016606458, 0.016640208, 0.016263208, 0.017174417,
    0.017467250, 0.016650250, 0.016476000, 0.017262917, 0.017969625
  ],
  "lumeSeconds": [
    0.028076500, 0.026366708, 0.029054875, 0.027788167, 0.027949541,
    0.027435041, 0.027777708, 0.026751542, 0.028487541, 0.027137500,
    0.025964750, 0.026937250, 0.026838041, 0.026552709, 0.028957292,
    0.028937458, 0.029054875, 0.031414541, 0.030795625, 0.028090459,
    0.026888750, 0.027811500, 0.027482542, 0.026669083, 0.027822042,
    0.027780917, 0.028069125, 0.028065709, 0.027990667, 0.027537292
  ]
}
```

## Reproduce

Build both runtimes in release mode, keep the inventory unchanged, and run:

```bash
make benchmark-inventory
```

Override binary locations or sample counts when needed:

```bash
python3 Scripts/benchmark-inventory.py \
  --lunchpail /path/to/lunchpail \
  --lume /path/to/lume \
  --samples 30 \
  --warmups 3
```

The script emits the full samples, host fingerprint, p50, nearest-rank p95, and
p50 speedup as JSON. Comparing Apple container requires a separate Linux
create-to-exec harness because it does not run macOS guests or Metal workloads.
