#!/bin/bash
# Fast gNMIc attach: bounce gRPC and enable cgnat-tel within seconds.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Reuse helpers from post-deploy without running the full script.
KIND_NODE="${KIND_NODE:-nok-demo-control-plane}"
CLAB_NET="${CLAB_NET:-cgnat}"
KUBECTL="${KUBECTL:-kubectl}"
NS="${NS:-nok-cgnat}"
CGNAT_NAT=(172.21.30.11 172.21.30.12)
SROS_PASS="${SROS_PASS:-NokiaSros1!}"
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PubkeyAuthentication=no -o PreferredAuthentications=password -o NumberOfPasswordPrompts=1 -o IdentitiesOnly=yes)

log() { echo "--> CGNAT-attach: $*"; }

bounce_grpc() {
  local ip="$1"
  sshpass -p "$SROS_PASS" ssh "${SSH_OPTS[@]}" "admin@${ip}" -tt <<'EOF' >/dev/null 2>&1
configure global
system grpc admin-state disable
commit
system grpc admin-state enable
commit
exit all
exit
EOF
  log "bounced gRPC on $ip"
}

patch_gnmic() {
  local enabled="$1"
  shift
  local ndt
  for ndt in "$@"; do
    "$KUBECTL" patch networkdevicetarget "$ndt" -n "$NS" --type=merge \
      -p "{\"spec\":{\"gnmic\":{\"enabled\":${enabled}}}}" 2>/dev/null || true
  done
}

gnmic_has_nat_metric() {
  "$KUBECTL" exec -n "$NS" gnmic-cgnat-metrics-0 -- \
    wget -qO- 'http://127.0.0.1:9912/metrics' 2>/dev/null \
    | grep -q 'state_isa_nat_group_oper_state' || return 1
}

# Pod networking (like BNG) — hostNetwork shares KinD node netns, not host route.
"$KUBECTL" patch sts gnmic-cgnat-metrics -n "$NS" --type=merge \
  -p '{"spec":{"template":{"spec":{"hostNetwork":false,"dnsPolicy":"ClusterFirst"}}}}' \
  2>/dev/null || true

patch_gnmic false clab-sros-cgnat-agg clab-sros-cgnat-core
"$KUBECTL" patch pipeline cgnat-tel -n "$NS" --type=merge -p '{"spec":{"enabled":false}}' 2>/dev/null || true
patch_gnmic true clab-sros-cgnat-cgnat1 clab-sros-cgnat-cgnat2
sleep 2
for ip in "${CGNAT_NAT[@]}"; do bounce_grpc "$ip" || true; done
"$KUBECTL" patch pipeline cgnat-tel -n "$NS" --type=merge -p '{"spec":{"enabled":true}}'
log "gNMIc enabled — waiting for prom-output metric"
t=0
while [ "$t" -lt 120 ]; do
  if gnmic_has_nat_metric; then
    log "state_isa_nat_group_oper_state present on gnmic :9912"
    exit 0
  fi
  t=$((t + 5))
  sleep 5
done
log "WARNING: metric not seen after 120s"
"$KUBECTL" logs -n "$NS" gnmic-cgnat-metrics-0 --tail=15 || true
exit 1
