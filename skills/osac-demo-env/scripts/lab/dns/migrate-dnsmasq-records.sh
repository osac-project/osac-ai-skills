#!/usr/bin/env bash
# Migrate existing dnsmasq guest records into the BIND lab zones.
#
# Reads /data/osac-demo/dns/<lab>.records.conf (written by the retired
# publish-guest-dns.py) and replays every record into the corresponding
# BIND zone with signed nsupdate, so clusters created before the cutover
# keep resolving. Run once on the hypervisor, after setup-demo-named.sh:
#
#   /data/osac-demo/dns/setup/migrate-dnsmasq-records.sh full
#   /data/osac-demo/dns/setup/migrate-dnsmasq-records.sh full2
#
# Only needed when cutting over with live clusters. A lab rebuilt after
# the cutover needs no migration: OSAC creates and deletes its own records.
#
# Skipped lines:
#   host-record=dns-check.<zone>,<gateway>   static in the zone file already
#
# Fail-loudly: any line that does not match the two known dnsmasq formats
# aborts the run before anything is sent.

set -euo pipefail

DATA_ROOT="/data/osac-demo/dns"
KEY_DIR="/etc/named/osac-demo-keys"

declare -A LABS=(
  [full]="full.guests.osac.test osac-full-lab 192.168.160.1"
  [full2]="full2.guests.osac.test osac-full2-lab 192.168.162.1"
)

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "run as root"
[[ $# -eq 1 ]] || fail "usage: $0 <full|full2>"
lab="$1"
[[ -n "${LABS[$lab]+set}" ]] || fail "unknown lab: $lab"
read -r zone key gateway <<<"${LABS[$lab]}"

records="$DATA_ROOT/$lab.records.conf"
[[ -f "$records" ]] || fail "no records file at $records"
key_file="$KEY_DIR/$key.key"
[[ -f "$key_file" ]] || fail "missing TSIG key $key_file (run setup-demo-named.sh first)"

# Parse first, send second: nothing is sent unless every line is understood.
declare -a ADD_CMDS=()
count=0
while IFS= read -r line; do
  case "$line" in
    "host-record=dns-check.$zone,$gateway") continue ;;
    host-record=*)
      # host-record=name1,name2,<ip>  (api and api-int share one address)
      names="${line#host-record=}"
      ip="${names##*,}"
      names="${names%,*}"
      [[ "$ip" =~ ^[0-9.]+$ ]] || fail "unparsed line: $line"
      IFS=',' read -ra parts <<<"$names"
      for name in "${parts[@]}"; do
        [[ "$name" == *".$zone" ]] || fail "record $name is outside $zone"
        ADD_CMDS+=("update add $name. 60 A $ip")
        count=$((count + 1))
      done
      ;;
    address=*)
      # address=/.apps.<order>.<zone>/<ip>  (dnsmasq wildcard form). The
      # leading dot means "this suffix and everything below it"; the BIND
      # equivalent is a wildcard record, *.apps.<...>. A literal leading
      # dot is an empty label and named rejects it.
      rest="${line#address=/}"
      name="${rest%%/*}"
      ip="${rest##*/}"
      [[ "${name#.}" == apps.*".$zone" && "$ip" =~ ^[0-9.]+$ ]] || fail "unparsed line: $line"
      ADD_CMDS+=("update add *.${name#.}. 60 A $ip")
      count=$((count + 1))
      ;;
    *)
      fail "unparsed line: $line"
      ;;
  esac
done <"$records"

echo "migrating $count records from $records into zone $zone"
if [[ $count -eq 0 ]]; then
  echo "nothing to migrate"
  exit 0
fi

printf '%s\n' "server 127.0.0.54" "zone $zone." "${ADD_CMDS[@]}" "send" \
  | nsupdate -k "$key_file" -v

for cmd in "${ADD_CMDS[@]}"; do
  name="$(echo "$cmd" | awk '{print $3}')"
  ip="$(echo "$cmd" | awk '{print $6}')"
  query="${name%.}"
  # Query below the wildcard: proves the record answers real lookups.
  case "$query" in
    \**) query="migration-probe.${query#\*.}" ;;
  esac
  answer="$(dig @127.0.0.54 "$query" A +short +time=2 +tries=1)"
  [[ "$answer" == "$ip" ]] || fail "$query: expected $ip, got '$answer'"
  echo "$query -> $ip"
done
echo "migration of $lab complete"
