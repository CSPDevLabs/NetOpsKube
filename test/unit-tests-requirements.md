# NetOpsKube unit-test requirements

Each requirement is linked to one or more BATS unit tests with a
`# bats test_tags=req:<ID>` tag.

- `CFG-01`: Make variables keep documented defaults.
- `CLAB-01`: Containerlab prerequisite checks require the SR-SIM image and license file.
- `CLONE-01`: Repository clone targets preserve existing checkouts.
- `DIAG-01`: `os-shell` and `proxy-env` print their settings as JSON.
- `DIA-01`: DIA Flux Kustomizations use the configured `FLUX_DIA_KUST_PREFIX`.
- `GNMIC-01`: gNMI subscription verification warns and succeeds when no targets exist.
- `GITEA-01`: The Gitea manifest patch sets the pullable image and is idempotent.
- `HELP-01`: Make help targets list the relevant targets and help exits successfully.
- `KIND-01`: The tracked KinD configuration uses the expected subnets and IPv4 networking.
- `KIND-02`: Generated KinD configuration includes ingress labels, port mapping, subnets, and IPv4 networking.
- `LB-01`: `update-kpt-lb-setters` writes the expected addresses and is idempotent.
- `LB-02`: LB setter targets fail when required network or kpt checkout inputs are missing.
- `LB-03`: `show-kind-lb-setters` prints the detected prefix and setter values.
- `NET-01`: Gitea addresses derive from the KinD prefix and configured host octets.
- `RCP-01`: Recipe verification rejects unknown recipes without blocking unrelated Make targets.
- `RCP-02`: Recipe health checks fail when recipe pods are unhealthy.
- `TEST-01`: The kpt validator and requirement check fail when their required inputs are missing.
- `TOOL-01`: `check-tools` provisions the pinned Bats version.
