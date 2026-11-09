# AGENTS.md

Instructions for AI coding agents working in this repo. Humans: see [README.md](README.md).

## What this repo is
Terraform for one personal AWS account (single account, regions `us-east-1` primary and `us-east-2` allowed). Roots: `bootstrap/`, `account/`, `envs/{dev,prod}`, `workloads/*` (from `templates/workload/`). Terraform >= 1.10, AWS provider `~> 6.0`.

## Hard rules (do not violate without the owner's explicit approval)
1. **Cost.** Never add NAT Gateways, Network Firewall, Transit Gateway, Client VPN, Site-to-Site VPN, ALB/NLB, OpenSearch, Redshift, ElastiCache, MSK, RDS/Aurora, interface VPC endpoints, WAF, or any other fixed-monthly-cost resource. Prefer Lambda (outside the VPC), S3, CloudFront, DynamoDB on-demand, API Gateway HTTP API. Anything optional that costs money must be a variable defaulting to off. Quote the monthly cost in the PR/summary for any new resource that has one.
2. **Secrets.** Never put secrets, tokens, keys, passwords, emails or other PII in `.tf`, `.tfvars` committed files, or `bootstrap/` state (it is committed). No IAM users or access keys: use SSO for humans and OIDC roles for CI. Use SSM Parameter Store or Secrets Manager only by reference.
3. **State.** `bootstrap/` uses local state, committed. Every other root uses the S3 backend and its state is never committed (`.gitignore` enforces this). Never run `terraform state rm`/`force-unlock`/`import` against live state without approval.
4. **Live resources.** The photo site and DNS are live. Never apply a plan that destroys or replaces an existing resource without the owner reading it. Do not import resources owned by CloudFormation (CDK/SAM stacks) while the stack exists.
5. **Never apply without being asked.** Running `terraform plan` is fine; `apply`/`destroy` and any AWS write need explicit instruction. Inventory work uses the read-only `inventory` SSO profile only.
6. **Account-wide S3 Block Public Access** (`enable_account_s3_public_access_block`) is `true`. Never make a bucket public; serve public content through CloudFront + OAC.

## Conventions
- Names: `${project-or-workload}-${env}-${purpose}`; the baseline uses `shared-${env}-*`. Lowercase, hyphens.
- Tags come from provider `default_tags` (Project, Workload/Component, Environment, ManagedBy). Do not hand-tag resources unless a resource type does not support default tags.
- Every S3 bucket: public access block (all four), `BucketOwnerEnforced`, SSE, TLS-only bucket policy, lifecycle rule (abort incomplete multipart, expire old versions/logs).
- Security groups: no `0.0.0.0/0` on SSH/RDP ever; administrative access is SSM Session Manager only. Reference security groups, not CIDRs, between tiers.
- IAM roles owned by workloads attach the permissions boundary `workload-permissions-boundary` (from `account/`).
- Workloads read network IDs from SSM parameters `/${env}/network/*`, not from remote state (see `envs/modules/baseline/main.tf`, `local.published`).
- CIDRs: dev `10.10.0.0/16`, prod `10.20.0.0/16`. Default VPCs use `172.31.0.0/16`. Reserve space for the homelab; confirm its ranges before adding a link.
- Use `check` blocks for cross-variable validation. Pin provider versions; commit `.terraform.lock.hcl`.
- Keep modules small. Prefer a variable-gated resource (`count`) over a forked module.

## Verify before finishing a change
```bash
terraform fmt -recursive
for d in bootstrap account envs/dev envs/prod templates/workload; do
  (cd $d && terraform init -backend=false -input=false && terraform validate); done
grep -rnE 'aws_nat_gateway|aws_networkfirewall|aws_lb\b|aws_wafv2' --include=*.tf . # expect no hits
```
Add/adjust docs in the same change: `docs/runbook.md` for procedures, `docs/cost.md` for anything with a price, an ADR in `docs/adr/` for a non-obvious decision.

## Environment notes
- The owner is often on a TLS-inspecting corporate proxy. If AWS CLI/Terraform fails with certificate errors, set `AWS_CA_BUNDLE`/`SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt`. Never disable TLS verification.
- Raw inventory output (`inventory/raw/`) contains account IDs and is git-ignored. Do not paste it into committed files; `docs/current-state.md` is the sanitized version.
- This account is also the AWS Organizations management account.

## Where to look
`docs/architecture.md` (design), `docs/cost.md` (budget/limits), `docs/security.md` (controls and gaps), `docs/runbook.md` (procedures), `docs/migration-plan.md` (what is being adopted/retired and in what order), `docs/current-state.md` (what exists now).
