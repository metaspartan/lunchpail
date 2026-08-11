# Research snapshot — 2026-08-11

## Finding

The credible product is a **Metal-aware macOS VM runtime**, not a new hypervisor
and not a Linux container runtime. Apple already supplies the hard part: a
paravirtualized macOS graphics device whose work executes on the host GPU.
The newly demonstrated bottleneck is capability negotiation inside the guest.

Cua measured llama.cpp prompt/generation improvements of 11.08×/16.36× for
TinyLlama, 7.20×/14.54× for Gemma 4 12B, and 7.55×/8.87× for Muse Glimmer 30B
on one M1 Ultra. Its reduced shim changes only Apple-family answers and maximum
threadgroup memory. MLX-LM remained flat, which is important evidence against a
blanket “faster Metal” claim. Source: [Cua's release and raw methodology](https://github.com/trycua/cua/blob/main/blog/gpu-passthrough-macos-vms.md).

The released implementation is small, process-scoped, and MIT licensed:
[source and build artifacts](https://github.com/trycua/cua/tree/main/libs/lume/metal-capability-shim).

## Platform facts

- [`Virtualization.framework`](https://developer.apple.com/documentation/virtualization)
  creates and runs macOS and Linux VMs. A macOS guest uses
  `VZMacGraphicsDeviceConfiguration`.
- Apple's [Paravirtualized Graphics framework](https://developer.apple.com/documentation/paravirtualizedgraphics)
  describes a guest driver communicating with a host framework that uses
  Metal-accelerated graphics.
- Apple's [Metal capability tables](https://developer.apple.com/metal/capabilities/)
  make runtime GPU-family and limit queries part of the supported feature
  selection model.
- Apple's [`container`](https://github.com/apple/container) and
  [`containerization`](https://github.com/apple/containerization) projects are
  Swift-based Linux-container runtimes over lightweight VMs. They do not give a
  Linux guest Apple's Metal framework.
- [Tart](https://github.com/openai/tart) and
  [`macosvm`](https://github.com/s-u/macosvm) already cover general macOS VM
  creation and automation. Tart still has an open user report framed as
  [missing GPU passthrough](https://github.com/openai/tart/issues/1032).
- macOS 27 adds automated macOS guest provisioning, layered DiskImageKit images,
  advanced networking, USB accessory access, and custom Virtio devices. Those
  are useful for rapid ephemeral AI workers but do not replace the virtual GPU:
  [WWDC26 Virtualization session](https://developer.apple.com/videos/play/wwdc2026/224/).

## Local reproduction

Host used for this snapshot:

- Apple M1 Ultra, 64 GPU cores, 128 GiB unified memory
- macOS 27.0, build `26A5378n`
- Xcode 26.6 / Apple Swift 6.3.x
- Cua commit `9bd4221e523efa7da67bb0516918f1956849833a`

Cua's released source built successfully. Its probe returned:

| Probe | Apple family 9 | Maximum threadgroup memory |
|---|---:|---:|
| stock host process | false | 32,768 bytes |
| injected profile | true | 65,536 bytes |

The end-to-end test then used Cua's published Tahoe image as a 64 GiB, 8-vCPU
guest. Lunchpail imported its real hardware identity, validated the resulting
`VZVirtualMachineConfiguration`, and booted it successfully with Lunchpail's
own runner. The stock guest exposed Apple family 5 and 32 KiB of threadgroup
memory. The scoped profile exposed Apple family 9 and 64 KiB, without changing
the Metal 3 or recommended-working-set answers.

With the exact same llama.cpp b10359 and TinyLlama Q4_K_M artifacts, the
three-repetition `llama-bench` averages were:

| Work | Stock guest | Profiled guest | Speedup | Bare host |
|---|---:|---:|---:|---:|
| prompt, 512 tokens | 396.82 tok/s | 5,122.03 tok/s | 12.91× | 5,163.84 tok/s |
| generation, 128 tokens | 8.06 tok/s | 167.36 tok/s | 20.75× | 250.95 tok/s |

The profiled guest reached 99.2% of host prompt throughput. These numbers are a
single-platform research canary, not a general compatibility guarantee. Full
commands, hashes, and caveats are in
[the benchmark record](benchmarks/2026-08-11-m1-ultra.md).

## Gap to fill

The differentiated path is:

1. Fast macOS VM lifecycle, using ASIF/layered disks where available.
2. Automatic first-boot enrollment and a narrow guest agent.
3. A host-side Metal profile registry keyed by chip, host build, guest build,
   workload, and artifact hashes.
4. Stock/unlocked canaries that compile and execute representative kernels,
   not just capability queries.
5. Process-scoped workload launch with automatic fallback to stock after any
   failed canary.
6. Reproducible benchmark evidence and signed compatibility manifests.

That makes “day-zero Metal” mean the VM is GPU-ready from its first workload,
while still refusing capability claims that have not been tested.

## Why Swift plus Objective-C

Swift is the lowest-friction and most future-proof language for Apple-only
Virtualization, Metal, Security, and DiskImageKit APIs. Rust would add FFI and
Objective-C runtime surface without making Apple's hypervisor or GPU bridge
faster. The guest hook itself should stay in Objective-C because it interposes
Objective-C Metal device methods and needs to remain tiny enough to audit.

Rust remains a reasonable later choice for a cross-platform guest agent, but it
is not the right center of gravity for the host runtime.

## Risks

- The unrestricted feature-level preference and the hook point are private,
  undocumented, and may change on any macOS update.
- Capability advertisement can select an API that the virtual device cannot
  execute. Cua observed this when advertising Metal 3 to MLX.
- `DYLD_INSERT_LIBRARIES` is ignored by some hardened or platform-protected
  processes. Lunchpail should never weaken SIP automatically.
- The preference is per-user rather than per-VM, so robust lifecycle management
  needs a lock, previous-state journal, and crash recovery.
- GPU API exposure broadens the attack surface. Profiles should be used only
  with trusted guest workloads until Apple's security boundary is documented.
