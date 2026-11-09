#!/usr/bin/env bash
# Read-only AWS inventory (Phase 0 discovery).
# Uses ONLY describe/list/get calls. Never reads secret values (no Secrets Manager
# GetSecretValue, no SSM GetParameter --with-decryption, no access key material).
#
# Usage: AWS_PROFILE=readonly ./scripts/inventory.sh [output_dir]
# Output defaults to inventory/raw/ (git-ignored). Review before sharing; it contains
# account IDs and resource names.
set -uo pipefail

OUT="${1:-inventory/raw}"
mkdir -p "$OUT"
command -v aws >/dev/null || { echo "aws CLI not found" >&2; exit 1; }

export AWS_PAGER=""
run() { # run <outfile> <aws args...>
  local f="$OUT/$1.json"; shift
  if aws "$@" --output json >"$f" 2>"$f.err"; then
    [ -s "$f.err" ] || rm -f "$f.err"
  else
    echo "  (skipped/failed: aws $*)" >&2
  fi
}

echo "Identity..."
run identity sts get-caller-identity
run account-aliases iam list-account-aliases
run organizations organizations describe-organization

echo "Global services..."
run iam-account-summary iam get-account-summary
run iam-password-policy iam get-account-password-policy
run iam-users iam list-users
run iam-roles iam list-roles
run iam-credential-report-generate iam generate-credential-report
sleep 3
aws iam get-credential-report --query Content --output text 2>/dev/null | base64 -d >"$OUT/iam-credential-report.csv" 2>/dev/null || true
run s3-buckets s3api list-buckets
run route53-zones route53 list-hosted-zones
run route53domains route53domains list-domains --region us-east-1
run cloudfront-distributions cloudfront list-distributions
run budgets budgets describe-budgets --account-id "$(aws sts get-caller-identity --query Account --output text)"

echo "S3 bucket details..."
for b in $(aws s3api list-buckets --query 'Buckets[].Name' --output text 2>/dev/null); do
  d="$OUT/s3/$b"; mkdir -p "$d"
  for call in get-bucket-location get-bucket-versioning get-bucket-encryption \
              get-public-access-block get-bucket-policy-status get-bucket-lifecycle-configuration \
              get-bucket-logging get-bucket-tagging; do
    aws s3api "$call" --bucket "$b" --output json >"$d/$call.json" 2>/dev/null || rm -f "$d/$call.json"
  done
done

echo "Route 53 records..."
for z in $(aws route53 list-hosted-zones --query 'HostedZones[].Id' --output text 2>/dev/null); do
  zid="${z##*/}"
  run "route53-records-$zid" route53 list-resource-record-sets --hosted-zone-id "$zid"
done

echo "Cost (last 3 full months, by service)..."
START=$(date -u -d "$(date +%Y-%m-01) -3 month" +%F)
END=$(date -u +%Y-%m-01)
run cost-by-service ce get-cost-and-usage --time-period "Start=$START,End=$END" \
  --granularity MONTHLY --metrics UnblendedCost --group-by Type=DIMENSION,Key=SERVICE

echo "Regions..."
# Space-separated list; override with REGIONS="us-east-1 us-east-2 us-west-2" or REGIONS=all
REGIONS="${REGIONS:-us-east-1 us-east-2}"
if [ "$REGIONS" = "all" ]; then
  aws ec2 describe-regions --query 'Regions[].RegionName' --output text 2>/dev/null | tr '\t' '\n' >"$OUT/regions.txt"
else
  tr ' ' '\n' <<<"$REGIONS" >"$OUT/regions.txt"
fi

while read -r r; do
  echo "Region $r..."
  d="$OUT/regions/$r"; mkdir -p "$d"
  rr() { local f="$d/$1.json"; shift; aws "$@" --region "$r" --output json >"$f" 2>/dev/null || rm -f "$f"; }
  rr vpcs ec2 describe-vpcs
  rr subnets ec2 describe-subnets
  rr route-tables ec2 describe-route-tables
  rr security-groups ec2 describe-security-groups
  rr network-acls ec2 describe-network-acls
  rr internet-gateways ec2 describe-internet-gateways
  rr nat-gateways ec2 describe-nat-gateways
  rr vpc-endpoints ec2 describe-vpc-endpoints
  rr vpn-connections ec2 describe-vpn-connections
  rr vpn-gateways ec2 describe-vpn-gateways
  rr peering ec2 describe-vpc-peering-connections
  rr flow-logs ec2 describe-flow-logs
  rr instances ec2 describe-instances
  rr volumes ec2 describe-volumes
  rr addresses ec2 describe-addresses
  rr load-balancers elbv2 describe-load-balancers
  rr lambda lambda list-functions
  rr apigw-rest apigateway get-rest-apis
  rr apigw-http apigatewayv2 get-apis
  rr rds rds describe-db-instances
  rr dynamodb dynamodb list-tables
  rr acm acm list-certificates
  rr kms kms list-keys
  rr cloudtrail cloudtrail describe-trails
  rr guardduty guardduty list-detectors
  rr config-recorders configservice describe-configuration-recorders
  rr secrets-metadata secretsmanager list-secrets   # metadata only, no values
  rr ssm-parameters-metadata ssm describe-parameters # metadata only, no values
  rr cloudformation-stacks cloudformation describe-stacks   # CDK/SAM ownership matters before any terraform import
  rr access-analyzers accessanalyzer list-analyzers
  rr ecs ecs list-clusters
  rr cw-log-groups logs describe-log-groups
done <"$OUT/regions.txt"

# Drop empty files so only populated results remain.
find "$OUT" -type f -size 0 -delete
echo "Done. Output in $OUT (git-ignored). Do not commit raw output."
