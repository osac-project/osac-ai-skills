# Networking Architecture Decisions

Extracted from the merged unified networking designs.
Read this file during planning, implementation, and review of OSAC networking-related work.
For full designs, see `enhancement-proposals/enhancements/` — search for networking-related
directories (OSAC-1433, OSAC-1435, OSAC-1436, OSAC-1437, dns-api). Before finalizing PRD or
design scope for a feature that adds IP, MAC, or network-attachment data to any resource, check
whether one of these already-accepted designs commits to delivering that same field — the
decisions below establish the general mechanism (e.g., DHCP-based IP assignment via decision 10),
not whether a specific field already exists in an accepted design elsewhere. If the new ticket is
unrelated to that design and happens to overlap with it, exclude the overlapping scope and cite
the existing design instead of redelivering it. If the new ticket is itself an intentional
revision or extension of that design, say so explicitly (name it as superseding/extending that
design) rather than treating the overlap as a conflict to avoid.

## Key design decisions

These are non-negotiable architectural decisions from the merged designs:

1. **Two-manager model**: `fabricManager` (Netris/Neutron — handles ALL physical networking) + optional `k8sManager` (bridges VMs to fabric via OVN). Never conflate the two.
2. **VMs are part of the fabric**: VMs join the physical network through the K8s manager bridge. Once on the fabric, they are treated identically to bare-metal and cluster nodes.
3. **ExternalIP replaces PublicIP**: The rename clarifies that addresses are external to the VirtualNetwork, not necessarily internet-routable. Both names coexist during migration (see `OSAC-1433-unified-networking/design.md` for the rename and migration strategy).
4. **Infrastructure-agnostic subnets**: The same Subnet can host VMs, BM servers, and cluster nodes. No per-service-type subnet variants.
5. **Uniform API**: VirtualNetwork, Subnet, SecurityGroup, ExternalIP, NATGateway serve VMaaS, CaaS, and BMaaS identically — no service-specific resource types for networking.
6. **One NetworkClass per deployment**: Provider-level CRD, tenants never interact with it.
7. **Fabric manager handles isolation**: Tenant isolation, ACLs, IP allocation, DNAT, SNAT, and inter-subnet L3 routing are all fabric manager responsibilities.
8. **Direction separation**: ExternalIPAttachment = inbound (DNAT) only, NATGateway = outbound (SNAT) only. These must never overlap or be conflated.
9. **Multi-NIC primary designation**: When a resource has >1 network attachment, exactly one must be `primary: true`. The primary attachment designates the default gateway, DNAT target, and SNAT source.
10. **DHCP-based IP assignment**: All resource types receive IPs via DHCP (VMs from OVN DHCP, BM and CaaS agents from fabric DHCP). No static IP configuration.
11. **Pluggable managers via ConfigMap**: Each manager ships a ConfigMap declaring type + capabilities. Adding a new manager = deploy ConfigMap + Ansible role, no API changes required.
12. **Default networking auto-provisioning**: Tenant onboarding creates VN + IPv4 Subnet + IPv6 Subnet + SG + NATGateway (dual-stack from NetworkClass defaults). `DefaultNetworkingReady` condition gates tenant readiness.

## Per-resource attachment types

The designs define three distinct attachment types with different fields — do not mix them up:

| Type | Fields | Used by |
|------|--------|---------|
| `ComputeNetworkAttachment` | subnet, security_groups, `primary` | ComputeInstance (VMaaS) |
| `ClusterNetworkAttachment` | subnet, security_groups (singular, no `primary`) | Cluster (CaaS) |
| `BareMetalNetworkAttachment` | subnet, security_groups, `interface`, `primary` | BaremetalInstance (BMaaS) |

## Deletion ordering

The designs establish strict deletion ordering with phased requeue. Violating this order causes finalizer leaks and stuck resources:

1. Delete auto-provisioned ExternalIPAttachment → wait for removal
2. Delete auto-provisioned ExternalIP → wait for removal
3. Remove finalizer from parent resource (ComputeInstance/Cluster/BaremetalInstance)
4. Manually created ExternalIP/ExternalIPAttachment persist — tenant manages their lifecycle
5. Default networking resources persist — they are tenant-scoped and shared
