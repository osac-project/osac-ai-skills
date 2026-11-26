#!/usr/bin/env bash
# Manage the extra address the OSAC demo BIND DNS service needs on the
# hypervisor, and remove the bridge addresses it must not use.
#
# 127.0.0.54 on lo:
#   named binds only addresses that are assigned to an interface. The old
#   dnsmasq bound 127.0.0.54 directly; named's listen-on skips it unless
#   the address is on lo. The libvirt network forwarders point here, so
#   it must exist.
#
# The lab bridges (br-full, br-full2) deliberately get NO extra address:
# libvirt's bind-dynamic dnsmasq claims port 53 on every address that
# appears on its bridges, so a bridge address cannot serve named. The
# service listens on the hypervisor's management address instead. Any
# 192.168.x.2 address left from the earlier design is removed, which
# also releases the libvirt dnsmasq claim on it.
#
# The osac-demo-named-bridges.service unit runs this script at boot;
# setup-demo-named.sh runs it with --strict before starting named.
#
# Modes:
#   (default)  run all steps, warn about missing bridges
#   --strict   fail if a lab bridge is missing
#   --boot     same as default (kept for the unit's --boot invocation)

set -euo pipefail

MODE=default
for arg in "$@"; do
  case "$arg" in
    --strict) MODE=strict ;;
    --boot) MODE=boot ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

# Bridge -> obsolete DNS address from the earlier design.
declare -A OBSOLETE_BRIDGE_ADDRS=(
  [br-full]=192.168.160.2
  [br-full2]=192.168.162.2
)

LOOPBACK_ADDR=127.0.0.54

if ip -4 addr show dev lo | grep -q "inet ${LOOPBACK_ADDR}/"; then
  echo "$LOOPBACK_ADDR already on lo"
else
  ip addr add "${LOOPBACK_ADDR}/8" dev lo
  echo "added $LOOPBACK_ADDR/8 to lo"
fi

missing=0
for bridge in "${!OBSOLETE_BRIDGE_ADDRS[@]}"; do
  if ! ip link show dev "$bridge" >/dev/null 2>&1; then
    echo "WARN: bridge $bridge not found" >&2
    missing=$((missing + 1))
    continue
  fi
  addr="${OBSOLETE_BRIDGE_ADDRS[$bridge]}"
  if ip -4 addr show dev "$bridge" | grep -q "inet ${addr}/"; then
    ip addr del "${addr}/24" dev "$bridge"
    echo "removed obsolete DNS address $addr/24 from $bridge"
  else
    echo "$addr not on $bridge (already clean)"
  fi
done

if (( missing > 0 )) && [[ "$MODE" == "strict" ]]; then
  echo "FAIL: $missing lab bridge(s) missing in strict mode" >&2
  exit 1
fi
