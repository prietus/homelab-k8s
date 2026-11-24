#!/bin/bash
# Keeps the mac-node-exporter Endpoints pointing at this Mac's current LAN IP.
#
# Run by launchd (macos/us.priet.mac-endpoint-sync.plist) at login, whenever
# the network configuration changes, and every 5 minutes as a fallback.
# Does nothing when the Mac is away from home (no 192.168.1.x address) or the
# API server is unreachable, so it is quiet on the road.
#
# Talks to the API server with /usr/bin/curl, NOT kubectl, on purpose: macOS
# Local Network privacy blocks third-party binaries started by launchd from
# reaching LAN addresses (kubectl gets "connect: no route to host"), while
# Apple's own curl is exempt. From a terminal kubectl works only because it
# inherits the terminal app's permission.
#
# Install:
#   install -m 755 macos/mac-endpoint-sync.sh ~/bin/mac-endpoint-sync
#   cp macos/us.priet.mac-endpoint-sync.plist ~/Library/LaunchAgents/
#   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/us.priet.mac-endpoint-sync.plist
#
# Credentials, in ~/.kube/mac-endpoint-sync/ (mode 600):
#   token   — of the mac-endpoint-sync ServiceAccount
#             (macos/mac-endpoint-sync-rbac.yaml), which may only get/patch
#             this one Endpoints object;
#   ca.crt  — the cluster CA.
# Rebuild them from the Secret mac-endpoint-sync-token in namespace monitoring:
#   kubectl -n monitoring get secret mac-endpoint-sync-token -o jsonpath='{.data.token}'  | base64 -d > token
#   kubectl -n monitoring get secret mac-endpoint-sync-token -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt
#
# Note: `kubectl apply -f macos/mac-node-exporter.yaml` resets the IP to the
# one written in that file; this job puts it right again within 5 minutes.
set -uo pipefail

API=https://192.168.1.34:6443
CREDS="$HOME/.kube/mac-endpoint-sync"
URL="$API/api/v1/namespaces/monitoring/endpoints/mac-node-exporter"
LAN_PREFIX=192.168.1.

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

iface=$(/sbin/route -n get default 2>/dev/null | /usr/bin/awk '/interface:/{print $2}')
ip=${iface:+$(/usr/sbin/ipconfig getifaddr "$iface" 2>/dev/null)}
if [[ -z "${ip:-}" || "$ip" != "$LAN_PREFIX"* ]]; then
  exit 0   # not at home: nothing to do, and nothing worth logging
fi

api() {
  /usr/bin/curl -sS --max-time 8 --cacert "$CREDS/ca.crt" \
    -H "Authorization: Bearer $(<"$CREDS/token")" "$@"
}

body=$(api -f "$URL" 2>&1) || { log "API server unreachable, will retry ($body)"; exit 0; }
current=$(printf '%s' "$body" | /usr/bin/tr -d ' \n' | /usr/bin/grep -o '"addresses":\[{"ip":"[0-9.]*"' | /usr/bin/grep -o '[0-9.]*"$' | /usr/bin/tr -d '"')

if [[ "$current" == "$ip" ]]; then
  exit 0
fi

patch=$(printf '{"subsets":[{"addresses":[{"ip":"%s"}],"ports":[{"name":"metrics","port":9100,"protocol":"TCP"}]}]}' "$ip")
if out=$(api -f -X PATCH -H 'Content-Type: application/merge-patch+json' -d "$patch" "$URL" 2>&1); then
  log "endpoint updated: ${current:-none} -> $ip ($iface)"
else
  log "patch failed (endpoint ${current:-none}, Mac $ip): $out"
fi
