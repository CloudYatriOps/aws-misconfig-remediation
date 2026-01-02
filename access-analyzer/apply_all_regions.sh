#!/usr/bin/env bash
# List enabled regions and run terraform apply in each (optional).
set -euo pipefail

# This script assumes AWS CLI is configured for the management account.
regions=$(aws ec2 describe-regions --all-regions --filters Name=opt-in-status,Values=opt-in-not-required,opted-in --query "Regions[].RegionName" --output text)
for r in $regions; do
  echo "Applying in region: $r"
  terraform -chdir="$(pwd)" init -input=false -reconfigure
  terraform -chdir="$(pwd)" apply -auto-approve -var="region=$r"
done
