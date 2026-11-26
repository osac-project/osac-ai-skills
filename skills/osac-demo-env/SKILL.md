---
name: osac-demo-env
description: Use when the user wants to reset, wipe, or prepare an OSAC demo lab for a demo, asks which labs or clusters exist and what state one is in, mentions osac-lab-demo-ready, osac-lab-wipe, or osac-lab-reset, asks what "demo ready" means or how long a lab reset takes, or needs to recover a lab after a demo run went wrong. Also use before or after running demo.sh on a lab.
metadata:
  version: "0.1.1"
---

# OSAC demo environment

The demo labs are cluster-tool SNO clones. Never assume which labs exist and
never hardcode lab names: discover the clusters, ask the user which one to
work on, detect that cluster's state, then recommend the command that brings
it to demo-ready. Work in that order every time.

The scripts this skill uses live in `scripts/lab/` inside this skill's
directory. The usual install symlinks the three `osac-lab-*` commands into
`~/.local/bin`. Two things still live in the demo environment checkout (the
repo that holds `demo.sh`): the `check-lab-ready.sh` gate and the
`FINDINGS.md` notes, because both drive `demo.sh`. `osac-lab-demo-ready`
also sources `demo.sh`, so it needs that checkout on its expected path
(two directories above `scripts/lab/`).

## Step 1: discover the clusters

```bash
cluster-tool list      # running clones: name, flavor, subnet
cluster-tool servers   # the baremetal servers hosting them
```

Show the user what you found and ask which cluster they want to work on. If
they named a lab up front, confirm it is in the list.

## Step 2: check the lab is resettable

The osac-lab commands only run on labs in the lab table in
`scripts/lab/lab-config.sh` (inside this skill). Each entry maps the lab
to its kubeconfig, guest DNS zone and subnet; some clones are deliberately
not resettable. If the chosen cluster has no entry, say so and stop: an entry
has to be added there first. A cluster-tool clone's kubeconfig is
`~/.kube/<name>.kubeconfig`.

## Step 3: detect the current state

Check top to bottom and stop at the first broken layer. All with the lab's
kubeconfig exported (`export KUBECONFIG=~/.kube/<name>.kubeconfig`):

1. **Cluster up** — `oc get nodes` returns Ready nodes.
2. **OSAC installed** — `helm list -A` shows the osac-deps, osac-infra and
   osac releases deployed, and the deployments in the osac namespace are
   ready.
3. **Workers free** — `oc get bmh -A` shows the hosts available with no
   consumers.
4. **Demo data** — `oc get tenants,vmis,vms -A` (and the scene-0 checks)
   tell you whether a demo has run: leftover tenants and workloads mean yes,
   a bare install means no.
5. **Starting position** — the demo environment checkout's gate script
   (`check-lab-ready.sh`) runs the full check: releases, workers, no
   leftovers, billing rules 0001, guest DNS, RFC 2136 reachability.

Report what you found, layer by layer, and what it means.

## Step 4: recommend the path

| Detected state | What to run | Measured time (Nov 22, 2026) |
|---|---|---|
| Cluster down or broken below OpenShift | cluster-tool rebuild: see the spawn-cluster skill (destroy, then boot from `quay.io/osac-project/cluster-flavors:sno-4-22` with `--pull-secret ~/pull-secret.json`), then install OSAC and run demo-ready | ~5-9 min to boot, then install |
| OSAC layer broken (failed releases, stuck pods) | `osac-lab-reset <lab> --yes` | 20-30 min clean; see failure mode below |
| OSAC healthy, demo data present | `osac-lab-demo-ready <lab> --yes` | 6.5-7 min |
| OSAC healthy, no demo data | `osac-lab-demo-ready <lab> --yes` (adds the fixtures) | 6.5-7 min |
| Clean install, no demo data | `osac-lab-wipe <lab> --yes` only if the user wants the bare state; otherwise demo-ready | 4.5-5 min |
| check-lab-ready already green | nothing; say so | - |

Always state the expected duration with the recommendation.

## The commands

All three live in `scripts/lab/` inside this skill (the usual install
symlinks them into `~/.local/bin`), share `lab-config.sh` and `lab-lib.sh`,
and take `<command> <lab> --yes`, then type the lab name when prompted (a
destructive-action guard; `--yes` alone does not skip it).

**demo-ready** produces the demo starting position: zero tenant data in
PostgreSQL and Kafka (install seeds kept), all OSAC pods ready, the workers
available with no consumers, no VMs/clusters/BMI-volumes, and the test
account in place: the demo tenant, its users linked to their Keycloak
identities, the admin carrying the `tenant-admin` realm role, catalog entries
and quotas set. The run ends with the scene-0 starting-position checks; exit
0 means the state is verified, not merely attempted.

**wipe** produces the same minus the test account. It scales the OSAC
deployments down (AAP and the console proxy stay up; the console proxy serves
an APIService Kubernetes needs for namespace deletion), strips the custom
resources, deletes tenant and guest namespaces, wipes the database rows via
generated SQL in one transaction (dress-rehearsed against the live schema in
preflight, rolled back if it fails), deletes the runtime Kafka topics
(`osac.events.*`, per-tenant heartbeat and dead-letter topics; chart-rendered
topics are kept), and scales back up. Keycloak is untouched. Replica counts
persist in `~/.local/state/osac-lab-wipe/<lab>.replicas` and survive failed
runs.

**reset** is the factory reset: stop and strip everything, helm uninstall,
delete kept CRDs, wipe infra PVCs, reinstall from the installer worktree
pinned in `lab-config.sh` (`LAB_CHECKOUT`) with the DNS overlay, TSIG secrets
and AAP license, then run the verify gate. Keycloak is fully reset (fresh
database, realm re-import). One time per lab under normal circumstances; the
reinstall never touches the workers. Requires the AAP license file (named in
`lab-config.sh`) and the lab's RFC 2136 secrets file
(`scripts/lab/dns/<lab>-rfc2136-secrets.local.yaml`, from the
`.example` file next to it) to exist.

## How to run them

Run in the background with a log file, then poll the log; never sit and wait
without watching:

```bash
echo <lab> | osac-lab-demo-ready <lab> --yes > /tmp/<lab>-demo-ready.log 2>&1
```

The `echo <lab> |` answers the lab-name prompt. Different labs can run in
parallel: separate clusters, and the reset does not touch the hypervisor's
named instance that serves the labs' zones.

Treat a run as done only when the log shows `EXIT: 0` and
`ready to start a demo` (demo-ready), `osac-infra is deployed` (wipe), or
`the lab matches the fresh-install starting position` (reset). An exit 0
without those lines is not success. Do not claim a lab is ready from the
absence of errors.

## Cluster-level operations

Anything below the OSAC layer — rebuilding a cluster, booting from the
golden snapshot, managing servers — belongs to the cluster-tool, documented
in the spawn-cluster skill; use that skill for it, not these commands. The
only supported snapshot is `quay.io/osac-project/cluster-flavors:sno-4-22`,
and booting requires a pull secret. The three osac-lab commands manage what
runs on the clusters; they never touch the clusters themselves.

## Known failure mode: the CSV race in osac-lab-reset

The installer's configure-kafka hook captures the amq-streams subscription's
`installedCSV` once and polls it with no timeout. When `make install-infra`
upgrades osac-deps and OLM replaces the CSV mid-run, the hook polls a CSV that
no longer exists, burns its 30-minute deadline, and the install fails with
`DeadlineExceeded` plus a cascade: no Kafka CR, no CA bundle, openbao and
postgres stuck. Full details in the demo environment checkout's
`FINDINGS.md` (finding 12).

Recovery, verified November 22, 2026: once the subscription settles on the
new CSV (`oc -n osac-kafka get subscription amq-streams` shows a Succeeded
installedCSV and the operator deployment is 1/1), re-run the reset's own
commands in order, each with `KUBECONFIG` exported:

1. `make -C "$LAB_CHECKOUT/osac-installer" install-infra PLATFORM=openshift PROFILE=full-ci NS=osac INFRA_VALUES_EXTRA='-f values/full-ci/quota-demo-infra.yaml'`
   (`$LAB_CHECKOUT` is the installer worktree pinned in `lab-config.sh`)
2. Wait for postgres Available and kafka Ready.
3. Apply the Provisioning resource with `disableVirtualMediaTLS: true`
   (see `restore_ci_virtual_media` in osac-lab-reset).
4. `make ... install-osac` with the AAP license, DNS overlay, DNS secrets and
   pinned-images values (see `phase_reinstall` in osac-lab-reset for the exact
   command).
5. Run the demo checkout's `check-lab-ready.sh <lab>` and the worker check;
   then `osac-lab-demo-ready <lab> --yes` if the goal is the demo state.

## Rules

- Never edit these scripts while a run is executing them; bash reads scripts
  incrementally and a mid-run edit corrupts the run.
- Never hand-edit database rows or Keycloak to "fix" a lab state; rerun the
  command that owns that state. The wipe's SQL is the only sanctioned row
  deletion and it is generated and rehearsed, not typed.
- Verify before claiming: check exit codes, the gate lines above, and for
  demo-ready also `deleting kafka topic` lines (their absence on a used lab
  means the Kafka wipe silently did nothing; see the demo checkout's
  FINDINGS.md history).
- Timings drift as the product changes; the numbers above were measured
  November 22, 2026. Re-measure before promising a number to the user.

## Examples

Two recorded quota demos, with the scripts that produced them:

- [scripts/quota-vmaas.sh](scripts/quota-vmaas.sh) — a tenant asks for a VM
  at a limit of zero, the provider sets the limits, the same ask lands, and
  a tightened limit refuses the next one.
  Recording: [assets/quota-vmaas.cast](assets/quota-vmaas.cast).
- [scripts/quota-caas.sh](scripts/quota-caas.sh) — a cluster's host ask
  counts before the hosts exist, the hosts replace it instead of doubling
  it, and a full tenant refuses a second cluster and a scale-up.
  Recording: [assets/quota-caas.cast](assets/quota-caas.cast).

Each script's header lists what it needs (a lab kubeconfig, a logged-in
`osac` CLI config dir, the demo catalog fixtures) and takes every
machine-specific value from the environment. Record your own with
`asciinema rec --command "bash scripts/quota-vmaas.sh" --idle-time-limit 3`.
