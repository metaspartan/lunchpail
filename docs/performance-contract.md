# Performance contract

Lunchpail should win on measured workflows, not on an undifferentiated claim
that every virtual machine is faster. All comparisons use pinned artifacts,
identical CPU and memory allocations, the same host power state, repeated runs,
and published raw samples.

## Comparable products

- **Lume and Tart:** compare macOS install, clone, boot, SSH readiness, idle
  overhead, disk/network I/O, and macOS Metal workload throughput.
- **Apple container:** compare only arm64 Linux container workloads: image pull,
  create, start-to-exec, filesystem/network I/O, memory overhead, and teardown.
  Apple container does not run a macOS guest or expose Apple's Metal framework
  to Linux, so a Metal throughput comparison would be meaningless.
- **Bare metal:** use as an efficiency ceiling for the same macOS AI binary and
  model, not as another VM runtime.

## Release gates

| Path | Metric | Gate |
|---|---|---|
| macOS | warm start to SSH p50/p95 | no regression versus the fastest pinned competitor |
| macOS | copy-on-write clone p50/p95 and allocated bytes | materially lower than full sparse-image copy |
| macOS | sequential/random disk and network throughput | within 5% of the fastest pinned competitor |
| macOS Metal | validated AI prompt throughput | at least 95% of the same bare-host run |
| macOS Metal | stock/profile correctness canaries | zero mismatches; automatic stock fallback on failure |
| Linux | create-to-exec p50/p95 | measured against Apple container on the same OCI image |
| both | idle host memory and CPU | no regression versus the fastest pinned competitor |
| both | crash recovery | no orphaned VM owner or Metal preference journal |

The current TinyLlama canary passes the macOS Metal prompt gate at 99.19% of
bare-host throughput. Generation is 66.69% and remains an optimization target.
The current compatibility storage path also cloned and validated a 150 GiB
logical macOS disk in 4.49 ms using APFS `clonefile`. In five end-to-end CLI
runs, Lunchpail clone publication measured 28.81 ms p50 versus 2.218 seconds for
Lume 0.5.3, a 77.0× p50 improvement. This is a clone-publication result, not a
broad runtime win; Tart, boot-to-SSH, and reliable unique-allocated-byte
comparisons are still required.

Thirty warm end-to-end inventory runs measured 16.67 ms p50 and 18.49 ms p95
for Lunchpail versus 27.80 ms p50 and 30.80 ms p95 for Lume 0.5.3. The 1.67×
p50 result covers process startup, VM discovery, validation, sorting, JSON
encoding, and process exit. It is not a VM execution or boot benchmark.

The CLI and API deliberately use the same registry, manifest validation,
lifecycle locks, clone implementation, and Metal policy. The HTTP path adds no
polling loop to a running VM and retains the native virtual-machine owner for
the full lifetime. Release builds produce only the three Homebrew products,
avoiding the unrelated GUI build in source installations.

## Fast-path architecture

1. Use macOS 27 guest provisioning to remove interactive installation where
   available, with a compatibility installer for earlier hosts.
2. Use DiskImageKit ASIF base/cache/overlay layers on macOS 27 and APFS
   copy-on-write clones as the compatibility path.
3. Keep one long-lived, signed owner process for VM lifecycle, network leases,
   and crash-safe reference counting of the private graphics preference.
4. Mount tools and large immutable assets read-only; put mutable state in a
   disposable overlay.
5. Cache Metal canaries by host chip/build, guest build, workload build, and
   artifact hashes. A cache miss runs stock first and never assumes support.
6. Keep CLI and GUI as clients of the same core/daemon rather than duplicating
   lifecycle logic.

The next storage milestone is an ASIF-backed immutable base with per-VM cache
and overlay layers. It must beat the APFS clone compatibility path on allocated
bytes, sustained random I/O, and p95 clone/start latency before it becomes the
default. Unsafe cache modes will not be used to manufacture benchmark wins.

## Supported creation matrix

| Guest/source | Product path | Metal |
|---|---|---|
| macOS IPSW | provision, install, reusable base, overlay clone | host-backed Metal with validated profiles |
| Lunchpail/Lume macOS manifest | zero-copy import and native run | host-backed Metal with validated profiles |
| arm64 Linux OCI image | OCI unpack to minimal rootfs and lightweight VM | no Apple Metal API |
| arm64 Linux raw disk/kernel | direct Virtualization.framework boot | no Apple Metal API |

Intel-only operating systems require emulation rather than Apple
Virtualization and are outside the performance-critical runtime.
