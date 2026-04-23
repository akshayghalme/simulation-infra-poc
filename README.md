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

## Author

Built as an SRE/DevOps Proof of Concept demonstrating production-grade infrastructure automation, cost governance, and developer self-service patterns.

---

*License: MIT*
