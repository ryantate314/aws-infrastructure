#!/usr/bin/env bash
# Create a new workload root from templates/workload.
# Usage: scripts/new-workload.sh <name> [dev|prod]
set -euo pipefail

name="${1:-}"
env="${2:-prod}"

if [[ ! "$name" =~ ^[a-z][a-z0-9-]{1,30}$ ]]; then
  echo "usage: $0 <name> [dev|prod]   (name: lowercase letters, digits, hyphens)" >&2
  exit 1
fi
[[ "$env" == "dev" || "$env" == "prod" ]] || { echo "env must be dev or prod" >&2; exit 1; }

root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$root/workloads/$name"
[[ ! -e "$dest" ]] || { echo "$dest already exists" >&2; exit 1; }

mkdir -p "$root/workloads"
cp -R "$root/templates/workload" "$dest"
rm -rf "$dest/.terraform" "$dest/.terraform.lock.hcl"

# Placeholders: name, and the state key / default env.
sed -i "s/__WORKLOAD__/$name/g" "$dest"/*.tf
sed -i "s#workloads/$name/prod/terraform.tfstate#workloads/$name/$env/terraform.tfstate#" "$dest/main.tf"
sed -i "/variable \"env\"/,/^}/ s/default     = \"prod\"/default     = \"$env\"/" "$dest/variables.tf"

echo "Created $dest (env=$env)."
echo "Next: cd workloads/$name && terraform init && terraform plan   (see README.md there)"
