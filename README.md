# Simulation Infrastructure PoC — Self-Service IaC for CAD/CFD Workloads

## Problem Statement

CAD and CFD simulation teams need **on-demand, high-performance compute** — but provisioning infrastructure manually creates bottlenecks, leads to configuration drift, and generates uncontrolled AWS costs when engineers forget to tear down instances after a simulation run.

## What This Project Does

This repository implements a **Self-Service Infrastructure** platform that enables CAD developers to launch simulation-ready EC2 instances through a GitHub Actions workflow — no Terraform expertise required — while enforcing organizational guardrails automatically.

### Architecture at a Glance

```
Developer triggers workflow (picks instance type)
        │
        ▼
GitHub Actions ─── Checkov Security Scan ──▶ FAIL → Block deploy
        │
        ▼ PASS
Terraform provisions:
  ┌─────────────────────────────────────────┐
  │  VPC (10.0.0.0/16)                      │
  │    └── Public Subnet (10.0.1.0/24)      │
  │          └── EC2 (simulation-ready)      │
  │                └── Elastic IP            │
  │                                          │
  │  S3 Remote Backend + DynamoDB Lock       │
  │  Cost Tags: Project=Simulation           │
  └─────────────────────────────────────────┘
        │
        ▼
Cost Guard (runs on schedule via cron)
  → Stops instances running > 4 hours
  → Prevents runaway AWS bills
```

### Key SRE Principles Demonstrated

| Principle | Implementation |
|---|---|
| **Infrastructure as Code** | Terraform with remote state, locking, and modular variables |
| **Shift-Left Security** | Checkov static analysis runs before any `terraform apply` |
| **Cost Control** | Automated cleanup script + mandatory cost-tracking tags |
| **Self-Service** | `workflow_dispatch` with dropdown inputs — zero Terraform knowledge needed |
| **Idempotency** | S3 + DynamoDB backend prevents state corruption in team environments |
| **Observability** | Tagged resources enable cost dashboards and audit trails |

## Repository Structure

```
simulation-infra-poc/
├── terraform/
│   ├── backend.tf          # S3 remote state + DynamoDB locking
│   ├── main.tf             # VPC, Subnet, EC2, EIP, Security Group
│   └── variables.tf        # Parameterized inputs with sensible defaults
├── scripts/
│   └── cleanup.py          # Boto3 cost-guard: stops idle simulation instances
├── .github/
│   └── workflows/
│       └── deploy.yml      # Self-service CI/CD with security scanning
├── docs/
│   └── interview-pitch.md  # How to present this to an architect
└── README.md
```

## Quick Start

### Prerequisites

- AWS CLI configured with appropriate IAM permissions
- Terraform >= 1.5
- Python 3.9+ with `boto3` installed
- GitHub repository with `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` secrets

### Manual Deployment

```bash
cd terraform/
terraform init
terraform plan -var="instance_type=t3.medium"
terraform apply -auto-approve
```

### Self-Service Deployment (Recommended)

1. Go to **Actions** → **Deploy Simulation Infrastructure**
2. Select instance type from the dropdown
3. Click **Run workflow**
4. Terraform plan output is available in the workflow logs for audit

### Cost Guard

Run the cleanup script manually or schedule it via cron / EventBridge:

```bash
python scripts/cleanup.py
```

Instances tagged `Project: Simulation` running longer than 4 hours are stopped automatically.

## Design Decisions

**Why a public subnet with EIP?**
Simulation engineers need direct SSH/RDP access to interact with CAD tools. In production, this would sit behind a bastion host or SSM Session Manager — this PoC prioritizes demonstrating the self-service workflow.

**Why Checkov over tfsec?**
Checkov covers Terraform, CloudFormation, Kubernetes, and Dockerfiles with a single tool. For a team that may adopt multi-cloud or containerized simulation workloads, Checkov scales better.

**Why stop instead of terminate?**
Stopped instances retain their EBS volumes and configuration. Simulation data on local storage is preserved, and the engineer can restart when ready — avoiding re-provisioning overhead.

## Known Limitations — Intentional PoC Tradeoffs

This is a Proof of Concept, not a production deployment. The following are deliberate shortcuts, listed so they can be addressed in a real rollout rather than discovered during a security review.

### Security posture

| Limitation | Why it's here | Production fix |
|---|---|---|
| SSH open to `0.0.0.0/0` (`allowed_ssh_cidrs` default) | Engineers need direct access without a VPN or bastion for the demo | Lock to corporate CIDR, or replace with SSM Session Manager (no inbound port 22) |
| EC2 in a **public subnet** with an EIP | Direct routability for the self-service demo | Private subnet + NAT, with SSM or a bastion for access |
| **Static AWS keys** in GitHub Secrets | Fastest path to a working CI/CD pipeline | OIDC federation: `aws-actions/configure-aws-credentials@v4` with `role-to-assume` — `id-token: write` permission is already declared, the role and trust policy are not yet created (tracked as a GitHub issue) |
| **No IAM role on the instance** | EC2 doesn't need AWS API access for this PoC | Attach an instance profile scoped to the S3 result bucket only |
| **No VPC flow logs** | Out of scope for a single-instance PoC | Enable flow logs to S3 or CloudWatch with 30-day retention |
| Default security group **not explicitly restricted** | Terraform doesn't manage the default SG unless you declare an `aws_default_security_group` resource | Add that resource with no ingress/egress rules to satisfy CIS and `CKV2_AWS_12` |

### Reliability posture

| Limitation | Why it's here | Production fix |
|---|---|---|
| **Single AZ** — subnet hard-coded to `${region}a` | PoC is a single instance | Span multiple AZs, put solver jobs behind AWS Batch, put control plane on EKS (see `docs/adr/001-eks-vs-ec2-for-simulation.md`) |
| **No autoscaling** | A single instance is the unit of work for this demo | ASG for API layer; Batch compute environment for solver jobs |
| **No health check wired into the workflow** | Out of scope for a one-shot provision pipeline | Post-apply smoke-test job that polls `/healthz` before the pipeline reports success (tracked as a GitHub issue) |
| **No SLO, no alerting** | PoC has no metrics to alert on | Prometheus + Grafana, Google SRE burn-rate alerts (14.4× / 6× / 3× windows) — scoped for a follow-up PoC |

### Workflow / pipeline

| Limitation | Why it's here | Fix |
|---|---|---|
| Checkov `skip_check` list contains **7 intentional skips** | Public subnet, open SSH, open egress, IAM role, VPC flow logs, default SG, public IP — all are documented tradeoffs above | Each skip is commented in `.github/workflows/deploy.yml` with the rationale. In production, reduce the skip list to zero and fail the build on any new finding |
| **Step summary text is stale** | Says *"Skipped checks: CKV_AWS_88"* but we skip 7 | Tracked as a GitHub issue — cosmetic, audit-trail only |
| **Free Tier-restricted accounts** can't launch `t3.medium` default | The default matched the JD tech stack narrative, but AWS accounts with a Free Tier service-control policy reject it | `t3.micro` was added to the approved list as a smoke-test-friendly option |
| Actions use Node.js 20 | GitHub runners will force Node 24 by June 2026 | Bump `actions/checkout`, `configure-aws-credentials`, `setup-terraform`, `setup-python` to Node 24-compatible majors before the deprecation |

### What this list signals

Calling these out is the point. A PoC that doesn't know what's wrong with itself is harder to evolve than one that does. Each row above is a **conscious tradeoff**, not an unknown risk.

## Author

Built as an SRE/DevOps Proof of Concept demonstrating production-grade infrastructure automation, cost governance, and developer self-service patterns.

---

*License: MIT*
