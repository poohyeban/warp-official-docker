#!/bin/bash
set -Eeuo pipefail
umask 077

# Explicit commands remain available: docker run IMAGE warp-cli --help.
# To talk to the running daemon, use docker exec instead.
if [[ "${1:-serve}" != serve ]]; then exec "$@"; fi

state=/var/lib/cloudflare-warp
mkdir -p "$state" /run/dbus
dbus-uuidgen --ensure
pids=()
cleanup() {
  trap - EXIT TERM INT
  for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
  wait || true
}
trap cleanup EXIT
trap 'exit 0' TERM INT
dbus-daemon --system --nofork --nopidfile &
pids+=("$!")
warp-svc &
pids+=("$!")

ready=false
cli=(warp-cli)
if [[ "${WARP_ACCEPT_TOS:-false}" == true ]]; then cli+=(--accept-tos); fi
for ((i=0; i<60; i++)); do
  if "${cli[@]}" status >/dev/null 2>&1; then ready=true; break; fi
  kill -0 "${pids[1]}" 2>/dev/null || { echo 'warp-svc exited' >&2; exit 1; }
  sleep 1
done
[[ "$ready" == true ]] || { echo 'warp-svc not ready after 60 seconds' >&2; exit 1; }

# No automatic registration unless the operator explicitly opts in.
# A successful initialization marker prevents overwriting later manual changes.
if [[ ! -f "$state/.container-initialized" && "${WARP_AUTO_INIT:-false}" == true ]]; then
  [[ "${WARP_ACCEPT_TOS:-false}" == true ]] || { echo 'Set WARP_ACCEPT_TOS=true after reviewing Cloudflare terms' >&2; exit 1; }
  if ! warp-cli --accept-tos registration show >/dev/null 2>&1; then
    warp-cli --accept-tos registration new
  fi
  warp-cli --accept-tos mode proxy
  warp-cli --accept-tos proxy port 40000
  warp-cli --accept-tos connect
  touch "$state/.container-initialized"
fi

# WARP's loopback listener is not reachable through Docker port publishing.
# This is only a TCP relay, not another proxy implementation.
port="${WARP_PROXY_PORT:-40000}"
[[ "$port" =~ ^[0-9]+$ ]] && ((port > 0 && port < 65536)) || { echo 'Invalid WARP_PROXY_PORT' >&2; exit 1; }
socat TCP4-LISTEN:1080,bind=0.0.0.0,reuseaddr,fork "TCP4:127.0.0.1:$port" &
pids+=("$!")
echo 'WARP daemon running; manage with docker exec warp warp-cli ...'
# If the daemon, bus or relay dies, exit so Docker's restart policy can act.
set +e
wait -n "${pids[@]}"
exit 1
