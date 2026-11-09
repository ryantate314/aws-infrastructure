# Current State (inventory of 2026-11-09)

Source: `scripts/inventory.sh` run with a read-only role (`ViewOnlyAccess` + `SecurityAudit`) against `us-east-1` and `us-east-2` only. Account ID, org ID, IP addresses and resource IDs are redacted. Raw output lives in git-ignored `inventory/raw/`.

**Not covered:** other regions (assumed empty), Organizations member accounts, ENI attachments, IAM role/policy contents, Lambda env vars/function URLs, CloudFront config details, S3 object contents/sizes. Re-run with `REGIONS=all` to verify the "nothing elsewhere" assumption.

## Summary
- **One AWS account**, which is also the Organizations management account (all features enabled). IAM Identity Center is in use (`ReadOnlyInventory` permission set).
- **Spend: about $0.60/month** (Route 53 hosted zone about $0.51, S3 about $0.07). Essentially free today.
- **Fully serverless already.** No EC2, RDS, NAT gateways, load balancers, VPN or VPC endpoints. The existing VPCs are only the default VPCs.
- **No Terraform yet.** Workloads are deployed by hand, by CDK/SAM (CloudFormation), and by CodeBuild/CodePipeline.

## Inventory

### DNS / domains
- Registered domain `ryantate314.net` (Route 53 Domains, auto-renew on, expires 2027-01).
- One public hosted zone (13 records after the apex `A` removal; the list below is from the original inventory):
  - apex: no record (the `A` to the S3 website endpoint was deleted 2026-11-09)
  - `photos` → CloudFront
  - `photos2` → CloudFront (its ACM cert is EXPIRED)
  - `worktimer` → API Gateway custom domain
  - `prem` and `vpn` → homelab addresses (updated by the DDNS stack)
  - ACM validation CNAMEs

### Workloads (all `us-east-1`)
| Workload | Components | Managed by |
|---|---|---|
| **Photo delivery** (`photos.ryantate314.net`) | CloudFront → S3 `photos.ryantate314.net`; API Gateway REST `photos-ryantate314` and `photos-ryantate314-net`; 3 Lambdas (nodejs22); IAM user `photosite-uploader` | Console / manual (the Lambdas were updated 2026-10-15) |
| **Legacy apex site** | S3 `ryantate314.net` with website hosting, **public-read policy**. As of 2026-11-09 the owner emptied and **deleted** it and removed the apex `A` record (apex now resolves to nothing). | Done |
| **ddns** (homelab dynamic DNS) | Lambda `ddns-updater` + API `ddns-api`; CDK `DyndnsStack` (Lambda, DynamoDB) | Mixed: CDK stack and a newer manual Lambda/API (2026-04) |
| **worktimer** | Lambda authorizer, API `work-timer`, DynamoDB `worktimer`, ACM cert, IAM user `worktimer-client` | Manual |
| **chore-board** | SAM stack, Lambda, EDGE API Gateway; an RDS cluster once existed (log group remains) | SAM / CloudFormation |
| **glider-view** | Only leftovers: CodeBuild/CodePipeline roles and log groups | Abandoned? |
| **docker-demo-app** (`us-east-2`) | Failed stack in `ROLLBACK_COMPLETE` (2023) | Abandoned |
| CDK / SAM tooling | `CDKToolkit`, `aws-sam-cli-managed-default` stacks, 2 buckets, SSM bootstrap version param | CloudFormation |

Other S3 buckets: `backup.ryantate314` (private, SSE-S3, unversioned).

### Networking
- Only the **default VPC** in each region (`172.31.0.0/16`, default subnets, IGW). This is the CIDR of the default VPC; any future VPC must not overlap it.
- 9 security groups in `us-east-1`, 8 non-default: several `launch-wizard-*`, `SSH-Proxy`, `dmz`. They open 22 and/or 80/443 to `0.0.0.0/0`. **No EC2 instances exist**, so they are probably orphaned (ENI attachments not checked).
- No flow logs, endpoints, peering or VPN.

### IAM
- 8 IAM users, 0 groups, 38 roles. Root has MFA on and no access keys.
- `admin` is the only console user (MFA on, used today).
- 6 users with **long-lived access keys**: `dev-gliderview` (last used 2024-04), `PowerUser` (2024-07), `home-proxy-caddy`, `photosite-uploader` (used 2026-10), `s3-cli-user` (**2 active keys**, MFA enabled but no console), `worktimer-client` (key **never used**).
- `developer-bob`: no keys, no console, so it is dead.
- **No account password policy.**

### Security services / logging
- **No CloudTrail trail** (only 90-day event history), no GuardDuty, no AWS Config, no Access Analyzer.
- 15 CloudWatch log groups in `us-east-1`; about 9 have **no retention set** (never expire), including stale ones (`glider-view` CodeBuild, `chore-board` RDS, `nginx-demo` ECS).
- Budgets: a single `$1 Warning` budget with a $5 monthly limit.

### S3 posture
- 4 of 5 buckets have all four public-access blocks on and default encryption (SSE-S3 or KMS).
- `ryantate314.net` has **no public-access block** and is public by policy. Intended for website hosting, but HTTP only.
- Versioning is on for the CDK and SAM buckets only. `photos.ryantate314.net` and `backup.ryantate314` are unversioned.

## Gap analysis vs target

| Area | Current | Target | Priority |
|---|---|---|---|
| IaC | None, plus CDK/SAM stacks | Terraform for shared infra and new workloads; leave CDK/SAM stacks until retired | High |
| State | n/a | Bootstrap S3 bucket (local state) + S3 remote state | High |
| Cost guardrails | $5 budget only | Budget plus Cost Anomaly Detection | High (cheap) |
| Audit | No CloudTrail | First management-events trail (free) | High |
| IAM | 6 static-key users, no password policy | OIDC/SSO only, delete unused keys/users | High |
| Edge/TLS | Legacy apex bucket public over HTTP (no real content) | Replace with the marketing site on CloudFront + OAC + HTTPS, delete the old bucket | Medium |
| Networking | Default VPCs, orphan open SGs | New baseline VPC (no NAT). Delete orphan SGs after verifying no ENIs | Medium (VPC is only needed once a workload requires one) |
| Logging hygiene | Many logs never expire | 14-30 day retention | Low (pennies) |
| Cleanup | Dead stacks/roles/users/cert | Remove after verification | Low |

**Observation:** nothing here currently needs a VPC (all Lambdas are outside any VPC). Since the constraint is cost and serverless-first, the `envs` baseline should stay minimal: a VPC costs $0 but is only useful once a workload needs one, and endpoints/NAT are paid add-ons.

## Risks for migration
1. **Terraform vs CloudFormation ownership.** CDK/SAM-owned resources (`DyndnsStack`, `chore-board`) must not be imported into Terraform while CloudFormation still owns them. Plan: leave in place and retire/redeploy later, or import only after deleting the stack with `DeletionPolicy: Retain`.
2. **Photo site is live.** The manually built resources are the best import candidates (CloudFront, S3, API Gateway, Lambdas, Route 53 records). Keep zero-diff `plan` as the gate.
3. **Route 53 hosted zone and domain** are critical. Import the zone, never recreate it, since name servers would change.
4. **Static access keys** (`photosite-uploader`, `s3-cli-user`) are in use somewhere. Rotate/replace only after finding the consumers.
5. **Management account is also the workload account.** Fine for a personal setup (recorded in an ADR), but the permission set for Terraform must be scoped sensibly.
