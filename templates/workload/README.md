# Workload template

A serverless static site on S3 + CloudFront (Origin Access Control), with optional custom domain (ACM + existing Route 53 zone), optional VPC lookup, and an optional GitHub deploy role.

## Start a workload
```bash
scripts/new-workload.sh <name> <dev|prod>     # creates workloads/<name>
cd workloads/<name>
terraform init && terraform plan
```
The generator replaces `__WORKLOAD__`, sets the state key `workloads/<name>/<env>/terraform.tfstate`, and the env default.

## Checklist
- [ ] Shared baseline (`envs/<env>`) applied if you set `use_shared_vpc = true`.
- [ ] `account/` applied (permissions boundary exists) if you set `enable_deploy_role = true`.
- [ ] Custom domain: set `domain_name` and `hosted_zone_id` (the zone already exists; never create a second one).
- [ ] No secrets in `.tf` or tfvars. Use SSM Parameter Store/Secrets Manager by reference.
- [ ] Any new resource with a monthly cost is behind a variable defaulting to off and documented in `docs/cost.md`.
- [ ] Workload IAM roles attach `workload-permissions-boundary`.
- [ ] CloudWatch log groups have retention set.

## Files
| File | Purpose |
|---|---|
| `main.tf` | Backend, providers (incl. `us_east_1` alias for the certificate), locals |
| `variables.tf` | Inputs |
| `data.tf` | Reads the shared network contract from SSM (`/<env>/network/*`) |
| `site.tf` | Bucket, OAC, headers policy, distribution, ACM, DNS |
| `iam.tf` | Optional GitHub OIDC deploy role with boundary |
| `outputs.tf` | Bucket, distribution, URL |

## Deploying content
```bash
aws s3 sync ./dist s3://$(terraform output -raw site_bucket) --delete
aws cloudfront create-invalidation --distribution-id $(terraform output -raw cloudfront_distribution_id) --paths '/*'
```
In CI, use the deploy role via OIDC, not static keys.

## Adding a backend (serverless API)
Prefer Lambda outside the VPC behind an API Gateway **HTTP API** (cheaper than REST) or a Lambda function URL. Give the function its own role with the permissions boundary, set log retention, and put secrets in SSM SecureString. Put it in the VPC (`use_shared_vpc = true`, isolated subnets, `sg_app_id`) only when it must reach private resources.

## Photo-delivery notes
- Keep originals private; deliver through CloudFront. Private galleries: CloudFront signed URLs/cookies or short-lived presigned URLs from Lambda.
- Add an S3 lifecycle rule to transition large originals to `INTELLIGENT_TIERING` (see the comment in `site.tf`).
- Keep `price_class = PriceClass_100` unless you have international customers.
- No WAF by default (fixed cost). If abuse becomes real, add it deliberately with a budget.

## Adopting an existing site
Set `bucket_name` to the existing bucket, add `import {}` blocks, and iterate `terraform plan` until clean (see `docs/runbook.md`, "Adopt an existing resource").
