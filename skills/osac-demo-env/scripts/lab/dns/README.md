# RFC 2136 DNS for the demo labs

Design for letting OSAC manage the guest DNS records itself (PR #2526,
OSAC-7921) on the two demo labs, replacing the out-of-band
`publish-guest-dns.py` watcher. Everything here is local and unapplied:
no branch was pushed, no hypervisor service was touched.

## What exists where

| Thing | Where |
| --- | --- |
| Rebased branch `osac-7921-rfc2136-on-3dc9c381` | worktree `~/projects/osac-worktrees/osac-7921-rfc2136`, head `ae3d42a3f` |
| BIND configs, setup script, migration script | this directory |
| Helm overlays `full-rfc2136.yaml`, `full2-rfc2136.yaml` | this directory |
| Schema patch for the rebased checkout | `ci-ingress-range-schema-on-osac-7921.patch` (this directory) |

## The rebased branch

`osac-7921-rfc2136-on-3dc9c381` is PR #2526's six `OSAC-7921` commits
rebased onto `3dc9c381e` (the commit both labs were installed from, fetched
from the fork `omer-vishlitzky/osac`). The PR's own base (`3f076cadb`) is 37
upstream commits ahead of `3dc9c381`, which caused conflicts only in
`osac-aap/AGENTS.md` and `osac-installer/AGENTS.md` (commit 1, and again in
commit 2 which reverts those additions). Resolution rule: keep the
`3dc9c381` document structure, drop text that intermediate upstream commits
added. The PR's net AGENTS.md change is zero, so both files ended up byte-
identical to `3dc9c381`. Every other PR-touched file is byte-identical to
the PR head `061e39b9d` (verified with `git diff pr-2526-raw HEAD` over the
PR's file list: empty).

Commits, in order (new hashes after rebase):

| Rebased | Original | Subject |
| --- | --- | --- |
| `54cffc0d6` | `1376aa82f` | add RFC 2136 DNS backend for CaaS cluster endpoints |
| `0b261e323` | `2ed6c9590` | address review of the RFC 2136 DNS backend |
| `211d1c497` | `76ea8be6d` | drop weak TSIG algorithms and neutral TTL lookup message |
| `1bb6027bb` | `07460ffb2` | tighten the RFC 2136 installer schema |
| `4735defa6` | `3114c0fad` | validate IPv6 fully and document unsigned readiness queries |
| `ae3d42a3f` | `061e39b9d` | verify the wildcard record directly |

Offline validation done on the rebased tree:

- `helm unittest -f 'tests/dns_rfc2136*_test.yaml' charts/osac` after
  `make helm-deps`: 30/30 pass.
- `values.schema.json` parses; all new/changed YAML parses.
- Both overlays below render through the chart with schema validation
  enabled (using the profile, quota-demo and pins files, plus this
  directory's schema patch); the render diff against the current
  `full-dns.yaml`/`full2-dns.yaml` renders contains only the DNS-class
  changes.
- `named-checkzone` accepts both initial zone files.
- The PR's pytest suite (`tests/unit/test_dns_rfc2136.py`) could not run
  offline: its dev dependencies need a network build. Run it on the
  workstation with network before the live application.

Reproduce the `full` overlay render (from the rebased checkout's
`osac-installer/`, chart dependencies built with `make helm-deps`, schema
patch applied with
`git apply <skill>/scripts/lab/dns/ci-ingress-range-schema-on-osac-7921.patch`):

```bash
helm template osac charts/osac -n osac \
  -f values/full-ci/instance.yaml \
  -f values/full-ci/quota-demo.yaml \
  -f <skill>/scripts/lab/dns/full-rfc2136.yaml \
  -f <skill>/scripts/lab/dns/full-rfc2136-secrets.local.yaml.example \
  -f $demo/environment/install/pinned-images.yaml \
  --set service.externalHostname=fulfillment-api-osac.apps.full.example.com \
  --set service.internalHostname=fulfillment-internal-api-osac.apps.full.example.com \
  --set global.clusterDomain=apps.full.example.com \
  --set ui.auth.oidcIssuerURL=https://keycloak-keycloak.apps.full.example.com/realms/osac \
  --set ui.externalHostname=osac-ui-osac.apps.full.example.com
```

The five `--set` flags stand in for what `make install-osac` derives from
the live cluster at install time (see the `--set service.externalHostname`
block in the installer Makefile); a bare `helm template` fails with
`auth.oidcIssuerURL is required` without them. The `.example` secrets file
renders as-is: the schema only requires a non-empty
`DNS_RFC2136_KEY_SECRET`, so no local copy is needed for a render check.
For `full2`, swap the two overlay files for their `full2` counterparts and
use the `full2` cluster domain in the `--set` flags. The DNS settings land
in the `cluster-fulfillment-ig` ConfigMap and the TSIG secret in the
`cluster-fulfillment-ig` Secret (both from
`charts/aap/templates/instance-groups.yaml`).

### What the PR changes

- `osac-aap`: new collection `dns.rfc2136` (role `dns` with
  `create`/`delete`/`validate`/`check_result` tasks, argument specs,
  defaults), unit tests and a fake RFC 2136 server. The existing
  `dns.api.dns` dispatcher and both callers (the `external_access` template
  step and the operator-launched `cluster_endpoints` jobs) are unchanged:
  they already dispatch on `DNS_CLASS`.
- `osac-installer`: `charts/osac/values.schema.json` (new keys, conditional
  requirements), `values.yaml`/`values-example.yaml` comments, chart unit
  test `tests/dns_rfc2136_values_test.yaml`.
- Docs: `docs/dns-backend.md` (new, the reference for everything below),
  `docs/aap-configuration.md`, `docs/testing/osac-aap.md`,
  `docs/testing/osac-installer.md`, customer install guide.

### No OSAC image needs rebuilding

The labs pin `aap.bootstrap.image` and `aap.configAsCode.eeImage` to
`ghcr.io/osac-project/osac-aap@sha256:e7d14652...` (built from `3dc9c381`).
That image already contains everything the new driver needs, verified at
`3dc9c381`:

- `community.general` 10.5.0 is vendored, including
  `plugins/modules/nsupdate.py` (the only module the driver calls).
- `dnspython==2.8.0` is in the execution environment requirements.
- `bind-utils` is in the environment's system packages.

The new `dns.rfc2136` collection itself is not baked into the image path
the jobs use: the project's `ansible.cfg` sets
`collections_path=./vendor:./collections:...`, so job pods resolve it from
the synced project checkout, exactly like the existing `osac.*`
collections and the `dns.noop`/`dns.route53` drivers. The AAP project git
sync delivers it.

### How the AAP project picks up the new commit

`aap.configAsCode.projectGitUri` and `projectGitBranch` (in
`environment/install/pinned-images.yaml`: the fork URI and
`3dc9c381ed7e69f4fcafa9389dcf9776548b6f27`) render into the
`config-as-code-ig` Secret as `AAP_PROJECT_GIT_URI`/`AAP_PROJECT_GIT_BRANCH`.
The `osac.config_as_code` playbook applies them to the AAP Project object
(`scm_url`/`scm_branch`), and AAP syncs that ref into the project the job
templates run from.

To move the labs to the rebased code (when ready, not now):

1. Push `osac-7921-rfc2136-on-3dc9c381` to the fork (a branch or the commit
   SHA; AAP accepts any git ref in `scm_branch`).
2. Update `projectGitBranch` in `pinned-images.yaml` to the new commit
   `ae3d42a3f` (or the pushed branch name).
3. Apply the instance upgrade (the runbook's `install-osac` command, or the
   existing `apply-full2-external-dns.py` flow); config-as-code updates the
   project, the next project sync fetches the new revision, and the next
   job runs use it. No image change.

## BIND on the hypervisor: design

### Zone layout: one zone per lab

Two zones: `full.guests.osac.test` and `full2.guests.osac.test`, each
`type primary` with its own journal and its own TSIG key. A shared parent
(`guests.osac.test`) was rejected: both labs' AAP jobs would update one
zone file and journal, so a mistake or a corrupted journal in one lab
takes down the other; the labs are otherwise deliberately independent
(separate records files today, separate publishers, per-lab rebuilds).
Per-lab zones also match the chart config, where each lab's
`DNS_ZONE`/`EXTERNAL_ACCESS_BASE_DOMAIN` is its own zone, and the libvirt
forwarders are per-zone already. The driver's "record name must be inside
`DNS_ZONE`" check stays tight per lab.

Each zone allows updates only through `update-policy` restricted to
`A`/`AAAA` records below the zone, signed with that lab's key
(`osac-full-lab`, `osac-full2-lab`, hmac-sha256, generated by
`tsig-keygen`). The key of one lab cannot update the other lab's zone, the
SOA, or the NS records.

### Listener: named replaces dnsmasq at 127.0.0.54, plus one address per lab bridge

named takes over `127.0.0.54:53` from dnsmasq, so the libvirt network
forwarders (`<forwarder domain="full.guests.osac.test" addr="127.0.0.54"/>`
in `test-infra-net-full`, the same for `full2` in `test-infra-net-full2`,
and the same on the secondary networks) keep working unchanged. Queries
still chain exactly as today: AAP pod / worker / hub resolver to the
network resolver at `192.168.<x>.1`, which forwards the zone to
`127.0.0.54`.

RFC 2136 updates cannot ride that chain: the driver unicasts them to
`DNS_RFC2136_SERVER`, and `127.0.0.54` is the hypervisor's loopback, which
AAP job pods cannot reach. The bridge gateway `192.168.<x>.1` is reachable
from the pods but already runs the per-network libvirt dnsmasq on port 53.
A bridge address cannot be used either, and the first live run proved it:
libvirt's per-network dnsmasq runs `bind-dynamic`, which claims port 53 on
**every** address that appears on its bridge, UDP and TCP, the moment it
is added. Two servers then hold the same `192.168.<x>.2:53`, and TCP
updates land on whichever socket the kernel picks; dnsmasq answers a DNS
UPDATE with NOTAUTH(BADKEY).

So named listens on the hypervisor's management address `192.0.2.10`
(a placeholder; use your lab's address) instead, with `127.0.0.54` for
the forwarder chain. The AAP job pods reach it through the lab bridge
gateway: pod traffic SNATs to the node IP, the node's default route is
the bridge gateway (the hypervisor), and the packet is delivered locally. `DNS_RFC2136_SERVER` and `DNS_SERVER` in both overlays
point there. Both labs share the one listener; their per-lab TSIG keys
keep the zones separate, and rebuilding one lab cannot interrupt the
other's DNS path. The bridges helper removes any leftover
`192.168.<x>.2` address from the earlier design, which also releases the
libvirt dnsmasq claim on it.

named is authoritative-only (`recursion no`) for the two zones. The static
`dns-check.<zone>` records the lab checks rely on are kept in the initial
zone files, with a 60-second negative TTL as the PR's documentation
recommends for the readiness waits.

### Coexistence and cutover

named replaces dnsmasq on `127.0.0.54`; they cannot share it. The setup
script stops and disables both `osac-demo-dns.service` and
`osac-demo-dns-publisher@full/full2.service` first (the publishers restart
the dnsmasq unit on every records change, so leaving them enabled would
fight named), then refuses to start if anything still holds the port.

What becomes obsolete, and when:

| Thing | Fate |
| --- | --- |
| `osac-demo-dns.service` (dnsmasq) | stopped and disabled at cutover |
| `osac-demo-dns-publisher@full.service`, `@full2.service` | stopped and disabled at cutover |
| `/data/osac-demo/dns/full.records.conf`, `full2.records.conf` | kept on disk; their content is migrated (below) or simply left as a record of the pre-cutover state |
| `publish-guest-dns.py`, `watch-full2-guest-dns.py` | no longer run; stay in the repo as history |

Clusters created before the cutover hold records only in the dnsmasq files.
`migrate-dnsmasq-records.sh <lab>` parses that lab's records file (both
dnsmasq formats: `host-record=api,api-int,<ip>` and `address=/.apps.../<ip>`),
replays them into the BIND zone with signed nsupdate, and verifies each
one. Clusters created after the cutover never need it: OSAC creates their
records on install and deletes them on teardown. If a lab is rebuilt empty
during the cutover window, skip the migration for it.

One behavior change to know: queries for names outside the two zones that
still get forwarded to `127.0.0.54` (stale forwarders such as
`box.massopen.cloud` visible in the full2 network XML) now get REFUSED
instead of dnsmasq's no-upstream failure. Both fail; nothing depends on
them. Cleaning those forwarders out of the network XML is optional and out
of scope here.

## Helm overlays and the TSIG secret

`full-rfc2136.yaml` and `full2-rfc2136.yaml` (this directory) replace
`environment/install/full-dns.yaml` and `full2-dns.yaml` on future installs
of the rebased checkout. They are one self-contained file per lab rather
than a shared template plus per-lab fragments: that matches the existing
per-lab overlay convention in the runbook, keeps each lab's DNS settings in
one place, and avoids `-f` ordering mistakes when layering. They carry over
everything the old files had (zone names in all three settings, the
reserved guest ingress range, `operator.ignition.trustIngressCA`) and add:

- `DNS_CLASS: dns.rfc2136.dns`, `DNS_ZONE`, and the `DNS_RFC2136_*`
  settings the rebased schema defines (`SERVER`, `PORT`, `PROTOCOL`,
  `KEY_NAME`, `KEY_ALGORITHM`), plus `DNS_SERVER` for the unsigned
  readiness queries.
- No AWS credentials, as before.

The TSIG secret is supplied through a gitignored local file per lab,
following the `netris-secrets.local.yaml` pattern from the installer
README:

```bash
cd <skill>/scripts/lab/dns
cp full-rfc2136-secrets.local.yaml.example full-rfc2136-secrets.local.yaml
# on the hypervisor: grep secret /etc/named/osac-demo-keys/osac-full-lab.key
# paste the base64 string between the quotes, exactly as printed
```

`*-secrets.local.yaml` (and any copied key material) is excluded by
`.gitignore` in this directory. The value is the raw `secret` string from
the tsig-keygen file; Helm values for `aap.instanceGroups...secret` are
plaintext and the chart's patch script base64-encodes them once more when
writing the Kubernetes Secret (see `osac-installer/docs/aap-configuration.md`).

Install command for the rebased checkout (from its `osac-installer`,
schema patch applied first):

```bash
lab=full   # or full2
make install-osac PLATFORM=openshift PROFILE=full-ci NS=osac \
  AAP_LICENSE_FILE=... \
  INFRA_VALUES_EXTRA="-f values/full-ci/quota-demo-infra.yaml" \
  INSTANCE_VALUES_EXTRA="-f values/full-ci/quota-demo.yaml \
    -f $skill/scripts/lab/dns/$lab-rfc2136.yaml \
    -f $skill/scripts/lab/dns/$lab-rfc2136-secrets.local.yaml \
    -f $demo/environment/install/pinned-images.yaml"
```

The rebased schema still omits `CI_GUEST_INGRESS_IP_RANGE` (the PR did not
include it), so the runbook's patch step stays. The original
`environment/install/ci-ingress-range-schema.patch` does not apply to the
rebased tree (the PR reworded the neighboring `DNS_ZONE` description); use
`ci-ingress-range-schema-on-osac-7921.patch` from this directory instead
(verified with `git apply --check` on the rebased tree).

## First live application on the hypervisor, step by step

Nothing below has run. Review this list first.

1. **On the workstation, with network:** run the PR's unit tests on the
   rebased tree (`osac-aap/`: `uv run --group development pytest
   tests/unit/test_dns_rfc2136.py`) and the full chart suite
   (`helm unittest charts/osac`).
2. **Choose a cutover window** where no demo recording is imminent. The
   safest window is when a lab has no guest clusters; then no record
   migration is needed for it. Decide per lab: `full2` is the usual
   rebuild candidate.
3. **Copy the setup to the hypervisor:**
   `scp -r scripts/lab/dns root@<hypervisor>:/data/osac-demo/dns/setup`
   (do not copy any `*-secrets.local.yaml`; they are not needed on the
   hypervisor).
4. **Run the setup:**
   `ssh root@<hypervisor> -- /data/osac-demo/dns/setup/setup-demo-named.sh`.
   It installs bind, generates the two TSIG keys under
   `/etc/named/osac-demo-keys/`, stops the dnsmasq listener and the
   publishers, adds the bridge addresses, installs config, zones and units,
   starts `osac-demo-named.service`, and verifies: static `dns-check`
   through `127.0.0.54`, then a signed `nsupdate` add / `dig` through both
   `127.0.0.54` and the bridge address / `nsupdate` delete, per zone. Any
   mismatch aborts loudly.
5. **If the lab being cut over still has guest clusters:** run
   `/data/osac-demo/dns/setup/migrate-dnsmasq-records.sh <lab>` to replay
   its records file into the zone, then spot-check
   `dig @127.0.0.54 api.<order>.<zone>`.
6. **Confirm the AAP path** (the one thing the setup script cannot test
   from the hypervisor): from a hub node or an AAP pod of that lab,
   `dig @192.0.2.10 dns-check.full.guests.osac.test` (or the full2
   equivalents). This validates bridge reachability and any firewalld
   behavior end to end.
7. **Wire the secret:** create `<lab>-rfc2136-secrets.local.yaml` from the
   example with the key secret from the hypervisor.
8. **Point the lab at the rebased code:** push the branch to the fork,
   update `projectGitBranch` in `pinned-images.yaml`, and run the
   `install-osac` upgrade for that lab with the new overlay and secrets
   file (command above). Read back
   `oc -n osac get configmap cluster-fulfillment-ig -o yaml` to confirm
   the rendered settings.
9. **Prove one cluster end to end:** create a cluster order in that lab,
   watch the AAP `cluster_endpoints` job publish
   `api.<order>.<zone>`, `api-int.<order>.<zone>` and `*.apps.<order>.<zone>`
   (query them from an AAP pod, as the runbook does today), then delete
   the cluster and confirm the records are gone
   (`dig @127.0.0.54` returns NXDOMAIN or an empty answer).
10. **Only then repeat for the second lab.**

Rollback, if step 4 or 9 goes wrong: stop and disable
`osac-demo-named.service` (and the bridges unit), restart
`osac-demo-dns.service` and the lab's publisher, and reinstall the lab with
its old `*-dns.yaml` overlay. The dnsmasq files and units are left in place
by the cutover, so this is one systemd dance, no reinstall of hypervisor
state.

## Open questions

1. **Firewalld on the bridges** (step 6): the design assumes the lab
   bridges' firewalld zone permits DNS (the libvirt zone normally does).
   The setup script adds the `dns` service when firewalld is active and
   the zone lacks it. Verify the AAP-pod query before relying on it.
2. **Bridge address survival across libvirt network restarts:** the extra
   `.2` addresses are re-added by `osac-demo-named-bridges.service` at
   boot, and by hand after a `virsh net-destroy`/`net-start` lab rebuild
   (the script is idempotent). If lab rebuilds become frequent, consider a
   libvirt hook instead. Not needed for the demo cadence.
3. **AAP pod egress to the bridge address** was designed from the network
   topology (pods SNAT to hub node IPs on the same bridge; the address is
   local to the hypervisor, so no forwarding is involved) but not yet
   observed live. Step 6 and step 9 verify it.
4. **`named` user and SELinux (resolved on first live run):** keys now
   live under `/etc/named/osac-demo-keys/` (labeled `named_conf_t` by the
   setup script). The original design put them under
   `/data/osac-demo/dns/keys/`, but `/data` and `/data/osac-demo` are
   `unlabeled_t`, and the SELinux-confined `named` domain cannot
   traverse unlabeled directories (the denial is dontaudit-suppressed,
   so it only appears as EACCES in the service). The setup script moves
   any legacy keys to the new path once. Dynamic zones live in the
   standard `/var/named/dynamic/` (named-writable) location.
5. **Key rotation** is manual: regenerate with tsig-keygen, update the
   include, restart named, update the lab's secrets file, re-run the
   install. Acceptable for a lab; noted for completeness.
