# Cost

**Today:** about $0.60/month (Route 53 zone $0.51, S3 ~$0.07). **Target ceiling:** about $5/month. Budget alert at $10/month (`account/`), plus the existing manual $5 budget.

## What this repo adds
| Item | Monthly | Notes |
|---|---|---|
| State bucket, CloudTrail bucket | pennies | Lifecycle rules cap growth; trail is the free first copy of management events |
| Budgets (first 2 free), Cost Anomaly Detection, Access Analyzer (account) | $0 | |
| VPC, subnets, IGW, route tables, SGs, S3/DynamoDB gateway endpoints | $0 | |
| SSM standard parameters | $0 | |
| VPC Flow Logs to S3 (prod only) | pennies idle | 30-day expiry |
| CloudFront + S3 workload | pay per use | Free tier: 1 TB egress + 10M requests/month |

## Forbidden by default (do not add without explicit approval)
| Service | Approx. cost | Cheaper alternative |
|---|---|---|
| NAT Gateway | $32+/mo per AZ | Run Lambda outside the VPC; or the optional fck-nat instance (~$3-4/mo) |
| Network Firewall | $270+/mo | Security groups; CloudFront; (WAF only if truly needed) |
| Site-to-Site VPN / Client VPN | $36+/mo | WireGuard on a t4g.nano |
| ALB / NLB | $16+/mo | CloudFront + API Gateway / Lambda function URL |
| Interface VPC endpoints | ~$7/mo per AZ each | Gateway endpoints (free); Lambda outside VPC |
| WAF | $5/mo + rules + requests | CloudFront security headers, rate limiting in the app |
| RDS / Aurora, ElastiCache, OpenSearch, MSK, Redshift | $15-$100s/mo | DynamoDB on-demand, S3 |
| Transit Gateway, Direct Connect | $36+/mo | n/a |
| Customer-managed KMS keys | $1/mo each | SSE-S3 (free) unless a requirement demands KMS |

The permissions boundary (`account/iam.tf`) denies creation of the most expensive ones for workload roles, but it is a backstop, not a substitute for review.

## Optional toggles (all default off)
- `enable_nat_instance` (baseline): t4g.nano fck-nat, about $3-4/mo, single AZ.
- `interface_endpoint_services` (baseline): about $7/mo per service per AZ (2 AZs: about $14/mo per service).
- `enable_flow_logs`: negligible, but traffic-dependent.

## Habits
- Review Cost Explorer monthly (group by service). Delete idle logs/stacks.
- Set CloudWatch log retention (14-30 days). Unbounded log groups quietly grow.
- Check `aws ec2 describe-nat-gateways` / unattached EIPs / idle load balancers after experiments.
