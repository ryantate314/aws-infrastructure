# aws-infrastructure

Terraform for my personal AWS account: a photo-delivery site today, a static marketing site next, and a training ground for the AWS Solutions Architect exam.

**Design rules:** serverless first, **low monthly cost** (target under about $5/month), security best practice, strong isolation between environments and workloads. No NAT Gateway, Network Firewall or other fixed-price services (see [docs/cost.md](docs/cost.md)).

> Agents: read [AGENTS.md](AGENTS.md) first.

## Layout

| Path | What it is | State |
|---|---|---|
| `bootstrap/` | Creates the S3 bucket that stores Terraform state. | **Local, committed** (no secrets by design) |
| `account/` | Account guardrails: budgets, anomaly alerts, CloudTrail, password policy, Access Analyzer, workload permissions boundary, optional GitHub OIDC roles. | S3 |
| `envs/modules/baseline/` | Reusable per-environment network baseline (VPC, subnets, SGs, free gateway endpoints). | n/a |
| `envs/dev`, `envs/prod` | Thin roots that call the baseline module. | S3 |
| `templates/workload/` | Copy-and-rename starter for a new project (serverless static site on S3 + CloudFront). | n/a |
| `workloads/<name>/` | Real workloads, created by `scripts/new-workload.sh`. | S3 |
| `scripts/` | `inventory.sh` (read-only AWS discovery), `new-workload.sh`. | n/a |
| `docs/` | Architecture, cost, security, runbook, SAA study map, migration plan, ADRs. | n/a |

## Quick start (new account or rebuild)

Prerequisites: Terraform >= 1.10, AWS CLI v2, an SSO/admin profile for applying. Order matters; details in [docs/runbook.md](docs/runbook.md).

```bash
export AWS_PROFILE=<admin-profile>
(cd bootstrap && terraform init && terraform apply)    # 1. state bucket (local state)
(cd account   && terraform init && terraform apply -var alert_email=you@example.com)   # 2. guardrails
(cd envs/prod && terraform init && terraform apply)    # 3. shared network baseline
scripts/new-workload.sh my-site prod                   # 4. start a workload
```

Behind a TLS-inspecting proxy (Zscaler etc.): `export AWS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt`.

## Where things stand

The account already runs live workloads that were built by hand or with CDK/SAM. The plan to adopt them safely is in [docs/migration-plan.md](docs/migration-plan.md); what exists today is in [docs/current-state.md](docs/current-state.md).

## Docs

- [Architecture](docs/architecture.md) - how the pieces fit, isolation model
- [Cost](docs/cost.md) - budget, forbidden services, estimates
- [Security](docs/security.md) - baseline controls and known gaps
- [Runbook](docs/runbook.md) - apply order, adding envs/workloads, recovery
- [Migration plan](docs/migration-plan.md) - current to target state, cleanup list
- [SAA study map](docs/saa-study-map.md) - what each resource teaches
- [ADRs](docs/adr/) - why decisions were made
