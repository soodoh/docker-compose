#!/usr/bin/env bash
set -euo pipefail

target_ip=${1:?target Tailscale IP is required}
expected_fingerprint=${2:?expected SSH fingerprint is required}
accept_subnet_routes=${3:-false}

case "$accept_subnet_routes" in
  true)
    expected_routes=192.168.0.100/32,192.168.0.123/32
    ;;
  false)
    expected_routes=
    sudo tailscale set --accept-routes=false
    ;;
  *)
    echo "accept-subnet-routes must be true or false" >&2
    exit 64
    ;;
esac

sudo tailscale debug prefs | jq -e --argjson expected_routes "$accept_subnet_routes" '
  .CorpDNS == false and
  .RunSSH == false and
  .RouteAll == $expected_routes
'

route_v4_file=$(mktemp)
route_v6_file=$(mktemp)
keyscan_file=$(mktemp)
trap 'rm -f "$route_v4_file" "$route_v6_file" "$keyscan_file"' EXIT
ip -j -4 route show table 52 >"$route_v4_file"
ip -j -6 route show table 52 >"$route_v6_file"

EXPECTED_ROUTES="$expected_routes" \
ROUTE_V4_FILE="$route_v4_file" \
ROUTE_V6_FILE="$route_v6_file" \
python - <<'PY'
import ipaddress
import json
import os

expected = {
    (ipaddress.ip_network(route), "tailscale0")
    for route in os.environ["EXPECTED_ROUTES"].split(",")
    if route
}
tailnets = {
    4: ipaddress.ip_network("100.64.0.0/10"),
    6: ipaddress.ip_network("fd7a:115c:a1e0::/48"),
}
route_sources = (
    (os.environ["ROUTE_V4_FILE"], "0.0.0.0/0"),
    (os.environ["ROUTE_V6_FILE"], "::/0"),
)

scoped_routes = set()
for route_path, default_route in route_sources:
    with open(route_path, encoding="utf-8") as route_stream:
        routes = json.load(route_stream)

    for route in routes:
        destination = route.get("dst", default_route)
        network = ipaddress.ip_network(destination, strict=False)
        if not network.subnet_of(tailnets[network.version]):
            scoped_routes.add((network, route.get("dev")))

if scoped_routes != expected:
    raise SystemExit(
        f"unexpected non-tailnet routes in table 52: {sorted(map(str, scoped_routes))}"
    )

if expected:
    print("Approved subnet routes:")
    for network, device in sorted(expected, key=lambda item: str(item[0])):
        print(f"  {network} dev {device}")
else:
    print("No non-tailnet IPv4 or IPv6 routes accepted.")
PY

for attempt in {1..10}; do
  if sudo tailscale ping --until-direct=false --c=1 --timeout=5s "$target_ip"; then
    break
  fi
  if [[ $attempt -eq 10 ]]; then
    echo "Tailscale connectivity check failed" >&2
    exit 1
  fi
  sleep 2
done

for attempt in {1..10}; do
  if ssh-keyscan -T 5 -t ed25519 "$target_ip" >"$keyscan_file" 2>/dev/null &&
    [[ -s $keyscan_file ]]; then
    break
  fi
  if [[ $attempt -eq 10 ]]; then
    echo "SSH host-key scan failed" >&2
    exit 1
  fi
  sleep 2
done

actual_fingerprint=$(ssh-keygen -lf "$keyscan_file" -E sha256 | awk 'NR == 1 {print $2}')
if [[ $actual_fingerprint != "$expected_fingerprint" ]]; then
  echo "SSH host-key fingerprint mismatch" >&2
  echo "Expected: $expected_fingerprint" >&2
  echo "Actual:   $actual_fingerprint" >&2
  exit 1
fi

install -d -m 0700 "$HOME/.ssh"
install -m 0600 "$keyscan_file" "$HOME/.ssh/known_hosts"
echo "Verified Docker SSH host key: $actual_fingerprint"
