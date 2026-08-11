# HTTP API

Start the local control plane:

```bash
lunchpail api serve
```

It listens on `127.0.0.1:7777` by default. Numeric IPv6 loopback `::1` is also
accepted; hostnames and non-loopback addresses are rejected. `/health` and
`/openapi.yaml` are public. Every `/v1` route requires the bearer token stored
at `~/.lunchpail/state/api-token` with mode `0600`.

```bash
TOKEN="$(lunchpail api token --show)"
curl http://127.0.0.1:7777/health
curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:7777/v1/host
curl -H "Authorization: Bearer $TOKEN" http://127.0.0.1:7777/v1/vms
```

The complete machine-readable contract is
[openapi.yaml](../Sources/LunchpailAPI/Resources/openapi.yaml). Responses use a
stable envelope with either `data` or `error`. VM identifiers are stable hashes
of canonical manifest paths; names are accepted only when unambiguous.

Starting a profiled VM fails closed unless the required host bridge preference
is already enabled. The API never enables it implicitly. VM start is
asynchronous, status reflects the retained runtime owner, and service shutdown
first requests guest shutdown before forcing any remaining VMs to stop.

The API intentionally has no arbitrary shell, command, file-read, or file-write
endpoint. Agent clients compose the typed inventory, clone, lifecycle, Metal
probe, and host-preference operations from the OpenAPI contract.

The API always uses the installed Metal probe and shim. Custom artifact paths
are available only to the interactive CLI. Imported manifest resources must be
owner-controlled descendants of the VM bundle; portable manifests cannot grant
a guest access to arbitrary host paths.
