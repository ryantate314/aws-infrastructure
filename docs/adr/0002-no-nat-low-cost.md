# ADR 0002: No NAT Gateway; serverless-first, low fixed cost

**Status:** accepted (2026-11-09)

## Context
The account's spend is under $1/month and must stay low. NAT Gateways (~$32+/month each), interface endpoints (~$7/month per AZ), ALBs, WAF and similar services would multiply the bill with no workload that needs them. Current workloads are all Lambda/S3/CloudFront.

## Decision
- The baseline VPC has public and **isolated** subnets and the free S3/DynamoDB gateway endpoints. No NAT Gateway.
- Workloads default to **not using the VPC** (Lambda outside the VPC keeps internet access for free).
- Optional, default off: a `t4g.nano` fck-nat instance (~$3-4/month) and interface endpoints.
- The permissions boundary denies creation of the most expensive fixed-price services for workload roles.
- Site-to-Site VPN is not used for the homelab link: it costs about $36/month and does not support WireGuard. A WireGuard instance is the documented option.

## Consequences
- Anything inside an isolated subnet cannot reach the internet or most AWS APIs unless an optional toggle is enabled.
- A NAT instance is single-AZ and self-managed. Acceptable for a personal account; documented as a trade-off (also an exam topic).
