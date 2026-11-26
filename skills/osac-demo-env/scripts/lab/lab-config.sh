# Configuration for osac-lab-reset. Sourced by the osac-lab-reset script
# after it has parsed the lab name. Every pin and machine-specific value
# lives here so the script body stays plain.
#
# Change the pins here, never in the script.
#
# Machine-specific values below default to a placeholder and can be
# overridden from the environment: LAB_CHECKOUT, AAP_LICENSE_FILE,
# LAB_DOMAIN and LAB_API_SERVER. Set them once in your shell profile (or
# export them per run) so no local path or lab hostname lives in this file.

# Installer source. The reset installs from an existing osac-7921-rfc2136
# worktree (PR #2526, RFC 2136 DNS backend, rebased onto the labs' install
# base 3dc9c381e). The worktree is shared with other work: the reset never
# creates, moves or resets it, it only verifies the pins and keeps the
# one-file schema patch applied. If the branch moves, preflight fails;
# update this pin deliberately.
LAB_CHECKOUT=${LAB_CHECKOUT:-$HOME/projects/osac-worktrees/osac-7921-rfc2136}
LAB_INSTALL_BRANCH=osac-7921-rfc2136-on-3dc9c381
LAB_INSTALL_HEAD=ae3d42a3fa998407acb1727107615a82c866101b

# One-key chart schema fix the rebased checkout still needs (its schema
# omits CI_GUEST_INGRESS_IP_RANGE). Applied idempotently to the worktree.
SCHEMA_PATCH=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dns/ci-ingress-range-schema-on-osac-7921.patch
SCHEMA_FILE=osac-installer/charts/osac/values.schema.json

# Accepted aap.configAsCode.projectGitBranch pins in
# environment/install/pinned-images.yaml: the labs' original install base,
# or the rebased RFC 2136 head once the branch is pushed to the fork. The
# reset never edits pinned-images.yaml; it refuses any other source.
PROJECT_PIN_OLD=3dc9c381ed7e69f4fcafa9389dcf9776548b6f27
PROJECT_PIN_RFC2136=ae3d42a3fa998407acb1727107615a82c866101b

# AAP subscription manifest, staged fresh by every install-osac run. Point
# AAP_LICENSE_FILE at the manifest you exported for your account.
AAP_LICENSE_FILE=${AAP_LICENSE_FILE:-$HOME/Downloads/osac-aap-manifest.zip}

# Namespaces, from the pinned installer invocation (NS=osac).
OSAC_NS=osac
INFRA_NS=osac-infra
KAFKA_NS=osac-kafka
KAFKA_NAME=osac-kafka
HOST_INVENTORY_NS=host-inventory

# The six virtual workers. The reset never touches their VMs on the
# hypervisor or their BareMetalHost definitions in host-inventory; it only
# waits for them to return to available.
WORKER_COUNT=6

# Waits, in seconds. The guest teardown allows 45 minutes because the
# operator retries deprovision jobs with a 30-minute backoff. The strip
# phase only waits for API deletions of finalizer-free objects.
WAIT_GUESTS=2700
WAIT_STRIP=300
WIPE_WAIT_STRIP=180
WIPE_WAIT_NAMESPACES=300
WIPE_WAIT_READY=600
WAIT_RELEASE=600
WAIT_AAP=1200
WAIT_NAMESPACE=900
WAIT_KAFKA=900
WAIT_KAFKA_PODS=600
WAIT_PVC=600
WAIT_METAL3=600

# Every osac.openshift.io kind the osac Helm release installs (operator and
# bare-metal-fulfillment CRDs). The drain phase deletes these in stages
# while the operator and AAP can still run their finalizers.
OSAC_CRD_KINDS="clusterorders computeinstances volumes baremetalinstances \
networkattachments externalipattachments externalips externalippools natgateways \
fabricdomains subnets securitygroups virtualnetworks networkclasses tenants"

# Kinds the ValidatingAdmissionPolicy osac-osac-managed-resources protects:
# it refuses kubectl deletes unless the caller is one of the Kubernetes
# controllers (RBAC blocks the operator and service accounts for deletes).
# The drain deletes these as the namespace-controller, the identity that
# would sweep them during namespace deletion, while the operator is still
# healthy to run their feedback finalizers. This list mirrors the policy's
# resourceRules; update it when the product policy changes.
PROTECTED_KINDS="networkattachments externalipattachments externalips externalippools \
natgateways fabricdomains subnets securitygroups virtualnetworks networkclasses"

# RFC 2136 DNS overlays and the gitignored TSIG secret file, per lab.
# The secrets file exists only after the hypervisor BIND setup runs; see
# scripts/lab/dns/README.md.
LAB_DNS_CLASS=dns.rfc2136.dns

# Lab table. Each lab is one SNO hub with its own kubeconfig, guest DNS
# zone and subnet. full3 and poc are deliberately not resettable.
case "$lab" in
  full)
    LAB_KUBECONFIG=$HOME/.kube/full.kubeconfig
    LAB_SUBNET=160
    LAB_ZONE=full.guests.osac.test
    LAB_DNS_OVERLAY=full-rfc2136.yaml
    LAB_DNS_SECRETS=full-rfc2136-secrets.local.yaml
    ;;
  full2)
    LAB_KUBECONFIG=$HOME/.kube/full2.kubeconfig
    LAB_SUBNET=162
    LAB_ZONE=full2.guests.osac.test
    LAB_DNS_OVERLAY=full2-rfc2136.yaml
    LAB_DNS_SECRETS=full2-rfc2136-secrets.local.yaml
    ;;
  *)
    printf 'lab-config.sh: unknown lab "%s"; use full or full2\n' "$lab" >&2
    exit 1
    ;;
esac

LAB_DNS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dns
# The hub's ingress domain and API endpoint. Preflight asserts the
# kubeconfig and the live ingress config match these, so set them to your
# lab's real values; the defaults are placeholders.
LAB_DOMAIN=${LAB_DOMAIN:-apps.$lab.example.com}
LAB_API_SERVER=${LAB_API_SERVER:-https://api.$lab.example.com:6443}
