# ADR 0003: Single account, isolation by convention and IAM

**Status:** accepted (2026-11-09)

## Context
The account is already the AWS Organizations management account (all features enabled, IAM Identity Center in use). Best practice is to keep workloads out of the management account and use separate accounts per environment. Member accounts are free, but add switching overhead, and the owner has one small account today.

## Decision
Stay with one account. Isolate with per-env VPCs and CIDRs, separate state per root, workload roles under a permissions boundary, OIDC roles scoped by repo and branch, and tagging.

## Consequences
- A compromise of the account is a compromise of everything; mitigations are MFA, no static keys, CloudTrail, budget alerts, and boundaries.
- Migration path (also good exam practice): create member accounts (`prod`, `dev`, `security/logging`), move `envs/prod` and workloads, move CloudTrail to an org trail, add SCPs (region and service denies) and Identity Center assignments per account. Terraform roots are already split by env, so the move is mostly new provider configs and state moves.
