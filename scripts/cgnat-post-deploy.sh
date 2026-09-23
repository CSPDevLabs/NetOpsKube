#!/bin/bash
# Post-deploy for the CG-NAT lab: gRPC must accept TCP :57400 from the KinD
# pod network (same path as BNG 172.21.20.0/24), then gNMIc is bounced so
# zombie sessions are dropped. Does not touch the BNG lab.
set -euo pipefail

KIND_NODE="${KIND_NODE:-nok-demo-control-plane}"
CLAB_NET="${CLAB_NET:-cgnat}"
KUBECTL="${KUBECTL:-kubectl}"
NS="${NS:-nok-cgnat}"
CGNAT_NE=(
  clab-sros-cgnat-cgnat1
  clab-sros-cgnat-cgnat2
  clab-sros-cgnat-agg
  clab-sros-cgnat-core
)
CGNAT_MGMT=(
  172.21.30.11
  172.21.30.12
  172.21.30.13
  172.21.30.21
)
CGNAT_NAT=(
  172.21.30.11
  172.21.30.12
)
CGNAT_NDT=(
  clab-sros-cgnat-cgnat1
  clab-sros-cgnat-cgnat2
  clab-sros-cgnat-agg
  clab-sros-cgnat-core
)
SROS_PASS="${SROS_PASS:-NokiaSros1!}"
SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o PubkeyAuthentication=no
  -o PreferredAuthentications=password
  -o NumberOfPasswordPrompts=1
  -o IdentitiesOnly=yes
)

log() { echo "--> CGNAT: $*"; }

grpc_open() {
  python3 - "$1" <<'PY'
import socket, sys
s = socket.socket()
s.settimeout(2)
try:
    s.connect((sys.argv[1], 57400))
    sys.exit(0)
except Exception:
    sys.exit(1)
finally:
    s.close()
PY
}

kind_reach_cgnat() {
  if ! docker inspect "$KIND_NODE" >/dev/null 2>&1; then
    return 1
  fi
  # KinD node reachability != pod reachability; use a one-shot test pod.
  if "$KUBECTL" run grpc-reach-test -n "$NS" --rm -i --restart=Never \
    --image=busybox --timeout=20s -- sh -c 'nc -zv -w 3 172.21.30.11 57400' \
    >/dev/null 2>&1; then
    return 0
  fi
  docker exec "$KIND_NODE" python3 - <<'PY'
import socket
s = socket.socket()
s.settimeout(3)
try:
    s.connect(("172.21.30.11", 57400))
    raise SystemExit(0)
except Exception:
    raise SystemExit(1)
finally:
    s.close()
PY
}

# KinD must NOT get a connected /24 on 172.21.30.0/24: SR-SIM ignores SYNs
# sourced from 172.21.30.2 on the mgmt bridge. Reach routers via the host
# default route (172.30.0.1 → docker bridge SNAT), same as BNG 172.21.20.x.
detach_kind_cgnat_iface() {
  if ! docker inspect "$KIND_NODE" >/dev/null 2>&1; then
    return 0
  fi
  if docker inspect "$KIND_NODE" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' \
    | grep -qw "$CLAB_NET"; then
    log "disconnecting KinD from $CLAB_NET (use host route to mgmt instead)"
    docker network disconnect "$CLAB_NET" "$KIND_NODE" 2>/dev/null || true
  fi
  local pid kind_veth host_veth
  pid="$(docker inspect -f '{{.State.Pid}}' "$KIND_NODE")"
  kind_veth="kind-${CLAB_NET}0"
  host_veth="veth-kind-${CLAB_NET}"
  if nsenter -t "$pid" -n ip link show "$kind_veth" >/dev/null 2>&1; then
    nsenter -t "$pid" -n ip link del "$kind_veth" 2>/dev/null || true
    log "removed legacy veth $kind_veth from KinD"
  fi
  ip link del "$host_veth" 2>/dev/null || true
  # Legacy eth1 SNAT to 172.21.30.200 makes pod SYNs land on the mgmt /24;
  # SR-SIM sr-1s ignores those. Pods must hairpin via 172.30.0.2 like BNG.
  while docker exec "$KIND_NODE" iptables -t nat -L POSTROUTING -n --line-numbers 2>/dev/null \
    | grep -q '172.21.30.200'; do
    local snat_line
    snat_line="$(docker exec "$KIND_NODE" iptables -t nat -L POSTROUTING -n --line-numbers 2>/dev/null \
      | awk '/172\.21\.30\.200/ {print $1; exit}')"
    [ -n "$snat_line" ] || break
    docker exec "$KIND_NODE" iptables -t nat -D POSTROUTING "$snat_line" 2>/dev/null || break
    log "removed legacy KinD SNAT to 172.21.30.200 (pod path broken)"
  done
}

docker_bridge_name() {
  local net="$1" br
  br="$(docker network inspect "$net" -f '{{index .Options "com.docker.network.bridge.name"}}' 2>/dev/null || true)"
  if [ -n "$br" ]; then
    echo "$br"
    return 0
  fi
  br="$(docker network inspect "$net" -f '{{.Id}}' 2>/dev/null | cut -c1-12 || true)"
  if [ -n "$br" ]; then
    echo "br-${br}"
  fi
}

ensure_gnmic_pod_network() {
  # hostNetwork only shares the KinD node netns (172.30.0.2), not the host route
  # to 172.21.30.0/24. Use normal pod networking like BNG after SNAT fix.
  if ! "$KUBECTL" get sts gnmic-cgnat-metrics -n "$NS" >/dev/null 2>&1; then
    return 0
  fi
  local hn
  hn="$("$KUBECTL" get sts gnmic-cgnat-metrics -n "$NS" -o jsonpath='{.spec.template.spec.hostNetwork}' 2>/dev/null || true)"
  if [ "$hn" = "true" ]; then
    log "disabling hostNetwork on gnmic-cgnat-metrics (use pod path like BNG)"
    "$KUBECTL" patch sts gnmic-cgnat-metrics -n "$NS" --type=merge \
      -p '{"spec":{"template":{"spec":{"hostNetwork":false,"dnsPolicy":"ClusterFirst"}}}}' \
      2>/dev/null || true
    "$KUBECTL" delete pod -n "$NS" gnmic-cgnat-metrics-0 --wait=true 2>/dev/null || true
  fi
}

restart_gnmic_metrics_pod() {
  if "$KUBECTL" get pod -n "$NS" gnmic-cgnat-metrics-0 >/dev/null 2>&1; then
    log "restarting gnmic-cgnat-metrics-0 (clear stale gNMI sessions)"
    "$KUBECTL" delete pod -n "$NS" gnmic-cgnat-metrics-0 --wait=true 2>/dev/null || true
  fi
}

ensure_kind_cgnat_forward() {
  local kind_br cgnat_br
  kind_br="$(docker_bridge_name kind)"
  cgnat_br="$(docker_bridge_name "$CLAB_NET")"
  if [ -z "$kind_br" ] || [ -z "$cgnat_br" ]; then
    log "WARNING: could not resolve docker bridges for kind/$CLAB_NET (KinD pod path may fail)"
    return 0
  fi
  if ! iptables -C DOCKER-USER -i "$kind_br" -o "$cgnat_br" -j ACCEPT 2>/dev/null; then
    log "DOCKER-USER: allow $kind_br -> $cgnat_br (KinD pods to CG-NAT mgmt)"
    iptables -I DOCKER-USER -i "$kind_br" -o "$cgnat_br" -j ACCEPT -m comment --comment "cgnat-post-deploy"
  fi
  if ! iptables -C DOCKER-USER -i "$cgnat_br" -o "$kind_br" -j ACCEPT 2>/dev/null; then
    log "DOCKER-USER: allow $cgnat_br -> $kind_br (return path)"
    iptables -I DOCKER-USER -i "$cgnat_br" -o "$kind_br" -j ACCEPT -m comment --comment "cgnat-post-deploy"
  fi
}

ensure_esa_stub() {
  if ! docker inspect clab-sros-cgnat-esa-stub >/dev/null 2>&1; then
    log "WARNING: clab-sros-cgnat-esa-stub missing — ESA stays provisioned/Unknown"
    log "re-run: make redeploy-clab-cgnat from netopskube (BNG lab untouched)"
    return 1
  fi
  if ! docker exec clab-sros-cgnat-esa-stub ip link show eth1 >/dev/null 2>&1; then
    log "WARNING: esa-stub has no eth1-eth4 (host-ports not cabled in container)"
    log "re-run: make redeploy-clab-cgnat from netopskube to wire ESA links"
    return 1
  fi
  local i
  for i in 1 2 3 4; do
    docker exec clab-sros-cgnat-esa-stub ip link set "eth$i" up 2>/dev/null || true
  done
  log "esa-stub present with eth1-eth4 up (ESA host-ports cabled)"
}

sros_ssh() {
  local ip="$1"
  shift
  sshpass -p "$SROS_PASS" ssh "${SSH_OPTS[@]}" "admin@${ip}" "$@"
}

sros_show() {
  local ip="$1"
  local cmd="$2"
  sros_ssh "$ip" -tt <<EOF 2>/dev/null | tr -d '\r' | sed 's/\x1b\[[0-9;?]*[ -\/]*[@-~]//g'
${cmd}
exit
EOF
}

bounce_grpc() {
  local ip="$1"
  if ! sros_ssh "$ip" -tt <<'EOF' >/dev/null 2>&1
configure global
system grpc admin-state disable
commit
system grpc admin-state enable
commit
exit all
exit
EOF
  then
    log "could not bounce gRPC on $ip (router still booting?)"
    return 1
  fi
  log "bounced gRPC on $ip (cleared zombie sessions)"
}

bounce_grpc_all() {
  local ip
  for ip in "${CGNAT_MGMT[@]}"; do
    bounce_grpc "$ip" || true
  done
}

kick_esa() {
  local ip
  for ip in "${CGNAT_NAT[@]}"; do
    if ! sros_ssh "$ip" -tt <<'EOF' >/dev/null 2>&1
configure global
esa 1 admin-state disable
commit
esa 1 admin-state enable
commit
exit all
exit
EOF
    then
      log "could not kick ESA on $ip"
      continue
    fi
    log "kicked ESA admin-state on $ip"
  done
}

wait_grpc_host() {
  local ip t ok_nat=0 ok_all=0 max_wait="${1:-180}"
  log "waiting up to ${max_wait}s for gRPC :57400 on CG-NAT NEs (from host)"
  for ip in "${CGNAT_NAT[@]}"; do
    t=0
    while [ "$t" -lt "$max_wait" ]; do
      if grpc_open "$ip"; then
        log "$ip:57400 open"
        ok_nat=$((ok_nat + 1))
        ok_all=$((ok_all + 1))
        break
      fi
      t=$((t + 2))
      sleep 2
    done
  done
  [ "$ok_nat" -ge 2 ]
}

wait_grpc_kind() {
  local t=0
  log "waiting for KinD node to reach 172.21.30.11:57400 (pod path via host SNAT)"
  while [ "$t" -lt 120 ]; do
    if kind_reach_cgnat; then
      log "KinD can reach CG-NAT gRPC"
      return 0
    fi
    t=$((t + 2))
    sleep 2
  done
  log "KinD still cannot reach 172.21.30.11:57400 — check docker FORWARD/DOCKER-USER for $CLAB_NET"
  return 1
}

FLUX_CGNAT_KS=(cgnat-gnmic cgnat-network-device-targets)
FLUX_SUSPENDED=0

suspend_flux_cgnat() {
  if ! "$KUBECTL" get kustomization cgnat-gnmic -n flux-system >/dev/null 2>&1; then
    return 0
  fi
  log "suspending Flux CG-NAT kustomizations (patches otherwise revert in ~1m)"
  local ks
  for ks in "${FLUX_CGNAT_KS[@]}"; do
    if command -v flux >/dev/null 2>&1; then
      flux suspend kustomization "$ks" -n flux-system || true
    else
      "$KUBECTL" patch kustomization "$ks" -n flux-system --type=merge \
        -p '{"spec":{"suspend":true}}' 2>/dev/null || true
    fi
  done
  FLUX_SUSPENDED=1
}

patch_sdcio_enabled() {
  local enabled="$1" ndt
  if ! "$KUBECTL" get ns "$NS" >/dev/null 2>&1; then
    return 0
  fi
  for ndt in "${CGNAT_NDT[@]}"; do
    "$KUBECTL" patch networkdevicetarget "$ndt" -n "$NS" --type=merge \
      -p "{\"spec\":{\"sdcio\":{\"enabled\":${enabled}}}}" 2>/dev/null || true
  done
}

pause_sdcio_sync() {
  log "pausing SDCIO gNMI on CG-NAT targets (config-server reconnect storm)"
  patch_sdcio_enabled false
  local ndt val
  for ndt in "${CGNAT_NDT[@]}"; do
    val="$("$KUBECTL" get networkdevicetarget "$ndt" -n "$NS" -o jsonpath='{.spec.sdcio.enabled}' 2>/dev/null || true)"
    if [ "$val" != "false" ]; then
      log "WARNING: $ndt sdcio.enabled still $val (Flux may be unsuspended)"
    fi
  done
}

patch_gnmic_enabled() {
  local enabled="$1"
  shift
  local ndt
  for ndt in "$@"; do
    "$KUBECTL" patch networkdevicetarget "$ndt" -n "$NS" --type=merge \
      -p "{\"spec\":{\"gnmic\":{\"enabled\":${enabled}}}}" 2>/dev/null || true
  done
}

patch_pipelines_enabled() {
  local enabled="$1"
  shift
  local pipe
  for pipe in "$@"; do
    "$KUBECTL" patch pipeline "$pipe" -n "$NS" --type=merge \
      -p "{\"spec\":{\"enabled\":${enabled}}}" 2>/dev/null || true
  done
}

pause_gnmic_collectors() {
  # Keep NAT targets + cgnat-tel enabled so gNMIc retries continuously; K8s patch
  # propagation (~15s) misses the SR-SIM gRPC window if we enable on detect.
  log "pre-arming gNMIc (NAT targets + cgnat-tel on; restart pod for clean dialer)"
  patch_pipelines_enabled false cgnat-state cgnat-core-tel
  patch_gnmic_enabled false clab-sros-cgnat-agg clab-sros-cgnat-core
  patch_gnmic_enabled true clab-sros-cgnat-cgnat1 clab-sros-cgnat-cgnat2
  patch_pipelines_enabled true cgnat-tel
  restart_gnmic_metrics_pod
  sleep 8
}

gnmic_has_nat_metric() {
  timeout 10 "$KUBECTL" exec -n "$NS" gnmic-cgnat-metrics-0 -- \
    wget -qO- 'http://127.0.0.1:9912/metrics' 2>/dev/null \
    | grep -q 'state_isa_nat_group_oper_state' || return 1
}

wait_grpc_and_attach() {
  # SR-SIM opens :57400 briefly after bounce; enable gNMIc in the same poll
  # loop — any gap (wait_esa, re-disable patches, second bounce) misses the window.
  local ip t=0 max_wait="${1:-180}" ok
  log "waiting up to ${max_wait}s for gRPC :57400 and attaching gNMIc on first open"
  while [ "$t" -lt "$max_wait" ]; do
    ok=0
    for ip in "${CGNAT_NAT[@]}"; do
      if grpc_open "$ip"; then ok=$((ok + 1)); fi
    done
    if [ "$ok" -ge 2 ]; then
      log "both NAT routers open at t=${t}s — gNMIc pre-armed, waiting for subscribe"
      local mt=0
      while [ "$mt" -lt 90 ]; do
        if gnmic_has_nat_metric; then
          log "gNMIc prom-output has state_isa_nat_group_oper_state at t=${mt}s"
          return 0
        fi
        mt=$((mt + 3))
        sleep 3
      done
      log "metrics not seen after first attach — will retry on next gRPC open"
    fi
    if [ "$((t % 30))" -eq 0 ] && [ "$t" -gt 0 ]; then
      log "still waiting for gRPC window (${t}s)"
      for ip in "${CGNAT_NAT[@]}"; do bounce_grpc "$ip" || true; done
    fi
    t=$((t + 1))
    sleep 1
  done
  log "WARNING: no state_isa_nat_group_oper_state after ${max_wait}s attach attempts"
  return 1
}

resume_gnmic_staggered() {
  wait_grpc_and_attach 120 || true
}

wait_esa_active() {
  local ip t state nat_oper max_wait=120
  if ! docker exec clab-sros-cgnat-esa-stub ip link show eth1 >/dev/null 2>&1; then
    max_wait=30
    log "esa-stub links missing — skip long ESA wait (run make redeploy-clab-cgnat)"
  else
    log "waiting up to ${max_wait}s for ESA VM / nat-group on cgnat1/cgnat2"
  fi
  for ip in "${CGNAT_NAT[@]}"; do
    t=0
    state=""
    nat_oper=""
    while [ "$t" -lt "$max_wait" ]; do
      state="$(sros_show "$ip" "show esa 1" | awk '/Operational State/ {print $NF; exit}')"
      nat_oper="$(sros_show "$ip" "show isa nat-group 1" | awk '/Operational state/ {print $NF; exit}')"
      case "$state" in
        up|active|inService|in-service|provisioned)
          log "$ip ESA operational ($state), nat-group oper=${nat_oper:-unknown}"
          break
          ;;
      esac
      case "$nat_oper" in
        inService|in-service|transition|provisioned)
          log "$ip nat-group oper=$nat_oper (ESA=${state:-unknown})"
          break
          ;;
      esac
      if [ "$((t % 60))" -eq 0 ] && [ "$t" -gt 0 ]; then
        log "$ip still ESA=${state:-unknown} nat-group=${nat_oper:-unknown} (${t}s)"
      fi
      t=$((t + 10))
      sleep 10
    done
    if [ "$t" -ge "$max_wait" ]; then
      log "$ip ESA=${state:-unknown} nat-group=${nat_oper:-unknown} after ${max_wait}s (SR-SIM sr-1s often stays provisioned; gNMI may still export transition)"
    fi
  done
}

recover_ne_grpc() {
  # docker stop/start on NE containers breaks containerlab veth links to esa-stub
  # (eth1-eth4 vanish). Use clab --reconfigure to restart NEs with cabling intact.
  local clab_topo="${CLAB_TOPO:-}"
  if [ -z "$clab_topo" ]; then
    local base
    base="$(cd "$(dirname "$0")/.." && pwd)"
    clab_topo="${base}/nok-clabs/nok-cgnat/topo.yaml"
  fi
  if [ ! -f "$clab_topo" ]; then
    log "WARNING: cannot reconfigure CG-NAT lab ($clab_topo missing)"
    return 1
  fi
  local clab_bin base
  base="$(cd "$(dirname "$0")/.." && pwd)"
  clab_bin="${CLAB:-${base}/tools/clab}"
  if [ ! -x "$clab_bin" ]; then
    clab_bin="$(command -v clab || command -v containerlab || true)"
  fi
  log "gRPC still closed — clab deploy --reconfigure (preserves esa-stub links)"
  if [ -n "$clab_bin" ] && [ -x "$clab_bin" ]; then
    (cd "$(dirname "$clab_topo")" && "$clab_bin" deploy --reconfigure -t "$(basename "$clab_topo")") \
      || log "WARNING: clab reconfigure failed"
  else
    log "WARNING: clab not found — run: make redeploy-clab-cgnat"
  fi
  ensure_esa_stub || true
  log "NE containers reconfigured — attach loop will wait for gRPC window"
}

prom_has_nat_group_metric() {
  local out count
  out="$("$KUBECTL" exec -n "$NS" prometheus-nok-cgnat-0 -- \
    wget -qO- 'http://localhost:9090/api/v1/query?query=state_isa_nat_group_oper_state' 2>/dev/null || true)"
  count="$(printf '%s' "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('data',{}).get('result',[])))" 2>/dev/null || echo 0)"
  [ "${count:-0}" -gt 0 ]
}

verify_prometheus() {
  local t=0
  log "checking Prometheus for state_isa_nat_group_oper_state"
  while [ "$t" -lt 120 ]; do
    if prom_has_nat_group_metric; then
      log "Prometheus has state_isa_nat_group_oper_state samples"
      return 0
    fi
    t=$((t + 10))
    sleep 10
  done
  log "WARNING: no state_isa_nat_group_oper_state in Prometheus after 120s"
  return 1
}

rerun_hosts() {
  local c
  for c in clab-sros-cgnat-inet clab-sros-cgnat-cpe1 clab-sros-cgnat-cpe2 clab-sros-cgnat-cpe3 \
           clab-sros-cgnat-lan1 clab-sros-cgnat-lan2 clab-sros-cgnat-lan3; do
    if docker inspect "$c" >/dev/null 2>&1; then
      docker exec "$c" sh /startup.sh >/dev/null 2>&1 || true
    fi
  done
  log "re-ran linux host startup scripts (CPE/LAN after NAT is up)"
}

suspend_flux_cgnat
detach_kind_cgnat_iface
ensure_kind_cgnat_forward
ensure_gnmic_pod_network
ensure_esa_stub || true
pause_sdcio_sync
pause_gnmic_collectors
kick_esa || true
bounce_grpc_all
if ! wait_grpc_and_attach 180; then
  log "first attach window missed — clab reconfigure NEs and retry (boot opens gRPC)"
  recover_ne_grpc
  wait_grpc_and_attach 300 || true
fi
wait_esa_active || true
wait_grpc_kind || true
verify_prometheus || true
log "SDCIO gNMI left paused on CG-NAT targets (manifests: sdcio.enabled=false)"
if [ "$FLUX_SUSPENDED" = 1 ]; then
  log "Flux cgnat-gnmic + cgnat-network-device-targets still suspended — run: make push-cgnat-manifests && flux resume kustomization cgnat-gnmic cgnat-network-device-targets -n flux-system"
fi
rerun_hosts
log "post-deploy finished"
