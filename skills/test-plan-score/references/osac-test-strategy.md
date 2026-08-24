# OSAC Testing Strategy — Context for Test Plan Skills

This file provides the OSAC-specific testing context that /test-plan-create
and /test-plan-score need to generate grounded, actionable test plans.

## Test Pyramid

Every OSAC test belongs at a specific level. The level determines which repo,
framework, and infrastructure the test uses.

### Level 1: Unit Tests (Component Repos)

Test individual functions and methods in isolation. Mock external dependencies.

| Component | Framework | Location | Run Command | Count |
|-----------|-----------|----------|-------------|-------|
| fulfillment-service | Ginkgo/Gomega + uber-go/mock | `internal/*/` co-located | `ginkgo run -r internal` | 345+ |
| osac-operator | Ginkgo/Gomega + envtest | `internal/*/` co-located | `make test` | ~40 |
| osac-ui | Vitest + Testing Library | `libs/*/`, `apps/*/` | `pnpm test` | 16 |

**Patterns:**
- Ginkgo v2: `Describe` > `It` blocks, `BeforeEach` for setup, `DeferCleanup` for teardown
- Gomega assertions: `Expect(value).To(Matcher)`
- Mocking: `go.uber.org/mock` with `//go:generate mockgen`
- Proto builders: `publicv1.ClustersListRequest_builder{}.Build()`
- Database: `server.MakeDatabase()` + `dao.CreateTables[T](ctx)`

### Level 2: Integration Tests (Component Repos)

Test cross-component interactions with real infrastructure.

| Component | Framework | Location | Infrastructure | Count |
|-----------|-----------|----------|----------------|-------|
| fulfillment-service | Ginkgo | `it/` | kind cluster + PostgreSQL + Keycloak + Envoy | 27 |
| osac-operator | Ginkgo + envtest | `*_integration_test.go` | envtest (API server + etcd) | ~5 |

**fulfillment-service IT infrastructure:**
- Kind cluster named `osac-dev`, created via
  `make -C osac-installer install-infra PLATFORM=kind PROFILE=dev NS=osac`
- PostgreSQL for data storage
- Keycloak for authentication (JWT tokens)
- Envoy Gateway for TLS + SNI routing
- Requires `/etc/hosts` entries:
  - `127.0.0.1 keycloak.keycloak.svc.cluster.local`
  - `127.0.0.1 fulfillment-api.osac.svc.cluster.local`
  - `127.0.0.1 fulfillment-internal-api.osac.svc.cluster.local`
- Clean up: `make -C osac-installer uninstall PLATFORM=kind PROFILE=dev NS=osac`

**IT test patterns:**
```go
// Client testing with real gRPC
client := publicv1.NewClustersClient(tool.UserConn())
req := publicv1.ClustersListRequest_builder{}.Build()
resp, err := client.List(ctx, req)
Expect(err).ToNot(HaveOccurred())
```

### Level 3: E2E Tests (osac-test-infra)

Test full user workflows against a live OSAC cluster via gRPC API and K8s CRDs.

| Domain | Location | Tests | Key Fixtures |
|--------|----------|-------|-------------|
| CaaS (Clusters) | `tests/caas/` | 6: lifecycle, credentials, templates, delete-during-provision | `grpc`, `k8s_hub_client` |
| VMaaS (Compute) | `tests/vmaas/` | 11: instances, networks, subnets, security groups, JWT, console | `grpc`, `k8s_virt_client`, `vm_template` |
| Public IP | `tests/vmaas/public_ip/` | 2: pool lifecycle, capacity | `grpc`, `k8s_hub_client` |
| Catalog | `tests/catalog/` | 2: item lifecycle, compute instance catalog | `grpc`, `private_grpc` |
| Storage | `tests/storage/` | 1: tenant storage lifecycle | `grpc`, `k8s_hub_client` |

**Framework:** pytest 8.0 + xdist (parallel execution)

**Shared test infrastructure (osac-test-infra core):**

| Module | Purpose |
|--------|---------|
| `tests/core/grpc_client.py` | gRPC client with create/list/get/delete methods per resource |
| `tests/core/k8s_client.py` | K8s CRD queries via kubectl with label selectors and jsonpath |
| `tests/core/helpers.py` | Wait helpers using `poll_until` (wait for CR, wait for Ready, wait for deletion) |
| `tests/core/runner.py` | `run()`, `run_unchecked()`, `poll_until()`, `env()` |
| `tests/core/keycloak.py` | Keycloak token management and auth helpers |
| `tests/core/osac_cli.py` | OSAC CLI wrapper for CLI-based operations |
| `tests/conftest.py` | Session-scoped fixtures: `grpc`, `k8s_hub_client`, `cli`, `namespace` |

**E2E test patterns:**
```python
def test_cluster_lifecycle(grpc, k8s_hub_client):
    # Create
    cluster = grpc.clusters.create(name="test-cluster", template="default")
    
    # Wait for Ready
    poll_until(lambda: grpc.clusters.get(cluster.id).status == "Ready", timeout=300)
    
    # Verify K8s resources
    cr = k8s_hub_client.get("clusterorders", cluster.id)
    assert cr["status"]["phase"] == "Ready"
    
    # Cleanup
    grpc.clusters.delete(cluster.id)
    poll_until(lambda: not grpc.clusters.exists(cluster.id), timeout=60)
```

### Level 4: UI Tests (osac-ui)

| Type | Framework | Location | Count |
|------|-----------|----------|-------|
| Component Unit | Vitest + Testing Library | Co-located with components | 16 |
| E2E Flows | Cypress 14 | `apps/e2e/cypress/` | 2 |

## Services and Personas

### OSAC Services

| Service | Description |
|---------|-------------|
| BMaaS | Bare Metal as a Service — physical machine provisioning |
| CaaS | Cluster as a Service — Kubernetes via Hosted Control Planes |
| VMaaS | Virtual Machines as a Service — KubeVirt compute instances |
| MaaS | Model as a Service — AI model serving and inference |
| Enclave | Day 1/Day 2 operations, installation, wizard UI |

### OSAC Personas

| Persona | Role |
|---------|------|
| Cloud Provider Admin | Super-user: tenant onboarding, quotas, global catalogs |
| Cloud Infrastructure Admin | Core infra: network, storage, compute backends |
| Tenant Admin | Org config, users, IDP, org-specific catalogs |
| Tenant User | Self-service: provisions resources via catalog |

### Service x Persona Coverage Matrix

When generating a test plan, use this matrix to determine which test types
are required for each service-persona combination:

|  | Cloud Provider Admin | Cloud Infra Admin | Tenant Admin | Tenant User |
|--|---------------------|-------------------|-------------|-------------|
| **BMaaS** | IT + E2E (onboarding, inventory) | Unit + IT + E2E (host provisioning) | N/A | E2E (bare metal order) |
| **CaaS** | IT + E2E (quota, catalogs) | IT + E2E (cluster templates) | E2E (tenant clusters) | Unit + IT + E2E (cluster order lifecycle) |
| **VMaaS** | IT + E2E (templates, pools) | Unit + IT + E2E (networking, storage) | E2E (VN, subnet, SG mgmt) | Unit + IT + E2E (VM lifecycle) |
| **MaaS** | E2E (model catalog) | E2E (GPU pool config) | E2E (model access) | E2E (inference endpoint) |
| **Enclave** | IT + E2E (install wizard) | IT + E2E (day-2 ops) | N/A | N/A |

## Risk-Based Prioritization

### HIGH Risk — Maximum Coverage (P0)

- **Tenant isolation / multi-tenancy** — OPA policies, namespace scoping, annotation filtering
- **Provisioning lifecycle** — create -> pending -> ready -> delete across all components
- **Cross-component workflows** — API -> operator -> AAP -> infrastructure
- **Authentication & authorization** — JWT, Keycloak, RBAC enforcement
- **Data integrity** — PostgreSQL transactions, status consistency

### MEDIUM Risk — Standard Coverage (P1)

- API field validation and error responses
- Status condition transitions
- Template / catalog operations
- Controller reconciliation edge cases
- CLI command behavior

### LOW Risk — Minimal Coverage (P2)

- Read-only list/get operations (covered by lifecycle tests)
- Static validation (yamllint, helm-lint)
- Logging and observability output
- Documentation rendering

## Test Type Requirements by Change Area

| Change Area | Unit | IT | E2E |
|------------|------|-----|-----|
| Proto / API definition | Yes | Yes | Yes |
| Controller logic | Yes | Yes | Yes |
| AAP playbooks | — | — | Yes |
| UI components | Yes | — | Yes |
| Helm / installer | — | Yes | Yes |
| Documentation | — | — | — |

## Coverage Thresholds

| Component | Unit Coverage | Integration | E2E | Measurement |
|-----------|-------------|-------------|-----|-------------|
| fulfillment-service | 75% line on `internal/servers/` | All CRUD lifecycle paths | Per-service lifecycle test | `ginkgo -cover` |
| osac-operator | 100% reconcile paths | envtest with controllers | Controller lifecycle | `make test` |
| osac-test-infra | N/A | N/A | 1 lifecycle test per resource per service | `pytest` |
| osac-ui | 70% component coverage | N/A | Critical user flows | Vitest + Cypress |
| osac-installer | N/A | kustomize build succeeds | Helm install on kind | yamllint |

## Quality Gates

### Gate 1: PR Merge (Dev -> Review)
- All existing unit tests pass
- New code has unit tests (Ginkgo for Go, Vitest for TS)
- Linting passes (golangci-lint, ruff, eslint)
- Build succeeds (`go build`, `pnpm build`)

### Gate 2: Integration Verified (Review -> QA)
- PR merged to main
- fulfillment-service `it/` green (kind cluster)
- osac-operator envtest green
- No flaky failures (re-run on failure before blocking)

### Gate 3: E2E Verified (QA -> Staging)
- Feature deployed to QA cluster
- E2E tests in osac-test-infra pass for affected domains
- Test plan scored >= 8/10 (Ready verdict)
- All P0 test cases implemented and passing
- No critical bugs open

### Gate 4: Release Ready (Staging -> GA)
- All quality gates 1-3 passed
- All test cases from test plan implemented
- Full E2E regression suite passes
- Performance baselines met
- Documentation complete
- Tech lead sign-off
