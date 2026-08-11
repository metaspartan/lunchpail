# Lunchpail

[![CI](https://github.com/metaspartan/lunchpail/actions/workflows/ci.yml/badge.svg)](https://github.com/metaspartan/lunchpail/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

Lunchpail is a native Apple silicon VM runtime for macOS AI workloads. It uses
Apple's `Virtualization.framework`, exposes an interactive SwiftUI console, and
adds validated, process-scoped Metal capability profiles inside macOS guests.

It is not physical GPU passthrough. Metal commands still use Apple's
paravirtualized graphics bridge. Unknown host, guest, and workload combinations
stay on Apple's stock capability answers.

## Quick start

```bash
swift build
make sign

.build/debug/lunchpail doctor
.build/debug/lunchpail vm list
.build/debug/lunchpail vm create macos tahoe --ipsw /path/to/Restore.ipsw
.build/debug/lunchpail vm import-lume ~/.lume/my-vm --profile cua-m1-llamacpp
.build/debug/lunchpail vm run my-vm
```

Launch the native app:

```bash
./script/build_and_run.sh
```

## Homebrew

The source formula supports Apple silicon and installs the CLI, Metal probe,
shim, shell completions, and required virtualization entitlement:

```bash
brew tap metaspartan/lunchpail https://github.com/metaspartan/lunchpail
brew install --HEAD metaspartan/lunchpail/lunchpail
```

The repository is also an explicit-URL Homebrew tap. The formula is at
[Formula/lunchpail.rb](Formula/lunchpail.rb), and its installed layout is covered
locally by `make homebrew-stage`. Release and Cask requirements are tracked in
[docs/distribution.md](docs/distribution.md).

## VM commands

```bash
lunchpail vm list
lunchpail vm info <id-or-name>
lunchpail vm add /path/to/lunchpail.json
lunchpail vm create macos tahoe --ipsw /path/to/Restore.ipsw
lunchpail vm import-lume ~/.lume/my-vm --profile cua-m1-llamacpp
lunchpail vm clone my-vm ~/.lunchpail/vms/my-vm-copy
lunchpail vm validate my-vm
lunchpail vm run my-vm
```

`vm run` owns the VM in the foreground. One Control-C requests guest shutdown;
a second force-stops it. APFS clones are atomic, generate a new machine identity
and MAC address, and refuse full copies unless `--allow-full-copy` is supplied.
`vm create macos` installs a supported local IPSW into an atomic 80 GiB sparse
VM by default; `--cpu-count`, `--memory-gib`, `--disk-gib`, and `--destination`
override its resources and location.

For service-owned VMs:

```bash
lunchpail api serve
lunchpail vm start my-vm
lunchpail vm status my-vm
lunchpail vm stop my-vm
lunchpail vm stop my-vm --force
```

## Metal containers

A Lunchpail Metal container is a capability-scoped guest process, not a Linux
or macOS filesystem container. It verifies the selected profile and replaces
itself with the workload so exit codes and signals remain native.

Enable the private host bridge explicitly before starting a profiled VM:

```bash
lunchpail metal host enable --acknowledge-private-api-risk
```

Inside the macOS guest:

```bash
lunchpail metal profiles
lunchpail metal probe --profile cua-m1-llamacpp
lunchpail metal container --profile cua-m1-llamacpp -- /path/to/workload
```

Restore the host setting after affected VMs stop:

```bash
lunchpail metal host restore
```

The current M1 Ultra/Tahoe/TinyLlama certification measured 12.37× prompt and
18.16× generation speedups. The complete artifact hashes and samples are in
[the certification record](docs/benchmarks/2026-08-11-m1-ultra-certification.json).

## HTTP API

The API binds only to loopback, creates a 256-bit token with mode `0600`, and
serves its OpenAPI 3.1 document without authentication:

```bash
lunchpail api serve
lunchpail api status
lunchpail api token

TOKEN="$(lunchpail api token --show)"
curl http://127.0.0.1:7777/health
curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:7777/v1/vms
curl http://127.0.0.1:7777/openapi.yaml
```

The API supports host inspection, Metal profiles and probes, transactional host
preference changes, VM inventory, Lume import, APFS clone, and asynchronous VM
start, status, and stop. It intentionally does not expose arbitrary host command
execution. See [docs/api.md](docs/api.md) and the
[OpenAPI document](Sources/LunchpailAPI/Resources/openapi.yaml).

## Performance contract

Lunchpail publishes narrow, reproducible comparisons instead of claiming every
VM operation is faster:

- Metal throughput is compared with the same binary and model on stock guest,
  profiled guest, and bare metal.
- macOS lifecycle and I/O are compared with pinned Lume and Tart versions.
- Linux create-to-exec is compared with Apple container using the same OCI
  image; Apple container is not a macOS or Metal competitor.
- A 150 GiB logical APFS VM clone completed in 4.49 ms on this M1 Ultra.
- Five end-to-end clone runs measured 28.81 ms p50 versus 2.218 seconds for
  Lume 0.5.3, a 77.0× p50 improvement on this host.
- Thirty warm inventory runs measured 16.67 ms p50 versus 27.80 ms for Lume
  0.5.3, a 1.67× end-to-end CLI improvement.

Release gates and remaining ASIF/layered-storage work are documented in
[docs/performance-contract.md](docs/performance-contract.md). Raw inventory
samples and reproduction commands are in
[the inventory benchmark](docs/benchmarks/2026-08-11-m1-ultra-inventory.md).

## Development

Requirements are Apple silicon, macOS 15 or newer, and Xcode 16 or newer.

```bash
make test
make verify
make format-check
swift build -c release
./script/build_and_run.sh --verify
```

The host runtime is Swift 6. The small Objective-C Metal interposer retains its
upstream MIT notice; everything else is Apache-2.0. Architecture and research
details live in [docs/architecture.md](docs/architecture.md) and
[docs/research.md](docs/research.md).
