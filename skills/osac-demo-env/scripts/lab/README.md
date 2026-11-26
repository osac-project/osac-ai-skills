# Lab tools

Three commands share this directory (`lab-config.sh` for pins,
`lab-lib.sh` for the strip helpers). All take `<lab> --yes` and ask you
to type the lab name before changing anything.

| Command | What it does | When to use it |
| --- | --- | --- |
| `osac-lab-demo-ready <lab>` | wipe + demo fixtures, ends with the demo's own scene-0 checks | between demo runs; a few minutes |
| `osac-lab-wipe <lab>` | fast demo-state reset: scale down, strip, wipe the databases in place, purge the Kafka event topics, drop rules beyond 0001, scale up, gate | any time no ClusterOrder exists |
| `osac-lab-reset <lab>` | factory reset: strip, uninstall, wipe the data volumes, reinstall from the pinned worktree | one-time migration to a new install (for example the RFC 2136 overlay); when the fast wipe is not enough |

`osac-lab-demo-ready` is the everyday command. The factory reset is the
one-time-per-change tool: it exercises the full install path (AAP
license import, project sync) and takes much longer.

## osac-lab-reset

Factory-reset an OSAC demo lab hub to its fresh-install state: no demo
resources, empty OSAC databases, billing rules `0001` only (loaded fresh),
no quota defaults, six available BMH workers, OSAC healthy.

    osac-lab-reset <lab> --yes

`<lab>` is `full` or `full2`. `--yes` is required, and the script then
asks you to type the lab name before it changes anything. The destruction
includes every guest cluster and all billing data, including approved
rules such as `0002`; the databases are emptied by removing their volumes
and reinstalling, never by deleting rows.

Billing data is durable state in the product's terms. This tool exists
because the demo's supported reset (`reset-state.sh`) cannot get past the
`quota_outbox` project-deletion bug (see `FINDINGS.md`), and because a
fresh-out-of-the-oven lab is the recording's starting position.

## Phases

Each phase checks the current state first and skips what is already done,
so a failed run can be re-run as-is. Any unexpected state stops the
script with the evidence commands to run next. Nothing is ever forced
except the strip phase's orphaned finalizers (see below).

| # | Phase | Checks first, then acts | Fails when |
| --- | --- | --- | --- |
| 1 | preflight | kubeconfig exists and points at `api.<lab>.example.com:6443` with domain `apps.<lab>.example.com`; installer worktree pins (below); AAP license readable and a valid ZIP; RFC 2136 overlays and the TSIG secret file present; `projectGitBranch` pin known | any pin moved or missing; the typed confirmation does not match |
| 2 | teardown guests | lists ClusterOrders in `osac`, hosted clusters anywhere, and `osac-order-*` namespaces | ClusterOrders do not finish deprovisioning in 45 min; leftover hosted clusters or guest namespaces do not delete; workers do not return to `available` |
| 3 | stop and strip | scales every non-AAP deployment in `osac` to 0 (the fulfillment service re-creates the builtin tenants and the networkclass while it runs, so it must stop too), deletes every demo custom resource (the networking kinds as the namespace-controller identity, which the `osac-osac-managed-resources` admission policy requires), then removes the now-orphaned finalizers so every deletion completes | any kind does not reach zero within its timeout (a controller may still be running and re-adding finalizers) |
| 4 | uninstall osac | `helm uninstall osac` (if the release exists), waits for the AAP CR to clear, deletes the `osac` namespace and every namespace labelled `osac.openshift.io/tenant-ref`, deletes the kept osac CRDs explicitly and waits for them to disappear | any demo CR remains after the strip (belt and braces); the AAP CR, the namespace or the CRDs do not clear |
| 5 | uninstall infra | `helm uninstall osac-infra`, deletes the `osac-infra` and `keycloak` namespaces, deletes the Kafka CR/node pool/topics and the broker PVCs in `osac-kafka` | a namespace does not clear; Kafka resources or pods do not stop; the amq-streams operator is not healthy; PVCs do not release |
| 6 | reinstall | runs `make install-infra` then `make install-osac` from the pinned worktree (skipped when the release is already deployed and healthy and the instance-group ConfigMap matches the overlay), restores the CI virtual-media Ironic setting, re-checks the six workers | either make fails; the readback of `cluster-fulfillment-ig` does not match the overlay; workers are not available |
| 7 | verify | runs `environment/install/check-lab-ready.sh <lab>`, re-checks the six workers (available, labelled `default`, no consumer, no error) and the Ironic virtual-media setting | any readiness check fails |

Progress prints carry the lab name prefix, like the other lab scripts.

## What is intentionally not reset

- The SNO hub itself (nodes, OpenShift, LVMS, CNV, MCE, MetalLB, the
  `osac-deps` operators including the amq-streams and AAP operators).
- The six worker VMs on the hypervisor and their `BareMetalHost`
  definitions in `host-inventory`. The reset only waits for them to return
  to `available`; worker re-registration stays with
  `environment/install/finish-lab-install.sh`.
- The hypervisor as a whole: the reset never touches it. Only the verify
  phase reads its state, through `check-lab-ready.sh`.
- The guest DNS service (named) and its TSIG keys on the hypervisor.

## The databases, and how they are emptied

| Data | Where | Removed by |
| --- | --- | --- |
| Fulfillment and metering databases | PVC `postgres-data` in `osac-infra` | `helm uninstall osac-infra` (Helm-tracked PVC) |
| Keycloak users | PVC `keycloak-database` in `keycloak` | `helm uninstall osac-infra` (Helm-tracked, namespace and all) |
| OpenBao secrets | PVC `openbao-data` in `osac-infra` | `helm uninstall osac-infra` (Helm-tracked PVC) |
| AAP data (jobs, project sync) | PVC `postgres-15-osac-aap-postgres-15-0` in `osac` | deletion of the `osac` namespace in phase 4 |
| Kafka topics and metering events | broker PVCs `data-osac-kafka-dual-role-0/1/2` in `osac-kafka` | phase 5 deletes the Kafka CR, node pool and topics (applied by the infra hook job, not Helm-tracked, `deleteClaim: false`) and then the PVCs |

No table is ever truncated, no row, finalizer or ConfigMap is deleted
directly. Rules `0001` come back the way a fresh install loads them.

## Install source and pins

The reinstall installs from the existing worktree
`~/projects/osac-worktrees/osac-7921-rfc2136` (PR #2526, the
RFC 2136 DNS backend, rebased onto the labs' install base `3dc9c381e`).
The reset never creates, moves or resets that worktree. Preflight and the
reinstall phase verify, and `lab-config.sh` pins:

- the branch `osac-7921-rfc2136-on-3dc9c381` and head
  `ae3d42a3fa998407acb1727107615a82c866101b`; if either moved, the reset
  fails until the pin is updated deliberately;
- exactly one uncommitted change is allowed in the worktree: the schema
  patch on `osac-installer/charts/osac/values.schema.json`. The rebased
  chart schema still rejects `CI_GUEST_INGRESS_IP_RANGE`, so the reset
  keeps `dns/ci-ingress-range-schema-on-osac-7921.patch` applied
  idempotently (key present in the schema = done; otherwise `git apply`;
  an apply that fails because the patch is already applied is success);
- `aap.configAsCode.projectGitBranch` in
  `environment/install/pinned-images.yaml` must be either the original
  `3dc9c381e...` or the rebased head `ae3d42a3f...`. The reset prints
  which one it found and never edits the file. Until the branch is pushed
  to the fork and the pin moves to `ae3d42a3f...`, the AAP project still
  syncs the old commit, so the `dns.rfc2136` driver is not in the synced
  project yet; the reset itself does not depend on it.

All machine-specific values (paths, pins, waits, the lab table) live in
`lab-config.sh` next to this README. The values that name a machine are
placeholders and come from the environment, so nothing lab-specific is
committed:

| Variable | Used by | Meaning |
| --- | --- | --- |
| `LAB_CHECKOUT` | reset | installer worktree to reinstall from |
| `AAP_LICENSE_FILE` | reset | AAP subscription manifest (ZIP) |
| `LAB_DOMAIN` | reset | hub ingress domain, e.g. `apps.<lab>.example.com` |
| `LAB_API_SERVER` | reset | hub API endpoint, e.g. `https://api.<lab>.example.com:6443` |
| `HOST_EXPECTED`, `MGMT_IP` | `dns/setup-demo-named.sh` | hypervisor FQDN and management address |

Preflight compares the kubeconfig and the live ingress domain against
`LAB_DOMAIN`/`LAB_API_SERVER`, so set them to your lab's real values
before the first reset.

## DNS overlays

The reinstall uses the RFC 2136 overlays from `dns/` next to this README:

    INSTANCE_VALUES_EXTRA="-f values/full-ci/quota-demo.yaml \
      -f $LAB_DNS_DIR/<lab>-rfc2136.yaml \
      -f $LAB_DNS_DIR/<lab>-rfc2136-secrets.local.yaml \
      -f <demo>/environment/install/pinned-images.yaml"

The secrets file is gitignored and carries the TSIG secret; it exists
only after the hypervisor BIND setup runs. Preflight fails with a pointer
to `dns/README.md` when it is missing. The reset never generates or fakes
the secret.

## Install commands

The same commands as the runbook and `finish-lab-install.sh`, run with
`make -C` against the pinned worktree:

    make install-infra PLATFORM=openshift PROFILE=full-ci NS=osac \
      INFRA_VALUES_EXTRA='-f values/full-ci/quota-demo-infra.yaml'
    make install-osac PLATFORM=openshift PROFILE=full-ci NS=osac \
      AAP_LICENSE_FILE=... \
      INFRA_VALUES_EXTRA='-f values/full-ci/quota-demo-infra.yaml' \
      INSTANCE_VALUES_EXTRA="... (see above)"

After `install-infra`, the reset re-applies the Provisioning resource
with `disableVirtualMediaTLS: true`: the chart's metal3 hook re-applies
it without that field on every install, and the pinned CI worker setup
needs it so Ironic accepts the hypervisor's virtual-media server over plain
HTTP
(the full2 rebuild had to restore this by hand). The setting is asserted
again in verify.

## Why phase 2 runs the real guest teardown, and phase 3 does not

The guest clusters are the one resource whose teardown must go through
OSAC while the stack is up: the ClusterOrder deprovision job releases
the six BMH workers. Brute-forcing a ClusterOrder finalizer would orphan
the workers in a provisioned state, and recovering them means manual
Metal3 surgery.

Everything else is stripped bluntly after the operators are stopped:

- The kubevirt VM objects live in the tenant namespaces; `virt-controller`
  (part of CNV, independent of OSAC) finalizes them when those namespaces
  are deleted in phase 4.
- The volume claims die with their namespaces; LVMS releases the storage.
- The networking custom resources have no external side effects on this
  profile (provisioning is disabled).
- Tenants, quota and metering are database rows, removed by the volume
  wipe in phase 5.
- The networkclass is not recreated once the operator is stopped (with
  the operator running it is reconciled back from its registration
  ConfigMap within minutes, observed live).

Removing finalizers is legitimate here because the operators are
stopped: the finalizers are orphaned, not masking live behavior. This is
the standard operator-uninstall practice. The demo remains the tool that
verifies the product's own teardown paths.

### Protected kinds and the controller identities

The ValidatingAdmissionPolicy `osac-osac-managed-resources` refuses
kubectl deletes and updates for the networking kinds (the list in
`lab-config.sh`), and RBAC separately denies the delete verb to the
operator and service accounts. Two identities matter:

- **Deletes** go out as `system:serviceaccount:kube-system:namespace-controller`
  (via `oc --as`): the identity namespace deletion itself would use, and
  one of the few that pass both the policy and RBAC.
- **Finalizer strips** (a patch) go out as
  `system:serviceaccount:osac:osac-operator`: it is whitelisted by the
  policy and holds the patch verb on those kinds.

Recovery when a drain gets stuck: the failure names the kind and the
evidence commands. If the osac release is missing or broken, reinstall it
(phase 6 does this on a stripped lab) and run the reset again.

## What the first live run should watch

- The AAP license import returns HTTP 503 for the first attempts on a
  fresh AAP; the bootstrap job retries and gets past it (seen on both
  fresh installs). `install-osac` waits, so this is normal slowness, not
  a failure.
- The AAP project sync must reach the pinned commit. With the
  `3dc9c381e` project pin and the RFC 2136 overlay installed, guest DNS
  record management will not work until the pin moves to `ae3d42a3f`;
  the reset prints the pin it found.
- Tenant deletion (drain stage 6) runs storage teardown AAP jobs per
  tenant; the storage controller refuses to drop its finalizer when
  storage tiers fail to resolve. A stuck tenant is a loud failure by
  design.
- Worker release after ClusterOrder deletion took minutes on the labs;
  the wait prints per-worker state every 15 seconds.

## Open questions

1. **`check-lab-ready.sh` and `demo.sh` accept both DNS classes.**
   The gate now reads `DNS_CLASS` from `cluster-fulfillment-ig`:
   `dns.noop.dns` labs require the dnsmasq listener and the lab's
   publisher running; `dns.rfc2136.dns` labs require `DNS_RFC2136_SERVER`
   to be the lab bridge address, `osac-demo-named.service` running on
   the hypervisor, and the bridge server answering TCP 53 from a hub pod. Any
   other class fails. `demo.sh`'s `show_starting_position` accepts both classes
   the same way.
2. **AAP on reinstall**: the AAP operator redeploys a fresh instance and
   the bootstrap job re-imports the license from the manifest on every
   install (the license is staged from `AAP_LICENSE_FILE` each time), but
   no reinstall of AAP over a wiped namespace has been observed end to
   end on these labs yet.
3. **Phase 2 repairs only order-driven worker holds.** Workers held by
   leftover `BareMetalInstance` bindings with no ClusterOrder are
   released by the drain phase and caught before the reinstall; a
   binding that survives the drain stops the reinstall loudly.
4. **Stale guest DNS records**: after the RFC 2136 cutover, OSAC removes
   records on normal teardown. If a guest was torn down by this reset's
   CR deletion while its record removal job failed, a stale
   `api.<order>.<zone>` record could remain in the BIND zone. Check with
   `dig @127.0.0.54` on the hypervisor if a later cluster order gets a name
   collision.

## Symlink

When this is trusted after the first live runs, expose it on PATH:

    ln -s <skill>/scripts/lab/osac-lab-reset ~/.local/bin/osac-lab-reset

Do not create the symlink yet.
