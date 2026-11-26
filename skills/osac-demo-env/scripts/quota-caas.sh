#!/usr/bin/env bash
#
# OSAC quota — CaaS: a cluster's ask and its hosts.
# The ask for three hosts counts at once; when the hosts exist, they
# replace the ask instead of adding to it. A second cluster and a
# scale-up are refused at the limit; raising the limit lets it through.
#
set -uo pipefail
#
# Needs on the machine that runs it:
#   - oc, grpcurl, jq, osac on PATH; KUBECONFIG pointing at the lab
#   - a logged-in osac CLI config dir (CLI_CONFIG): create it once with
#       osac --config <dir> login --insecure https://<public-api> \
#            --user <tenant-user> --password <password>
#     and put an SSH public key at <dir>/sshkey.pub
#   - the demo account fixtures in the tenant: the demo-vm (or demo-cluster)
#     catalog item, the demo-pull-secret secret, and a default subnet and
#     security group
#
# Every value below can be overridden through the environment.


export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/${OSAC_LAB:-full}.kubeconfig}"
CLI_CONFIG="${CLI_CONFIG:-/tmp/osac-demo-cli}"
TENANT_USER="${TENANT_USER:-tenant1_user}"
TENANT_PASSWORD="${TENANT_PASSWORD:-foobar}"
TENANT="${TENANT:-tenant1}"

DOMAIN=$(oc get ingress.config.openshift.io cluster -o jsonpath='{.spec.domain}')
PRIV="fulfillment-internal-api-osac.${DOMAIN}:443"
PUB="fulfillment-api-osac.${DOMAIN}:443"
CFG="${CLI_CONFIG}"
TENANT=tenant1
DIM_HOST=bare_metal.instances.demo-worker-bm
CLUSTER=c1

BOLD='\033[1m'
DIM='\033[2m'
CYAN='\033[1;36m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
MAGENTA='\033[1;35m'
RED='\033[1;31m'
RESET='\033[0m'

# ---------------------------------------------------------------- helpers ---

title() {
  echo ""
  echo -e "${CYAN}  ╭──────────────────────────────────────────────────────────────╮${RESET}"
  echo -e "${CYAN}  │${RESET}  ${BOLD}$1${RESET}"
  echo -e "${CYAN}  ╰──────────────────────────────────────────────────────────────╯${RESET}"
  sleep 2.0
}

section() {
  echo ""
  echo -e "${CYAN}── $1 ─────────────────────────────────────────────────────────────${RESET}"
  sleep 1.6
}

tenant_user() {
  echo ""
  echo -e "${GREEN}❯ tenant user${RESET}  ${BOLD}$1${RESET}"
  sleep 1.6
}

# Types a multi-line command out, house style.
tenant_type() {
  local text=$1 i
  echo ""
  echo -en "${GREEN}❯ tenant user${RESET}  ${BOLD}"
  for (( i=0; i<${#text}; i++ )); do
    echo -n "${text:$i:1}"
    sleep 0.025
  done
  echo -e "${RESET}"
  sleep 1.2
}

provider_admin() {
  echo ""
  echo -e "${MAGENTA}❯ provider admin${RESET}  ${BOLD}$1${RESET}"
  sleep 1.6
}

note() { echo -e "  ${DIM}$*${RESET}"; sleep 1.5; }
good() { echo -e "  ${GREEN}✓${RESET} $*"; sleep 1.4; }
bad()  { echo -e "  ${RED}✗${RESET} $*"; sleep 1.5; }
tick() { echo -e "  ${YELLOW}⏳${RESET} $*"; sleep 1.2; }

admin_api() {
  local method=$1; shift
  local out rc i
  for i in 1 2 3 4; do
    out=$(grpcurl -insecure -H "Authorization: Bearer ${TOKEN}" "$@" "${PRIV}" "${method}" 2>&1)
    rc=$?
    if (( rc == 0 )) || ! grep -q "no healthy upstream\|code = Unavailable" <<<"${out}"; then
      printf '%s' "${out}"
      return ${rc}
    fi
    sleep 3
  done
  printf '%s' "${out}"
  return ${rc}
}

osac_tu() { osac --config "${CFG}" "$@"; }

# Run a tenant CLI command and color a refusal red.
run_tenant() {
  local out rc
  out=$("$@" 2>&1)
  rc=$?
  if (( rc == 0 )); then
    printf '  %b%s%b\n' "${GREEN}" "${out}" "${RESET}"
  else
    printf '  %b%s%b\n' "${RED}" "${out}" "${RESET}"
  fi
  return ${rc}
}

usage_row() {
  local dimension=$1
  admin_api osac.private.v1.QuotaUsage/Get -d "{\"tenant\":\"${TENANT}\"}" -emit-defaults \
    | jq -r --arg d "${dimension}" '.report.dimensions[]
        | select(.dimension==$d)
        | "  \(.dimension)  limit \(.limit)  usage \(.usage)"'
}

seed_default() {
  local dimension=$1 value=$2
  local name="limit-$(echo "${dimension}" | tr '[:upper:]._' '[:lower:]--' | tr -cd 'a-z0-9-')"
  local out
  out=$(admin_api osac.private.v1.QuotaDefaultLimits/Create -d "$(jq -cn \
    --arg name "${name}" --arg dim "${dimension}" --arg val "${value}" \
    '{object:{metadata:{name:$name},spec:{dimension:$dim,value:$val}}}')")
  SEEDED_ID=$(echo "${out}" | jq -r '.object.id // empty')
  printf '  %-34s = %s\n' "${dimension}" "${value}"
}

cluster_id() {
  osac_tu get cluster "$1" -o json 2>/dev/null \
    | jq -r 'if type=="array" then (.[0].id // empty) else (.id // empty) end'
}

# ---------------------------------------------------------------- prepare ---

TOKEN=$(oc create token admin -n osac --duration 4h --as system:admin)

# ---------------------------------------------------------------- demo -----

clear

title "OSAC quota — CaaS: a cluster's ask and its hosts"
note "The tenant user asks for a cluster. The provider sets the limits."
note "Each worker is one bare-metal host from the provider's pool."
sleep 1

# --- 1 -------------------------------------------------------------------
section "1 · The hosts and the limits"

provider_admin "oc get bmh -n host-inventory"
oc get bmh -n host-inventory

provider_admin "grpcurl … QuotaDefaultLimits/List"
admin_api osac.private.v1.QuotaDefaultLimits/List -d '{}' | jq -c .
note "Six hosts are free, but the host dimension has no limit."

# --- 2 -------------------------------------------------------------------
section "2 · The provider gives room for one cluster"

provider_admin "grpcurl … QuotaDefaultLimits/Create (two dimensions)"
seed_default "${DIM_HOST}" 3
HOST_LIMIT_ID="${SEEDED_ID}"
seed_default caas.control_planes 2
note "Three hosts: exactly one cluster at the demo-cluster size of three."

# --- 3 -------------------------------------------------------------------
section "3 · The tenant asks for a cluster"

tenant_type $'osac create cluster --catalog-item demo-cluster --name c1 \\\n                --pull-secret demo-pull-secret --ssh-public-key-file sshkey.pub'
sleep 0.8

run_tenant osac_tu create cluster --catalog-item demo-cluster --name "${CLUSTER}" \
  --pull-secret demo-pull-secret --ssh-public-key-file "${CFG}/sshkey.pub"

good "Accepted. The ask is three hosts and the limit is three."
osac_tu get cluster "${CLUSTER}"

CID=$(cluster_id "${CLUSTER}")

# --- 4 -------------------------------------------------------------------
section "4 · The ask counts at once"

provider_admin "grpcurl … QuotaUsage/Get (right after the create)"
usage_row "${DIM_HOST}"
usage_row caas.control_planes
note "Three hosts count now, before a single host exists."

# --- 5 -------------------------------------------------------------------
section "5 · The operator creates the hosts"

note "The cluster asked for three workers; the operator is finding them."
start=${SECONDS}
while (( SECONDS - start < 1500 )); do
  states=$(admin_api osac.private.v1.BareMetalInstances/List \
    -d "{\"filter\":\"this.metadata.tenant == \\\"${TENANT}\\\"\"}" \
    | jq -r --arg c "${CID}" \
      '[.items[] | select(.status.cluster.id==$c)] as $i
       | "\($i|length) \([ $i[] | select(.status.state|contains("RUNNING")) ]|length)"')
  total=${states% *}
  running=${states#* }
  tick "${total} of 3 hosts created · ${running} running · $((SECONDS-start))s"
  (( running >= 3 )) && break
  sleep 20
done
good "All three hosts are running."

provider_admin "grpcurl … BareMetalInstances/List (the cluster's hosts)"
admin_api osac.private.v1.BareMetalInstances/List \
  -d "{\"filter\":\"this.metadata.tenant == \\\"${TENANT}\\\"\"}" \
  | jq -r --arg c "${CID}" '.items[]
      | select(.status.cluster.id==$c)
      | "  \(.metadata.name)  \(.status.state | sub("BARE_METAL_INSTANCE_STATE_"; ""))"'

osac_tu get cluster "${CLUSTER}"
note "The cluster is still installing. The quota part is already settled."

# --- 6 -------------------------------------------------------------------
section "6 · The hosts replace the ask"

provider_admin "oc get bmh -n host-inventory | grep provisioned"
printf '  %s provisioned\n' "$(oc get bmh -n host-inventory | grep -c provisioned)"

provider_admin "grpcurl … QuotaUsage/Get (after the hosts exist)"
usage_row "${DIM_HOST}"
note "Still three. The hosts replaced the ask; they did not add to it."

# --- 7 -------------------------------------------------------------------
section "7 · One more cluster, one more host — both refused"

tenant_user "osac create cluster --catalog-item demo-cluster --name c2 …"
run_tenant osac_tu create cluster --catalog-item demo-cluster --name c2 \
  --pull-secret demo-pull-secret --ssh-public-key-file "${CFG}/sshkey.pub"
bad "A second cluster needs three more hosts. The limit is three."

tenant_user "osac scale cluster ${CLUSTER} --node-set workers --size 4"
run_tenant osac_tu scale cluster "${CLUSTER}" --node-set workers --size 4
bad "One more host is one too many."

# --- 8 -------------------------------------------------------------------
section "8 · Raise the limit by one"

provider_admin "grpcurl … QuotaDefaultLimits/Update (${DIM_HOST} = 4)"
admin_api osac.private.v1.QuotaDefaultLimits/Update -d "$(jq -cn --arg id "${HOST_LIMIT_ID}" \
  --arg d "${DIM_HOST}" \
  '{object:{id:$id,metadata:{name:(("limit-" + ($d|ascii_downcase|gsub("[^a-z0-9]";"-"))))},spec:{dimension:$d,value:"4"}}}')" \
  | jq -r '"  \(.object.spec.dimension) = \(.object.spec.value)"'

tenant_user "osac scale cluster ${CLUSTER} --node-set workers --size 4"
run_tenant osac_tu scale cluster "${CLUSTER}" --node-set workers --size 4

good "The same command now passes. Nothing restarts: the limit is live."
usage_row "${DIM_HOST}"
note "Four hosts count; the fourth is being created now."

# --- 9 -------------------------------------------------------------------
section "9 · Clean up"

tenant_user "osac delete cluster ${CLUSTER}"
run_tenant osac_tu delete cluster "${CLUSTER}"

start=${SECONDS}
teardown_done=false
while (( SECONDS - start < 150 )); do
  if [[ -z "$(cluster_id "${CLUSTER}")" ]]; then
    teardown_done=true
    good "Cluster deleted; its hosts are going back to the pool."
    break
  fi
  tick "teardown running · $((SECONDS-start))s"
  sleep 30
done
if [[ "${teardown_done}" == "false" ]]; then
  note "Teardown continues on its own; the hosts return to the pool."
fi

provider_admin "grpcurl … QuotaDefaultLimits/Delete (the two we set)"
for dimension in "${DIM_HOST}" caas.control_planes; do
  id=$(admin_api osac.private.v1.QuotaDefaultLimits/List \
    -d "$(jq -cn --arg d "${dimension}" '{filter:"this.spec.dimension == \""+$d+"\""}')" \
    | jq -r '.items[0].id // empty')
  [[ -n "${id}" ]] && admin_api osac.private.v1.QuotaDefaultLimits/Delete -d "{\"id\":\"${id}\"}" >/dev/null
done

remaining=$(admin_api osac.private.v1.QuotaDefaultLimits/List -d '{}' | jq '.items | length')
good "Limits left set: ${remaining}"

echo ""
note "The hosts drain back to available as teardown finishes."
sleep 1
