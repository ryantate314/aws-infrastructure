# ADR 0004: Photos workload lives in its app repo; deploys are `make` from a laptop

**Status:** accepted (2026-11-09)

## Context
The photo site (Angular frontend, Lambda API, and its Terraform) is a single-owner project that changes together. `workloads/*` in this repo was the default home for workload roots. The two deploy options considered were a Makefile run locally and GitHub Actions auto-applying to prod on merge to `main`.

## Decision
- The `photos` workload's Terraform lives in `photo-delivery-site/infra/` (scaffolded with `scripts/new-workload.sh photos prod <dest>`). State still lives in this account's shared state bucket, key `workloads/photos/prod/terraform.tfstate`. Baseline roots (`bootstrap/`, `account/`, `envs/*`) and the template stay here.
- Deploys are Makefile-only (`make plan`, `make apply`, `make deploy-web`) using SSO. No GitHub Actions deploys and no OIDC for this repo (`enable_github_oidc` stays off).

## Consequences
- Hard rules 4 and 5 (a human reads plans that touch live resources; no applies unless asked) are enforced by the workflow itself: `make apply` only applies a fresh, saved plan after a typed confirmation.
- No CI trust surface; the `github-actions-apply` role (AdministratorAccess) stays unused.
- The app repo carries its own copy of the relevant hard rules in its `AGENTS.md`; drift between the two is a manual-review item.
- Revisit if there are other contributors. The safe first step then is a PR-time `plan` using the read-only `github-actions-plan` role, not auto-apply.
