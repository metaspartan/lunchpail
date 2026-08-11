# Contributing

Lunchpail requires Apple silicon, macOS 15 or newer, and Xcode 16 or newer.

Before opening a pull request, run:

```bash
make format-check
make verify
swift build --configuration release
```

Keep the Swift runtime and native app on shared core types, preserve atomic VM
publication and lifecycle locking, and keep Metal profile changes scoped to one
guest process. New performance claims need pinned versions, raw samples, p50 and
p95, identical resources, and a precise statement of what the timer includes.

Report security issues through the private process in [SECURITY.md](SECURITY.md).
