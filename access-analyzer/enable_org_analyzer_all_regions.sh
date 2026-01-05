#!/usr/bin/env bash
set -euo pipefail

# This script will:
# 1. Confirm you're running in the Organization management account.
# 2. Enable the Access Analyzer service for the Organization if not already enabled.
# 3. Create an organization-level analyzer in each enabled region (optional).

ORG_MASTER=$(aws organizations describe-organization --query 'Organization.MasterAccountId' --output text)
CURRENT=$(aws sts get-caller-identity --query Account --output text)

if [ "$ORG_MASTER" != "$CURRENT" ]; then
  echo "ERROR: You must run this from the Organization management account ($ORG_MASTER). Current account: $CURRENT" >&2
  exit 1
fi

echo "Running as management account: $CURRENT"

# Enable service access if not already
echo "Enabling Access Analyzer service access for the organization (idempotent)..."
aws organizations enable-aws-service-access --service-principal access-analyzer.amazonaws.com || true

# Confirm enabled
echo "Listing delegated administrators for Access Analyzer (if any):"
aws organizations list-delegated-administrators --service-principal access-analyzer.amazonaws.com || true

# List active regions (opt-in required regions excluded)
REGIONS=$(aws ec2 describe-regions --all-regions --filters Name=opt-in-status,Values=opt-in-not-required,opted-in --query "Regions[].RegionName" --output text)

for r in $REGIONS; do
  echo "--- Applying analyzer in region: $r ---"
  terraform -chdir="$(pwd)" init -input=false -reconfigure
  terraform -chdir="$(pwd)" apply -auto-approve -var="region=$r"
done

echo "Done."
