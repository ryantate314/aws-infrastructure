# bootstrap

Creates the S3 bucket that stores Terraform state for every other root. This is the **only** root with local state, and `terraform.tfstate` here **is committed to git**.

**Never add secrets or PII to this root** (emails, tokens, passwords, keys). Put anything like that in `account/` (remote, uncommitted state).

```bash
terraform init
terraform plan
terraform apply
git add terraform.tfstate .terraform.lock.hcl && git commit -m "bootstrap state"
```

Creates one bucket: versioned, SSE-S3, all public access blocked, ownership enforced, TLS-only policy, 90-day expiry of old versions, `prevent_destroy`. Locking uses S3 lockfiles, so there is no DynamoDB table. Rationale: [ADR 0001](../docs/adr/0001-state-handling.md).

The bucket name (`ryantate314-tfstate`) is hardcoded in the `backend` block of each other root. If you change it here, change it there.
