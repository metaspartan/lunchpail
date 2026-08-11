# Architecture

```text
┌──────────────────────── Apple silicon host ────────────────────────┐
│ CLI                    native SwiftUI app          HTTP clients     │
│  │                     + VZVirtualMachineView       │               │
│  └──────────────┬───────────────────────────────────┘               │
│                 │                                                   │
│      shared registry, manifests, profiles, locks, cloning           │
│                 │                                                   │
│      loopback Hummingbird control plane + bearer token              │
│                 │                                                   │
│      Virtualization.framework lifecycle owner                      │
│                               │                                    │
│                VZMacGraphicsDeviceConfiguration                    │
│                               │                                    │
│       ParavirtualizedGraphics / host Apple GPU                     │
└───────────────────────────────┼────────────────────────────────────┘
                                │
┌──────────────────────── macOS guest ───────────────────────────────┐
│ selected workload process                                         │
│  ├─ DYLD_INSERT_LIBRARIES=libLunchpailMetalShim.dylib              │
│  ├─ LUNCHPAIL_METAL_APPLE_FAMILY_MAX=1009                         │
│  └─ stock Metal commands and virtual GPU driver                    │
│                                                                   │
│ every other process remains on stock capability answers           │
└───────────────────────────────────────────────────────────────────┘
```

## Invariants

1. The VM always uses Apple's public `Virtualization.framework` device model.
2. A Metal profile changes reported capability answers, never command buffers,
   timing, pipeline contents, argument layouts, or compiled kernels.
3. Missing or malformed profile input leaves the process on stock behavior.
4. Common, Mac, Metal, and unknown GPU-family ranges keep their stock answers.
5. Profiles are workload- and platform-specific. “Probe passed” and “workload
   certified” are separate states.
6. Host preference changes are explicit, journaled, and reversible.
7. A VM directory has one lifecycle owner; clone takes a shared source lock,
   run takes an exclusive lock, and a destination becomes visible only after
   all files and the manifest validate.
8. The HTTP control plane binds to loopback, authenticates management routes,
   and cannot execute arbitrary host commands.
9. A service-owned VM remains retained by the service until it stops, and
   service shutdown requests graceful guest shutdown before forcing a stop.
10. Portable manifest resources are owner-controlled descendants of the VM
    bundle. External host shares require a future, separate local grant.

## Milestones

### M0 — auditable host and guest primitives

- Host doctor
- Profile registry
- Transactional private-preference handling
- Capability shim and probe
- VM manifest validation and headless runner
- Atomic local-IPSW macOS creation and installation
- Native interactive console
- Atomic APFS copy-on-write clone and lifecycle locking
- Shared VM registry with Lume discovery
- Loopback HTTP API and OpenAPI schema
- Head-only Homebrew formula and install-layout verification

### M1 — first-boot GPU worker

- IPSW discovery, resumable download, and cache
- macOS 27 guest provisioning with SSH enabled
- ASIF base/cache/overlay storage
- read-only guest tools share
- guest agent enrollment and `lunchpail exec --metal`

### M2 — certification

- representative Metal compute canaries
- llama.cpp stock/profile benchmark runner (implemented for local guest use)
- host/guest/build/artifact hashes (implemented)
- signed compatibility records and automatic stock fallback

### M3 — image distribution

- content-addressed base images
- sparse/layered clones (APFS compatibility clone implemented)
- resumable transfer and OCI-compatible metadata where licensing permits
- launchd service packaging and crash-safe Metal preference reference counting
