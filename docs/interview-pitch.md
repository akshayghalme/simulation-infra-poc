# Interview Pitch — Explaining This Project to a CCTech Architect

## The 60-Second Elevator Pitch

> "At CCTech, simulation engineers need compute on demand — but the traditional workflow of filing infra tickets creates a 2-day bottleneck that kills iteration speed. I built a self-service platform where a developer picks an instance type from a dropdown, clicks 'Run,' and gets a simulation-ready EC2 in minutes — with security scanning and cost guardrails baked into the pipeline. No Terraform knowledge required, no runaway AWS bills."

## Talking Points by Theme

### 1. Developer Productivity

**The problem you're solving:**
CAD/CFD engineers are domain experts, not infrastructure experts. Every hour they spend waiting for an Ops engineer to provision a machine is an hour they're not iterating on simulation models.

**What to say:**
- "I designed this as a `workflow_dispatch` pipeline with dropdown inputs. A simulation engineer sees familiar options — `c5.xlarge` for CFD, `r5.large` for large assemblies — and the pipeline handles VPC, security groups, EIP, everything."
- "The key insight is that self-service doesn't mean self-managed. The infrastructure is codified, version-controlled, and reproducible. If a simulation needs to be re-run six months later, the exact same environment can be recreated from the same commit."

**Anticipated follow-up:** *"How would you handle different simulation profiles?"*
- "I'd extend this with Terraform workspaces or modules — a `cfd-heavy` profile pre-loads NVIDIA drivers and attaches an FSx Lustre volume, while a `cad-review` profile spins up a lighter instance with a pre-configured VNC server."

### 2. Reliability & Cost Control

**The problem you're solving:**
Simulation workloads are bursty. An engineer launches a `c5.2xlarge` for a 2-hour CFD run, gets pulled into a meeting, and the instance runs for 3 days at $0.34/hour. Multiply by a 20-person team and you have a billing surprise.

**What to say:**
- "The Cost Guard script runs on a schedule and enforces a 4-hour runtime ceiling. It doesn't terminate — it stops, so EBS data is preserved and the engineer can resume later."
- "Every resource is tagged with `Project: Simulation` and `Owner: DevTeam`, which means I can set up AWS Cost Explorer dashboards that break down spend by team and workload type. Tags are the foundation of cloud financial governance."
- "The S3 backend with DynamoDB locking prevents a common reliability failure — two engineers running `terraform apply` simultaneously and corrupting state. In a team of 20 simulation engineers, this is a real scenario."

**Anticipated follow-up:** *"What would you do differently in production?"*
- "Three things: First, replace IAM keys with OIDC federation — GitHub Actions supports this natively, and it eliminates long-lived credentials. Second, add SSM Session Manager instead of direct SSH — it provides auditable access without opening port 22. Third, wrap the Cost Guard in a Lambda behind EventBridge, so it runs every 30 minutes without needing a management instance."

### 3. Security Posture

**What to say:**
- "Checkov runs before any `terraform apply`. If someone modifies the security group to allow 0.0.0.0/0 on port 3389, the pipeline blocks the deploy. Shift-left security means the feedback loop is minutes, not days."
- "IMDSv2 is enforced on every instance — this prevents SSRF-based credential theft, which is one of the most common cloud attack vectors."
- "The Terraform validation blocks restrict instance types to an approved list. A developer can't accidentally spin up a `p4d.24xlarge` GPU instance at $32/hour."

### 4. Scalability Vision (Bonus — Shows Forward Thinking)

**If asked "Where would you take this next?":**
- "Phase 2 would add Prometheus + Grafana for simulation job observability — CPU utilization, memory pressure, EBS IOPS — so engineers can right-size their instance type based on actual workload metrics, not guesswork."
- "Phase 3 would be an internal developer portal (Backstage or a custom Slack bot) where an engineer types `/simulate cfd-heavy 4h` and the entire lifecycle — provision, monitor, auto-stop — is handled end-to-end."
- "Long term, for heavy CFD workloads, I'd evaluate AWS ParallelCluster or EKS with Karpenter for auto-scaling node pools — but the self-service and cost-control patterns from this PoC carry over directly."

## What NOT to Say

- Don't oversell this as production-ready. Call it a PoC that demonstrates patterns.
- Don't apologize for using a public subnet. Explain the trade-off and state what you'd change (SSM, bastion host).
- Don't get lost in Terraform syntax. Focus on the *why* — developer velocity, cost governance, security posture.

## Closing Statement

> "This project reflects how I think about SRE: infrastructure should be a product that serves developers, not a bottleneck that blocks them. The three pillars — self-service provisioning, automated cost control, and shift-left security — are patterns I'd apply to any cloud-native engineering team, whether the workload is simulation, ML training, or microservices."
