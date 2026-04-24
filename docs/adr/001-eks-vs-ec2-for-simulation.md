# ADR-001: EKS for the Control Plane, EC2 for Solver Compute

| | |
|---|---|
| **Status** | Accepted |
| **Date** | 2026-04-24 |
| **Deciders** | Platform / SRE team |
| **Supersedes** | — |

## Context

simulationHub runs two workload shapes that look identical on a slide and nothing alike in production:

1. **Control plane** — ~200 REST APIs, result catalog, user/project service, billing, async job orchestrator. Short-lived requests, bursty RPS, HTTP/gRPC, stateless-ish, deploys daily.
2. **Solver compute** — the actual CFD run. A single job consumes 1–64 vCPU for 30 min–3 days, allocates 8–128 GB RAM, emits 1–50 GB of result files to S3. Zero ingress traffic; scheduled-once, runs-to-completion.

"Put everything on EKS" is the default cloud-native answer and it's wrong for shape #2 — Kubernetes primitives (Service, Deployment, HPA, sidecars, service mesh) solve problems that solvers don't have, and impose overhead (kubelet, container runtime, CNI, logging sidecar) that solvers actively pay for in wall-clock time.

"Put everything on EC2" is wrong for shape #1 — the control plane is a microservice fleet and belongs on something that treats pods as cattle.

## Decision

Run the two planes on the tools that fit them.

| Layer | Platform | Why |
|---|---|---|
| API / control plane / catalog | **EKS** (managed node groups + Karpenter) | Rolling deploys, HPA, zero-downtime, service mesh, native ingress, Prometheus scraping |
| Async job scheduler (submits solver runs) | **EKS** | Same cluster as control plane; uses EventBridge → SQS → worker pods |
| Solver compute (CFD execution) | **EC2** via AWS Batch or ParallelCluster | Long-running, large-memory, spot-friendly, no network serving |
| Per-engineer interactive sandbox (this PoC) | **EC2** direct | Matches engineer mental model; SSH-driven CAD tooling |
| Shared state (project DB, result metadata) | **RDS PostgreSQL** | Out of scope for this ADR |

Both planes share the same VPC, IAM boundaries, tagging, and observability pipeline. The seam is **S3 + EventBridge**: the control plane publishes a "run job" event; the Batch queue pulls it; results land back in S3 and the catalog picks them up.

## Rationale

**Why not EKS for solvers?**
- A 3-day CFD job on an EKS pod pins a node for 3 days. Karpenter won't reclaim it, HPA can't scale it, a rolling cluster upgrade has to drain or wait. Batch handles this primitive natively — jobs are first-class, nodes are disposable, upgrades don't touch in-flight work.
- Memory-bound solvers (r5 / x2iedn) benefit from 1:1 instance:job affinity. Scheduling them as pods adds kubelet overhead (~1–3%) with zero functional upside.
- Spot interruption handling for solvers is a Batch feature (managed requeue on interruption); in EKS you'd write it yourself.

**Why not EC2 for the control plane?**
- 200 microservices on raw EC2 means rebuilding what EKS gives for free: service discovery, rolling deploy, failure detection, autoscaling, secrets mounting, sidecar injection.
- Deploy cadence (daily → hourly) makes AMI-based deploys miserable. Container image + `kubectl rollout` is the right tool.

**Why "both" rather than "pick one"?**
- The two planes have different SLOs (control plane 99.9% availability; solver 99% job completion). Coupling them on one runtime couples the SLOs too.
- Solver cost dominates the AWS bill (70-80% at steady state). Every percent of solver-side efficiency beats any control-plane optimisation. Running solvers on Batch/Spot gives ~60–70% off list price; EKS spot pods can't match that safely for multi-hour jobs.

## Consequences

### Positive

- **Tier-0 API stays boring** — EKS + standard SRE tooling, no bespoke EC2 orchestration.
- **Solver cost drops** — Batch + Spot + right-sized instance families is the single biggest cost lever on the bill.
- **Upgrade paths decouple** — EKS version bumps don't interrupt running solver jobs, and vice versa.
- **Chaos engineering fits both** — FIS covers EC2/Batch (`aws:ec2:stop-instances`, `aws:ec2:send-spot-instance-interruptions`); Litmus covers EKS (see `chaos/experiments/pod-kill-simulation-api.yaml`). One team, two tools, clear boundary.

### Negative

- **Two runtimes to operate.** Two sets of IAM roles, two monitoring configurations, two incident runbooks. Mitigated by sharing the VPC, tagging, and observability stack.
- **The seam is S3 + EventBridge** — a failure of that bridge looks like "solvers are running, nothing downstream notices." Add a catalog-lag SLO and an alert on `result_catalog_ingest_age_p99`.
- **Engineers need to pick** where a new service goes. Default rule: *if it serves HTTP or gRPC, it's EKS; if it's a job that finishes, it's Batch/EC2*.

### Follow-ups

1. ADR-002 — Spot vs On-Demand split for the Batch compute environment.
2. ADR-003 — FIS and Litmus experiment catalogue (when to run what, on what cadence).
3. Terraform module `simulation-batch/` — mirror of the current `simulation-compute/` pattern but for Batch compute environments + job queues + job definitions.

## Not Decided Here

- **Karpenter vs managed node groups** for EKS — deferred; both work, will decide once we have sustained traffic data.
- **ParallelCluster vs Batch** for solvers — Batch is the default; ParallelCluster only if a customer needs MPI across nodes for a single job (rare at this scale).
- **Multi-region** — single region (`ap-south-1`) until customer latency data justifies the complexity.
