#!/usr/bin/env bash
# Install the OSAC demo guest DNS (BIND) on the hypervisor.
#
# Replaces the dnsmasq listener at 127.0.0.54:53 with a named instance that
# serves full.guests.osac.test and full2.guests.osac.test authoritatively
# and accepts signed RFC 2136 updates from the OSAC AAP jobs.
#
# Run on the lab hypervisor as root, from a copy of this directory:
#
#   scp -r scripts/lab/dns root@<hypervisor>:/data/osac-demo/dns/setup
#   ssh root@<hypervisor> -- /data/osac-demo/dns/setup/setup-demo-named.sh
#
# Idempotent: re-running it leaves keys and live zone files alone. Use
# --verify-only to re-run only the verification.
#
# The libvirt network forwarders (<forwarder domain="<zone>"
# addr="127.0.0.54"/>) keep working unchanged: named takes over the same
# loopback listener. The AAP update path uses the hypervisor's management
# address: libvirt's bind-dynamic dnsmasq claims port 53 on every address
# added to the lab bridges, so named cannot listen there. AAP job pods
# reach the management address through the lab bridge gateway.

set -euo pipefail

# The hypervisor this may run on, and its management address. Both are
# placeholders: export HOST_EXPECTED and MGMT_IP with your lab's values.
HOST_EXPECTED="${HOST_EXPECTED:-demo-hv-01.example.com}"
DATA_ROOT="/data/osac-demo/dns"
# The SELinux policy confines named to the standard /etc/named tree; the
# /data parents are unlabeled_t and the service cannot traverse them.
KEY_DIR="/etc/named/osac-demo-keys"
LEGACY_KEY_DIR="$DATA_ROOT/keys"
CONF_DEST="/etc/named/osac-demo-named.conf"
ZONE_DIR="/var/named/dynamic"
BRIDGES_BIN="/usr/local/sbin/osac-demo-named-bridges.sh"
NAMED_USER="named"
# The hypervisor's management address, the one lab pods and the
# workstation reach. named listens here for the AAP jobs' RFC 2136 updates
# and readiness queries; it must already be assigned to an interface.
MGMT_IP="${MGMT_IP:-192.0.2.10}"

# lab -> "bridge zone key"; the bridge is only used for firewalld.
declare -A LABS=(
  [full]="br-full full.guests.osac.test osac-full-lab"
  [full2]="br-full2 full2.guests.osac.test osac-full2-lab"
)

BASE="$(cd "$(dirname "$0")" && pwd)"
VERIFY_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --verify-only) VERIFY_ONLY=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

fail() { echo "FAIL: $*" >&2; exit 1; }
note() { echo "== $*"; }

# --------------------------------------------------------------------------
# Preflight
# --------------------------------------------------------------------------
[[ $EUID -eq 0 ]] || fail "run as root"
[[ "$(hostname -f)" == "$HOST_EXPECTED" ]] || fail "wrong hypervisor: $(hostname -f)"
[[ -f "$BASE/named/osac-demo-named.conf" ]] || fail "run from the lab dns setup directory (missing named/osac-demo-named.conf)"

# A running system named would fight this instance for /run/named files.
if systemctl is-active --quiet named.service; then
  fail "the system named.service is running; this setup replaces the dnsmasq listener instead"
fi

# firewalld, if active, must allow DNS in the zones the lab bridges sit
# in: the AAP job pods reach the management listener through the bridge
# gateways, so the bridges are the ingress interfaces.
if systemctl is-active --quiet firewalld; then
  for lab in "${!LABS[@]}"; do
    read -r bridge zone key <<<"${LABS[$lab]}"
    zone_name="$(firewall-cmd --get-zone-of-interface="$bridge" 2>/dev/null || true)"
    if [[ -z "$zone_name" ]]; then
      zone_name="$(firewall-cmd --get-default-zone)"
    fi
    if ! firewall-cmd --zone="$zone_name" --query-service=dns >/dev/null 2>&1; then
      firewall-cmd --zone="$zone_name" --add-service=dns --permanent
      firewall-cmd --reload
      note "allowed dns service in firewalld zone $zone_name for $bridge"
    fi
  done
fi

# named can only bind addresses that exist on an interface.
ip -4 addr show | grep -q "inet ${MGMT_IP}" ||
  fail "the management address $MGMT_IP is not assigned on this hypervisor"

for lab in "${!LABS[@]}"; do
  read -r bridge zone key <<<"${LABS[$lab]}"
  [[ -f "$BASE/named/zones/$zone.db" ]] || fail "missing zone file $BASE/named/zones/$zone.db"
done

note "installing bind, bind-utils and SELinux tools if missing"
dnf install -y bind bind-utils policycoreutils-python-utils

# --------------------------------------------------------------------------
# Cutover: retire the dnsmasq listener and the per-lab publishers
# --------------------------------------------------------------------------
if [[ $VERIFY_ONLY -eq 0 ]]; then
  # The publishers restart osac-demo-dns.service whenever their records
  # change; leaving them enabled would fight named for 127.0.0.54:53.
  # The stop must not be guarded by list-unit-files: it does not match
  # template instances like @full.service and silently skips them, which
  # once let a running publisher restart dnsmasq and stop named.
  for unit in osac-demo-dns-publisher@full.service osac-demo-dns-publisher@full2.service; do
    systemctl stop "$unit" 2>/dev/null || true
    systemctl disable "$unit" 2>/dev/null || true
    if systemctl is-active --quiet "$unit"; then
      fail "$unit is still active after the stop; refusing to continue"
    fi
    note "stopped and disabled $unit"
  done
  if systemctl list-unit-files osac-demo-dns.service >/dev/null 2>&1; then
    systemctl stop osac-demo-dns.service || true
    systemctl disable osac-demo-dns.service || true
    if systemctl is-active --quiet osac-demo-dns.service; then
      fail "osac-demo-dns.service is still active after the stop; refusing to continue"
    fi
    note "stopped and disabled osac-demo-dns.service (dnsmasq at 127.0.0.54)"
  fi

  # The port check guards against the retired dnsmasq or anything else
  # claiming the address. On re-runs named itself legitimately holds it
  # and is restarted at the end, so only check when named is not active.
  if ! systemctl is-active --quiet osac-demo-named.service; then
    if ss -H -lun 'sport = :53' | grep -q '127\.0\.0\.54:'; then
      fail "something still listens on 127.0.0.54:53 (UDP); refusing to start named"
    fi
    if ss -H -ltn 'sport = :53' | grep -q '127\.0\.0\.54:'; then
      fail "something still listens on 127.0.0.54:53 (TCP); refusing to start named"
    fi
  fi
fi

# --------------------------------------------------------------------------
# TSIG keys: one per lab zone, generated once, kept under $KEY_DIR
# --------------------------------------------------------------------------
if [[ $VERIFY_ONLY -eq 0 ]]; then
  # named (SELinux-confined) must be able to traverse and read the keys.
  mkdir -p "$KEY_DIR"
  chown root:"$NAMED_USER" "$KEY_DIR"
  chmod 0750 "$KEY_DIR"
  # Keys generated before the path moved live under /data; move them once.
  if [[ -d "$LEGACY_KEY_DIR" ]]; then
    for legacy in "$LEGACY_KEY_DIR"/*.key; do
      [[ -e "$legacy" ]] || continue
      if [[ -f "$KEY_DIR/$(basename "$legacy")" ]]; then
        fail "both $KEY_DIR and $LEGACY_KEY_DIR hold $(basename "$legacy"); resolve by hand"
      fi
      mv "$legacy" "$KEY_DIR/"
      note "moved legacy key $(basename "$legacy") into $KEY_DIR"
    done
  fi
  for lab in "${!LABS[@]}"; do
    read -r bridge zone key <<<"${LABS[$lab]}"
    key_file="$KEY_DIR/$key.key"
    if [[ -f "$key_file" ]]; then
      note "keeping existing TSIG key $key_file"
    else
      note "generating TSIG key $key ($lab)"
      tsig-keygen -a hmac-sha256 "$key" > "$key_file"
    fi
    chown root:"$NAMED_USER" "$key_file"
    chmod 0640 "$key_file"
    grep -q "algorithm hmac-sha256" "$key_file" || fail "$key_file is not an hmac-sha256 key"
  done

  # named (SELinux-confined) must be able to read the key files.
  KEY_FCONTEXT="$KEY_DIR(/.*)?"
  semanage fcontext -a -t named_conf_t "$KEY_FCONTEXT" 2>/dev/null \
    || semanage fcontext -m -t named_conf_t "$KEY_FCONTEXT"
  restorecon -R "$KEY_DIR"
fi

# --------------------------------------------------------------------------
# Config, zone files, services
# --------------------------------------------------------------------------
if [[ $VERIFY_ONLY -eq 0 ]]; then
  note "installing named config"
  # The shipped config carries the documentation placeholder address;
  # render the one this run listens on so MGMT_IP and the config agree.
  sed "s|192\.0\.2\.10|$MGMT_IP|g" "$BASE/named/osac-demo-named.conf" > "$CONF_DEST"
  chown root:"$NAMED_USER" "$CONF_DEST"
  chmod 0644 "$CONF_DEST"
  restorecon "$CONF_DEST"

  mkdir -p "$ZONE_DIR"
  chown root:"$NAMED_USER" "$ZONE_DIR"
  chmod 0770 "$ZONE_DIR"
  for lab in "${!LABS[@]}"; do
    read -r bridge zone key <<<"${LABS[$lab]}"
    zone_file="$ZONE_DIR/$zone.db"
    if [[ -f "$zone_file.jnl" ]]; then
      note "keeping live dynamic zone $zone_file (journal present)"
    elif [[ -f "$zone_file" ]]; then
      note "keeping existing zone file $zone_file"
    else
      note "installing zone file $zone_file"
      install -m 0644 -o root -g "$NAMED_USER" "$BASE/named/zones/$zone.db" "$zone_file"
    fi
  done
  restorecon -R "$ZONE_DIR"

  note "installing bridge address helper"
  install -m 0755 "$BASE/osac-demo-named-bridges.sh" "$BRIDGES_BIN"

  note "installing systemd units"
  install -m 0644 "$BASE/osac-demo-named-bridges.service" /etc/systemd/system/osac-demo-named-bridges.service
  install -m 0644 "$BASE/osac-demo-named.service" /etc/systemd/system/osac-demo-named.service
  systemctl daemon-reload
  systemctl enable osac-demo-named-bridges.service osac-demo-named.service

  note "ensuring named's addresses (strict)"
  "$BRIDGES_BIN" --strict

  note "validating configuration"
  named-checkconf -z "$CONF_DEST"

  note "starting named"
  systemctl restart osac-demo-named.service
fi

systemctl is-active osac-demo-named.service || fail "osac-demo-named.service is not active"

# --------------------------------------------------------------------------
# Verification: nsupdate add, dig query, nsupdate delete
# --------------------------------------------------------------------------
note "verifying DNS service"

# Static health record through the forwarder path (libvirt forwarders).
for lab in "${!LABS[@]}"; do
  read -r bridge zone key <<<"${LABS[$lab]}"
  # The gateway of the lab network: full -> 192.168.160.1, full2 -> 192.168.162.1.
  case "$lab" in
    full) dns_check_ip=192.168.160.1 ;;
    full2) dns_check_ip=192.168.162.1 ;;
  esac
  answer=$(dig @127.0.0.54 "dns-check.$zone." A +short +time=2 +tries=1) ||
    fail "querying dns-check.$zone via 127.0.0.54 failed; is named listening on 127.0.0.54?"
  [[ "$answer" == "$dns_check_ip" ]] || fail "dns-check.$zone via 127.0.0.54: expected $dns_check_ip, got '$answer'"
  note "dns-check.$zone via 127.0.0.54 -> $dns_check_ip"
done

# Signed dynamic update through the management address the AAP job pods
# use. This is the exact server and path OSAC's RFC 2136 driver takes.
for lab in "${!LABS[@]}"; do
  read -r bridge zone key <<<"${LABS[$lab]}"
  key_file="$KEY_DIR/$key.key"
  # No leading underscore: nsupdate's check-names rejects it in owner names.
  test_name="setup-check.$zone"

  note "creating $test_name via nsupdate at $MGMT_IP"
  nsupdate -k "$key_file" -v <<EOF ||
server $MGMT_IP
zone $zone.
update add $test_name. 60 A 192.0.2.1
send
EOF
    fail "nsupdate could not add $test_name at $MGMT_IP (TSIG or reachability problem)"

  for resolver in 127.0.0.54 "$MGMT_IP"; do
    answer=$(dig @"$resolver" "$test_name." A +short +time=2 +tries=1) ||
      fail "querying $test_name via $resolver failed"
    [[ "$answer" == "192.0.2.1" ]] || fail "$test_name via $resolver: expected 192.0.2.1, got '$answer'"
    note "$test_name via $resolver -> $answer"
  done

  note "deleting $test_name via nsupdate at $MGMT_IP"
  nsupdate -k "$key_file" -v <<EOF ||
server $MGMT_IP
zone $zone.
update delete $test_name. A
send
EOF
    fail "nsupdate could not delete $test_name at $MGMT_IP"

  answer=$(dig @"$MGMT_IP" "$test_name." A +short +time=2 +tries=1) ||
    fail "querying $test_name via $MGMT_IP failed after the delete"
  [[ -z "$answer" ]] || fail "$test_name via $MGMT_IP still resolves: '$answer'"
  note "$test_name removed"
done

note "OK: named serves both zones, signed updates and both query paths work"
note "next: read each $KEY_DIR/*.key secret into the lab's rfc2136 secrets file (see the README)"
