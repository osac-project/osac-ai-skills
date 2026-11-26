#!/usr/bin/env bash
#
# OSAC quota — VMaaS: the request path.
# A tenant asks for a VM at a limit of zero, the provider sets the limits,
# the same ask lands, and a tightened limit refuses the next one.
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

# Prompt lines always name the persona. Green = tenant user, magenta = provider admin.
tenant_user() {
  echo ""
  echo -e "${GREEN}❯ tenant user${RESET}  ${BOLD}$1${RESET}"
  sleep 1.6
}

provider_admin() {
  echo ""
  echo -e "${MAGENTA}❯ provider admin${RESET}  ${BOLD}$1${RESET}"
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

note() { echo -e "  ${DIM}$*${RESET}"; sleep 1.5; }
good() { echo -e "  ${GREEN}✓${RESET} $*"; sleep 1.4; }
bad()  { echo -e "  ${RED}✗${RESET} $*"; sleep 1.5; }
waiting() { echo -e "  ${YELLOW}⏳${RESET} $*"; sleep 1.4; }

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

tenant_api() {
  local method=$1; shift
  local out rc i
  for i in 1 2 3 4; do
    out=$(grpcurl -insecure -H "Authorization: Bearer ${TJWT}" "$@" "${PUB}" "${method}" 2>&1)
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

# The CLI the tenant user is logged in with.
osac_tu() { osac --config "${CFG}" "$@"; }

# ---------------------------------------------------------------- prepare ---

TOKEN=$(oc create token admin -n osac --duration 4h --as system:admin)
TJWT=$(curl -sk -X POST "https://keycloak-keycloak.${DOMAIN}/realms/osac/protocol/openid-connect/token" \
  -d grant_type=password -d client_id=osac-cli \
  -d username=${TENANT_USER} -d password=${TENANT_PASSWORD} -d scope=openid | jq -r .access_token)
[[ -n "${TJWT}" && "${TJWT}" != "null" ]] || { echo "no tenant token" >&2; exit 1; }

RHCOS="${DISK_IMAGE_ID:-$(grpcurl -insecure -H "Authorization: Bearer ${TOKEN}" \
  "${PRIV}" osac.private.v1.DiskImages/List -d '{}' \
  | jq -r '[.items[] | select(.metadata.tenant == "shared")][0].id')}"
SUBNET=$(osac_tu get subnet default-ipv4 -o json | jq -r .id)
SG=$(osac_tu get securitygroup default -o json | jq -r .id)

VM_JSON=$(jq -cn --arg n vm1 --arg img "${RHCOS}" --arg sn "${SUBNET}" --arg sg "${SG}" '{
  object: {
    metadata: {name: $n},
    spec: {
      template: {id: "osac.templates.ocp_virt_vm"},
      disk_image: {id: $img},
      instance_type: {name: "demo-standard-2"},
      boot_disk: {storage_tier: {name: "local"}, size_gib: "5"},
      network_attachments: [{subnet: {id: $sn}, security_groups: [{id: $sg}]}]
    }
  }
}')

# Show one refusal as a small table: code, message, and the QuotaFailure fields.
show_refusal() {
  local json=$1 code message reason dim added sources scope
  code=$(echo "${json}" | jq -r '.code')
  message=$(echo "${json}" | jq -r '.message')
  reason=$(echo "${json}" | jq -r '[.details[] | select(.reason)][0].reason // empty')
  dim=$(echo "${json}" | jq -r '[.details[] | select(.dimension)][0].dimension // empty')
  added=$(echo "${json}" | jq -r '[.details[] | select(.added)][0].added // empty')
  sources=$(echo "${json}" | jq -r '[.details[] | select(.dimension)][0].sources // [] | join(", ")')
  scope=$(echo "${json}" | jq -r '[.details[] | select(.scope)][0].scope // empty' \
    | sed 's/QUOTA_SCOPE_//' | tr 'A-Z' 'a-z')
  printf '  %-10s %s\n' "CODE" "FailedPrecondition (${code})"
  printf '  %-10s %s\n' "MESSAGE" "${message}"
  printf '  %-10s %s\n' "REASON" "${reason}"
  printf '  %-10s %s\n' "DIMENSION" "${dim}"
  printf '  %-10s %s\n' "ADDED" "${added}"
  printf '  %-10s %s\n' "SOURCES" "${sources}"
  printf '  %-10s %s\n' "SCOPE" "${scope}"
}

# Run a tenant CLI create and color the refusal red.
create_vm() {
  local name=$1 out rc
  out=$(osac_tu create computeinstance \
    --catalog-item demo-vm --name "${name}" \
    --instance-type demo-standard-2 --boot-disk-size 5 --boot-disk-storage-tier local \
    --set disk_image.id="${RHCOS}" \
    --network-attachment "subnet=${SUBNET},security-groups=${SG}" \
    --ssh-public-key "$(cat "${CFG}/sshkey.pub")" 2>&1)
  rc=$?
  if (( rc == 0 )); then
    printf '  %b%s%b\n' "${GREEN}" "${out}" "${RESET}"
  else
    printf '  %b%s%b\n' "${RED}" "${out}" "${RESET}"
  fi
  return ${rc}
}

# ---------------------------------------------------------------- demo -----

clear

title "OSAC quota — VMaaS: the request path"
note "The tenant user asks for a VM. The provider sets the limits."
note "Shorthand: \$RHCOS is the disk image, \$SUBNET and \$SG are the"
note "tenant's default subnet and security group."
sleep 1

# --- 1 -------------------------------------------------------------------
section "1 · No limits have been set"

provider_admin "grpcurl … QuotaDefaultLimits/List"
admin_api osac.private.v1.QuotaDefaultLimits/List -d '{}' | jq -c .
note "The provider has not set a single limit. Until it does, every limit is zero."

# --- 2 -------------------------------------------------------------------
section "2 · The tenant asks for a VM"

tenant_type $'osac create computeinstance --catalog-item demo-vm --name vm1 \\\n                --instance-type demo-standard-2 --boot-disk-size 5 \\\n                --boot-disk-storage-tier local --set disk_image.id=$RHCOS \\\n                --network-attachment subnet=$SUBNET,security-groups=$SG \\\n                --ssh-public-key "$(cat sshkey.pub)"'
sleep 0.8

create_vm vm1
bad "Refused. The ask is 2 vCPUs and 4 GiB. The memory limit is zero."
note "Nothing was created:"
osac_tu get computeinstance

note "The CLI prints one line. The API also returns the reason as data:"

tenant_user "grpcurl … osac.public.v1.ComputeInstances/Create"
show_refusal "$(tenant_api osac.public.v1.ComputeInstances/Create -format-error -d "${VM_JSON}" 2>&1)"

# --- 3 -------------------------------------------------------------------
section "3 · The provider sets the limits"

provider_admin "grpcurl … QuotaDefaultLimits/Create (five dimensions)"

seed_default() {
  local dimension=$1 value=$2
  local name="limit-$(echo "${dimension}" | tr '[:upper:]._' '[:lower:]--' | tr -cd 'a-z0-9-')"
  local out
  out=$(admin_api osac.private.v1.QuotaDefaultLimits/Create -d "$(jq -cn \
    --arg name "${name}" --arg dim "${dimension}" --arg val "${value}" \
    '{object:{metadata:{name:$name},spec:{dimension:$dim,value:$val}}}')")
  SEEDED_ID=$(echo "${out}" | jq -r '.object.id // empty')
  printf '  %-26s = %s\n' "${dimension}" "${value}"
}

seed_default compute.vcpus 10
VCPUS_ID="${SEEDED_ID}"
seed_default compute.memory_gib 20
seed_default storage.volumes 10
seed_default storage.local.gib 100
seed_default network.virtual_networks 10
sleep 0.3
note "Limits are per dimension and cover the whole tenant."

admin_api osac.private.v1.QuotaUsage/Get -d "{\"tenant\":\"${TENANT}\"}" -emit-defaults \
  | jq -r '.report.dimensions[]
      | select(.dimension=="compute.vcpus" or .dimension=="compute.memory_gib")
      | "  \(.dimension)  limit \(.limit)  usage \(.usage)"'
note "The room is there and nothing is used yet."

# --- 4 -------------------------------------------------------------------
section "4 · The same ask, now with room"

tenant_user "osac create computeinstance --catalog-item demo-vm --name vm1 …"

osac_tu create computeinstance \
  --catalog-item demo-vm --name vm1 \
  --instance-type demo-standard-2 --boot-disk-size 5 --boot-disk-storage-tier local \
  --set disk_image.id="${RHCOS}" \
  --network-attachment "subnet=${SUBNET},security-groups=${SG}" \
  --ssh-public-key "$(cat "${CFG}/sshkey.pub")" 2>&1

good "Created. Quota was checked inside the create, before any host work."
note "The VM is starting; that part is not the quota's business."

osac_tu get computeinstance
prev=""
for _ in 1 2 3; do
  state=$(osac_tu get computeinstance vm1 -o json 2>/dev/null | jq -r 'if type=="array" then .[0].status.state else .status.state end // "UNKNOWN"')
  if [[ "${state}" != "${prev}" ]]; then
    waiting "vm1 state: ${state}"
    prev="${state}"
  fi
  [[ "${state}" == *STARTING* ]] || break
  sleep 8
done

# --- 5 -------------------------------------------------------------------
section "5 · Tighten the limit to what is already used"

provider_admin "grpcurl … QuotaUsage/Get (vCPUs in use)"
admin_api osac.private.v1.QuotaUsage/Get -d "{\"tenant\":\"${TENANT}\"}" -emit-defaults \
  | jq -r '.report.dimensions[] | select(.dimension=="compute.vcpus") | "  compute.vcpus: limit \(.limit), usage \(.usage)"'

provider_admin "grpcurl … QuotaDefaultLimits/Update (compute.vcpus = 2)"
admin_api osac.private.v1.QuotaDefaultLimits/Update -d "$(jq -cn --arg id "${VCPUS_ID}" \
  '{object:{id:$id,metadata:{name:"limit-compute-vcpus"},spec:{dimension:"compute.vcpus",value:"2"}}}')" \
  | jq -r '"  compute.vcpus = \(.object.spec.value)"'

tenant_user "osac create computeinstance --catalog-item demo-vm --name vm2 …"
create_vm vm2

bad "Refused: the tenant holds 2 vCPUs, the limit is 2, the second VM adds 2."

# --- 6 -------------------------------------------------------------------
section "6 · The usage report"

provider_admin "grpcurl … QuotaUsage/Get (tenant1)"
{
  printf '  %-24s %6s %6s\n' DIMENSION LIMIT USAGE
  admin_api osac.private.v1.QuotaUsage/Get -d "{\"tenant\":\"${TENANT}\"}" -emit-defaults \
    | jq -r '.report.dimensions[]
        | select(.dimension | startswith("compute.") or startswith("storage."))
        | "\(.dimension)\t\(.limit)\t\(.usage)"' \
    | awk -F'\t' '{printf "  %-24s %6s %6s\n", $1, $2, $3}'
}
note "The same numbers the refusal named: limit 2, usage 2."

# --- 7 -------------------------------------------------------------------
section "7 · Clean up"

tenant_user "osac delete computeinstance vm1"
osac_tu delete computeinstance vm1 2>&1 || true
for _ in $(seq 1 24); do
  left=$(osac_tu get computeinstance vm1 -o json 2>/dev/null \
    | jq -r 'if type=="array" then (if length==0 then 0 else 1 end) else (if .id then 1 else 0 end) end')
  [[ "${left}" == "0" ]] && break
  sleep 5
done
good "VM deleted."

# Clear any KubeVirt object the delete left behind.
leftovers=$(oc get vm,vmi,datavolume,pvc -n "${TENANT}" -o name 2>/dev/null || true)
if [[ -n "${leftovers}" ]]; then
  note "clearing the leftover KubeVirt objects"
  oc delete vm,vmi -n "${TENANT}" --all --wait=false >/dev/null 2>&1 || true
  sleep 6
  for obj in $(oc get vm,vmi -n "${TENANT}" -o name 2>/dev/null || true); do
    oc patch "${obj}" -n "${TENANT}" --type merge -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1 || true
  done
  oc delete datavolume -n "${TENANT}" --all --wait=false >/dev/null 2>&1 || true
  for pvc in $(oc get pvc -n "${TENANT}" -o name 2>/dev/null | grep -E 'root-disk|prime-' || true); do
    oc delete "${pvc}" -n "${TENANT}" --wait=false >/dev/null 2>&1 || true
  done
fi

provider_admin "grpcurl … QuotaDefaultLimits/Delete (the five we set)"
for dimension in compute.vcpus compute.memory_gib storage.volumes storage.local.gib network.virtual_networks; do
  id=$(admin_api osac.private.v1.QuotaDefaultLimits/List \
    -d "$(jq -cn --arg d "${dimension}" '{filter:"this.spec.dimension == \""+$d+"\""}')" \
    | jq -r '.items[0].id // empty')
  [[ -n "${id}" ]] && admin_api osac.private.v1.QuotaDefaultLimits/Delete -d "{\"id\":\"${id}\"}" >/dev/null
done

remaining=$(admin_api osac.private.v1.QuotaDefaultLimits/List -d '{}' | jq '.items | length')
good "Limits left set: ${remaining}"

echo ""
note "Back where we started: no limits, no VM."
sleep 1
