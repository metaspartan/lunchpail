# Security

## Supported version

Security fixes are applied to the latest commit on `main` until stable releases
begin.

## Reporting a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/metaspartan/lunchpail/security/advisories/new).
Do not open a public issue for an unpatched vulnerability. Include affected
versions, impact, reproduction steps, and any suggested remediation.

## Security boundaries

Lunchpail treats VM guests and imported manifests as untrusted. Portable VM
resources must remain inside their owner-controlled bundle. The HTTP API binds
only to numeric loopback, authenticates all management routes, and does not
accept executable or dynamic-library paths. Metal capability changes are
process-scoped, canary-validated, and separate from the journaled host bridge
preference.

The local API token protects against other users and clients that have not been
given the token. It is not a sandbox boundary against arbitrary code already
running as the same macOS account.
