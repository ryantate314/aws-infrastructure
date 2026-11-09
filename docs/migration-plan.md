# Migration plan: current state to target state

Baseline facts are in [current-state.md](current-state.md). Strategy: **import in place, then converge**. The photo site stays live throughout; every phase has a rollback and a "site still works" gate. Nothing below is executed until the owner says so.

Decisions so far (2026-11-09): retire `worktimer` and `chore-board`; clean up all old hello-world projects; `dyndns` is live and needs investigation first; scope regions to `us-east-1` and `us-east-2`.

## M0. Safety net (no changes to live resources)
- [ ] Export Route 53 zone records (`aws route53 list-resource-record-sets`) to a private location.
- [ ] Confirm break-glass: root MFA works; `admin` console user with MFA works.
- [ ] Enable versioning on `photos.ryantate314.net` and `backup.ryantate314` only after checking storage cost impact (versioning on a large photo bucket increases cost on overwrites).
- [ ] Note the live consumers of the static keys (see M5).

## M1. Bootstrap and guardrails (additive only) - APPLIED 2026-11-09
Verified read-only after apply: state bucket exists and holds `account/terraform.tfstate`; bootstrap state committed and scanned clean (no secrets/PII); CloudTrail logging with no delivery errors; budget `monthly-cost` ($10) alongside the old `$1 Warning`; password policy, Access Analyzer, account-level S3 public-access block, EBS default encryption and the `workload-permissions-boundary` policy all present. GitHub OIDC not enabled (default). Not verifiable with the read-only role: the Cost Anomaly monitor/subscription.
1. Apply `bootstrap/` (new state bucket).
2. Apply `account/` (budget, anomaly alerts, CloudTrail, password policy, Access Analyzer, permissions boundary; OIDC if wanted). Leave the account S3 public-access block **off**.
- Verify: `terraform plan` clean on re-run; first CloudTrail log object appears; test budget email arrives.
- Rollback: `terraform destroy` in `account/` (state bucket untouched).
- Cost delta: pennies.

## M2. Shared baseline (additive only)
Apply `envs/prod` (`10.20.0.0/16`, new VPC beside the default). Nothing existing uses it yet. Apply `envs/dev` only when a workload needs it.
- Cost delta: $0 (flow logs add pennies).

## M3. Adopt the photo-delivery site
**Decisions (2026-11-09):** the workload lives in the app repo (`photo-delivery-site/infra`, see ADR 0004) and deploys with `make` (no CI). The site is console-built (no CDK/SAM/CloudFormation), so everything is imported in place. Read-only inventory is in `docs/current-state.md` ("Photo site detail").

Order:
1. **Adopt the existing stack unchanged** (`infra/` in the app repo, import blocks, no-op apply): S3 bucket `photos.ryantate314.net` (policy, public-access block, SSE), CloudFront distribution and OAC, ACM cert and its validation record, the `photos` A/AAAA records, the Lambda role and logging policy, the two live Lambdas, and the live REST API `photos-ryantate314-net` (stage `api`). The hosted zone is looked up by name, never created or imported. Not adopted (to delete later): the legacy REST API `photos-ryantate314`, the Lambda `photos-ryantate314`, `photos2` records and cert.
2. **Deploy the existing code from the repo:** the first apply also updates the two Lambdas' code from `api/` and `make deploy-web` ships the Angular build.
3. **Then** replace the API with a DynamoDB-backed index (HTTP API + single Lambda + indexer), cut CloudFront `/api/*` over, and retire the old REST API, Lambdas and `photosite-uploader` (the upload process may change destructively).

**Status 2026-11-09:** steps 1 and 2 (Terraform adoption and Lambda code from the repo) are APPLIED by the owner; the follow-up `terraform plan` shows no changes and the live site and API respond normally. `make deploy-web` (content sync) is not yet exercised. Step 3 (DynamoDB rewrite) is not started.

Gate: `terraform plan` shows only reviewed, intended diffs and no replace/destroy. Intended diffs in step 1: default tags on adopted resources, 14-day retention on the one log group without retention, an abort-incomplete-multipart lifecycle rule, a TLS-only deny statement in the bucket policy, and the Lambda code update. Everything else (headers policy, TLS minimum, price class, OAC name) is a later, separate change.
- Rollback: `terraform state rm` the adopted resource (does not touch AWS) and revert; owner approval required for state surgery.

## M4. Marketing site and apex bucket
The legacy bucket `ryantate314.net` held only a 2023 timezone-test `index.html`. **Done by the owner on 2026-11-09 (verified read-only):** the apex `A` record was deleted and the bucket emptied. The apex currently resolves to nothing (only NS/SOA remain); no graceful changeover is needed.

Remaining:
1. ~~Delete the empty `ryantate314.net` bucket.~~ Done by the owner (verified 2026-11-09). All four remaining buckets have full public-access blocks, so `enable_account_s3_public_access_block` now defaults to `true` in `account/`.
2. Create `workloads/marketing` from the template with `domain_name = "ryantate314.net"` and the existing hosted zone ID (new private bucket, CloudFront + OAC, HTTPS, ACM cert). The apex alias records are created by Terraform, so the plan should show only new records.
3. Upload content (a placeholder is fine) and confirm it loads.
- Rollback: none needed; there is nothing to roll back to.

## M5. Identity cleanup
| Item | Action |
|---|---|
| `photosite-uploader` (key used 2026-10-04) | Find the consumer; replace with the OIDC deploy role (`enable_deploy_role`); deactivate key, wait, delete |
| `s3-cli-user` (2 active keys, used 2026-10-16) | Find consumers; replace with SSO; remove the unused key now, then the user |
| `home-proxy-caddy` (key used 2026-01-09) | Find the consumer on the homelab; scope or replace. Lead: a customer-managed policy `ryantate314-letsencrypt` exists, likely Route 53 DNS-challenge permissions for Caddy certificates; check that policy's scope (should be limited to this zone's TXT records) before rotating the key |
| `dev-gliderview`, `PowerUser` (last used 2024) | Deactivate keys, wait 30 days, delete user |
| `developer-bob` (no keys, no console) | Delete |
| `worktimer-client` | Deleted with worktimer |
Method: deactivate first (reversible), watch for failures for ~30 days, then delete. CloudTrail from M1 gives the evidence of who still uses what.

## M6. Retire and clean up (each item needs explicit approval; verify first)
Old hello-world and abandoned projects:

| Project | Resources to remove |
|---|---|
| **chore-board** (retire) | CloudFormation stack `chore-board` (Lambda, EDGE API Gateway, role); `/aws/lambda/chore-board-*` and `/aws/rds/cluster/chore-board/*` log groups; confirm no RDS snapshots remain |
| **SAM tooling** | Stack `aws-sam-cli-managed-default` and its bucket (only after chore-board is gone) |
| **worktimer** (retire) | API `work-timer`, custom domain, Lambda authorizer and role, DynamoDB table `worktimer`, ACM cert `worktimer.ryantate314.net`, DNS records (`worktimer` A and its validation CNAME), user `worktimer-client`, roles `AR-worktimer-apigateway` |
| **glider-view** | Roles `glider-view`, `AWSCodePipelineServiceRole-us-east-1-glider-view`, `codebuild-glider-view.*`, `cwe-role-us-east-1-glider-view`, `AwsCodeDeploy`; log groups `/aws/codebuild/glider-view_*`; check for CodeBuild/CodePipeline projects that remain |
| **docker-demo-app** (`us-east-2`) | Stack `Infra-ECS-Cluster-docker-demo-app-*` (`ROLLBACK_COMPLETE`); `/ecs/nginx-demo` log group; `ecsTaskExecutionRole`, `rds-monitoring-role` if unused |
| **Misc hello-world** | Roles `TestFunction-role-*`, `web-server`, `Developer`; `photos2` ACM cert (expired) and `photos2` DNS records; `/aws/apigateway/welcome` log group |
| **Orphan SGs** | `launch-wizard-1..5`, `SSH-Proxy`, `dmz`, `internal-instances` in the default VPC, after confirming no ENI uses them |
| **Log hygiene** | Set 14-30 day retention on every remaining log group |

Before deleting anything: confirm last-use (CloudTrail, CloudWatch invocation metrics), take a final export if data matters (DynamoDB `worktimer`), and delete CloudFormation-owned resources by deleting the stack rather than individually. Keep the `CDKToolkit` stack until `dyndns` is resolved.

## Investigation: dyndns (live, do not touch yet)
Two overlapping implementations appear to exist:
- CDK stack `DyndnsStack` (June 2025): Lambda `DyndnsStack-dyndnsfn-*` (arm64, python3.13) + DynamoDB table.
- Manual `ddns-updater` Lambda (python3.12) + REST API `ddns-api` (April 2026), plus role `ddns-lambda`.
The DNS names `prem` and `vpn` point at homelab addresses and are the likely things being updated.
Read-only investigation steps:
1. CloudTrail event history for `ChangeResourceRecordSets` (90 days): which role/Lambda updates `prem` and `vpn`, and how often.
2. CloudWatch Logs and invocation metrics for both Lambdas and `ddns-api` (last invocation).
3. Lambda configs/roles (env vars and the Route 53 permission scope; read env var *names*, not values).
4. Find the caller on the homelab (router/script/`home-proxy-caddy` user) and which endpoint URL it uses.
5. Decide: keep the newer manual one or the CDK one; document the final design.
Then rebuild as a Terraform workload (Lambda + Function URL or HTTP API, DynamoDB on-demand if state is needed, least-privilege Route 53 policy on that one zone, auth token in SSM SecureString), cut the homelab client over, and retire the loser. Keep `CDKToolkit` until the CDK stack is deleted.

## Final state checklist
- [ ] All Terraform roots plan clean.
- [ ] No IAM users with keys; no CloudFormation stacks other than ones deliberately kept.
- [ ] Apex site on CloudFront; account-level Block Public Access on.
- [ ] Monthly cost still under $5 (Cost Explorer).
