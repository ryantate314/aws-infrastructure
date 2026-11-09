# ADR 0001: Terraform state handling

**Status:** accepted (2026-11-09)

## Context
State must live somewhere before a remote backend exists, and the owner wants the bootstrap state committed to GitHub. Committed state is readable by anyone with repo access and its history is permanent, so it must hold no secrets or PII. Other roots (budgets with an email address, IAM, workloads) may contain sensitive-ish data.

## Decision
- `bootstrap/` uses **local state, committed**. It contains only a bucket and its settings (account ID and ARNs appear; they are identifiers, not credentials). No emails, tokens or passwords may ever be added to it.
- Everything else (`account/`, `envs/*`, `workloads/*`) uses the **S3 backend** with native locking (`use_lockfile`, Terraform >= 1.10), so no DynamoDB table is needed. State is never committed (enforced by `.gitignore`).
- State bucket encryption is **SSE-S3**, not a customer KMS key: it is free, and a key adds about $1/month plus key-policy complexity for state that is already access-controlled by IAM. Revisit if compliance requires KMS.
- Budgets, which need an email address, live in `account/`, not `bootstrap/`, for this reason.

## Consequences
- Bootstrap state is in git history forever: keep it minimal.
- Losing the S3 bucket loses state for the other roots; versioning (90 days) mitigates this, and `prevent_destroy` guards the bucket.
- Backend blocks cannot use variables, so the bucket name is hardcoded in each root and must match `bootstrap/variables.tf`.
