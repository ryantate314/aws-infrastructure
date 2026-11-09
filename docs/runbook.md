# Runbook

Prereqs: Terraform >= 1.10, AWS CLI v2, an SSO profile with rights to create IAM, S3, CloudTrail, Budgets (the `ReadOnlyInventory` profile is read-only and cannot apply). Behind Zscaler or similar, set `AWS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt`.

## Apply order (first time)
1. **`bootstrap/`**: local state, creates the state bucket.
   ```bash
   cd bootstrap && terraform init && terraform plan && terraform apply
   git add terraform.tfstate && git commit   # state is committed on purpose; it contains no secrets
   ```
2. **`account/`**: needs `alert_email` (not committed anywhere):
   ```bash
   cd account && terraform init && TF_VAR_alert_email=you@example.com terraform plan
   ```
   Optional: `-var enable_github_oidc=true -var github_repo=<owner>/<repo>`. The account-wide S3 public-access block is on by default (the legacy public bucket is gone; re-run `scripts/inventory.sh` first if you have added public buckets since).
3. **`envs/prod`** (and `envs/dev` when needed): `terraform init && terraform plan && terraform apply`.
4. **Workloads**: `scripts/new-workload.sh <name> <env>` then see `workloads/<name>/README.md`.

Always read `terraform plan` before `apply`. Anything that shows `destroy` or `must be replaced` on an existing resource stops the process.

## Add an environment
Copy `envs/prod` to `envs/<name>`, change the state `key`, the `env` value, tags, and pick a non-overlapping `/16`. Keep the optional toggles off.

## Add a workload
`scripts/new-workload.sh blog dev`, edit `variables.tf` defaults (domain, zone ID), `terraform init && terraform plan`. If the workload sits in the VPC set `use_shared_vpc = true`; it reads `/<env>/network/*` from SSM.

## Adopt an existing resource (import)
1. Write the resource block that matches reality. Add an `import { to = ..., id = ... }` block.
2. `terraform plan` until it shows no changes (or only intended ones). Fix the HCL, not the resource.
3. Apply only a no-op import, then remove the `import` block. Never import something CloudFormation owns while its stack exists.

## State
- Bucket versioning keeps 90 days of state versions. Recover by restoring a previous object version of `.../terraform.tfstate`.
- Locking uses an S3 lockfile (`*.tflock`). If a run crashed: `terraform force-unlock <ID>` only after confirming no run is active.
- Bootstrap state is in git history. Everything else is only in S3.

## Rotate / revoke
- **Human access:** IAM Identity Center; remove the assignment to revoke.
- **CI:** delete or edit the `github-actions-*` role trust policy in `account/iam.tf`.

## Destroy
Reverse order: workloads, envs, account, bootstrap last. The state bucket has `prevent_destroy` and must be emptied (including versions) by hand. Do not destroy anything you did not create with Terraform.

## Tooling checks
```bash
terraform fmt -recursive -check
# pre-commit: see .pre-commit-config.yaml (fmt, validate, gitleaks)
```

## Common failures
| Symptom | Fix |
|---|---|
| `x509: certificate signed by unknown authority` / `CERTIFICATE_VERIFY_FAILED` | Corporate TLS inspection. `export AWS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt` |
| `NoSuchBucket` on `terraform init` | Run `bootstrap/` first, or the bucket name differs from `backend.tf` |
| `ExpiredToken` | `aws sso login --profile <profile>` |
| Budgets/Cost Explorer `AccessDenied` | Enable "IAM user and role access to Billing information" in account settings |
