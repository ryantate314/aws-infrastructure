# SAA study map

Each building block here maps to exam concepts (SAA-C03). Use it as lab prompts: change a toggle, run `terraform plan`, explain what changes and what it costs.

| Resource (path) | Concepts | Exam angle / experiment |
|---|---|---|
| VPC, subnets, route tables (`envs/modules/baseline`) | VPC design, CIDR planning, public vs private subnets, multi-AZ | Why `/24` per subnet per AZ? What makes a subnet "public"? (the IGW route, not the name) |
| Isolated tier with no internet route | Network segmentation, least exposure | Private subnet access to S3 without NAT |
| S3 + DynamoDB gateway endpoints | VPC endpoints: gateway vs interface (PrivateLink) | Gateway = free, route-table based; interface = ENI, paid. Prefix lists in SG rules |
| `enable_nat_instance` | NAT Gateway vs NAT instance, source/dest check, cost/availability trade-off | Why a NAT instance is single-AZ and not highly available |
| Security groups chained by reference | Stateful vs stateless; SG vs NACL | Ingress from `web` SG only; compare with NACL behaviour |
| Flow logs to S3 | Monitoring, troubleshooting connectivity, log destinations | S3 vs CloudWatch Logs cost; Athena over flow logs |
| `bootstrap/` state bucket | S3 versioning, SSE, bucket policy (`aws:SecureTransport`), lifecycle, Block Public Access | Restore a deleted state version; why BucketOwnerEnforced disables ACLs |
| `account/cloudtrail.tf` | CloudTrail, management vs data events, log validation, org vs single trail | Find who changed a security group in event history |
| `account/iam.tf` boundary | Permissions boundaries, explicit deny, SCP vs boundary, policy evaluation logic | Why an explicit Deny wins; why `NotAction` + region condition |
| GitHub OIDC roles | Federation, STS `AssumeRoleWithWebIdentity`, trust policies, no long-lived keys | Compare with an IAM user's access keys |
| Identity Center permission sets | SSO, temporary credentials, least privilege for humans | Read-only role vs admin role |
| Budgets, Cost Anomaly Detection | Cost optimization, governance | Forecasted vs actual alerts |
| Access Analyzer, password policy | Security posture, external access findings | Make a bucket public in a sandbox and see the finding |
| Workload: S3 + CloudFront OAC | CDN, OAC vs OAI, origin access, edge caching, TLS, ACM in us-east-1 | Why the cert must be in us-east-1; cache policy vs origin request policy |
| Response headers policy | Web security headers, HSTS | |
| Route 53 alias records | Alias vs CNAME, apex records, DNS validation | Why an alias is allowed at the apex |
| SSM Parameter Store contract | Decoupling, config management, parameter tiers | Parameter Store vs Secrets Manager (cost and rotation) |
| Lambda + API Gateway (photo site) | Serverless, REST vs HTTP API, authorizers, cold starts | Memory vs cost, arm64 savings |
| DynamoDB on-demand | NoSQL, capacity modes, partition keys | On-demand vs provisioned break-even |
| Multi-account path (ADR 0003) | Organizations, SCPs, Control Tower | Move prod to a member account |

## Suggested labs
1. Enable `interface_endpoint_services = ["ssm"]` in dev, plan, read the cost, then remove it.
2. Turn on `enable_nat_instance` in dev, put a test instance in an isolated subnet, observe egress, tear down.
3. Break a security group rule on purpose and use flow logs to diagnose it.
4. Write an SCP-style deny in the boundary and prove it with `aws iam simulate-principal-policy`.
5. Restore a prior version of a state file from S3 versioning.
