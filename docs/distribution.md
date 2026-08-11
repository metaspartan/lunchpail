# Distribution

## Homebrew

`Formula/lunchpail.rb` is a head-only source formula for Apple silicon. It
builds and installs the CLI, Metal probe, and process-scoped shim, applies the
virtualization entitlement, and generates shell completions.

Verify the same installed layout locally:

```bash
make homebrew-stage
dist/homebrew/bin/lunchpail doctor
dist/homebrew/bin/lunchpail metal probe --profile cua-m1-llamacpp
```

The main repository is directly usable as an explicit-URL tap:

```bash
brew tap metaspartan/lunchpail https://github.com/metaspartan/lunchpail
brew install --HEAD metaspartan/lunchpail/lunchpail
```

A stable formula requires a tagged source archive and SHA-256 digest. A future
`homebrew-lunchpail` repository can provide the shorter one-argument tap syntax,
but it is not required for source installation.

## Native app

The development app uses ad-hoc signing so it can be tested locally. A public
Homebrew Cask requires a Developer ID signed, hardened-runtime archive,
notarization, stapling, and a stable download URL. Distribution credentials are
never stored in this repository.

## Release checklist

1. Run `make format-check`, `make verify`, and the real-VM smoke suite.
2. Build the release CLI artifacts and native app from a clean checkout.
3. Sign, notarize, staple, and validate the app and command-line artifacts.
4. Publish checksums, OpenAPI schema, compatibility record, and raw benchmarks.
5. Update the stable formula and Cask, then run strict Homebrew audit on a
   supported Xcode/Homebrew host.
