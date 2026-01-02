# Access Analyzer (Organization-level)

This module creates an AWS Access Analyzer at the organization level (type = ORGANIZATION).

Important:
- Must be run from the AWS Organization management account.
- Access Analyzer organization type is a global resource but must be created in a region; create it in an active region such as `us-east-1`.

Guard behavior:
- The module checks the current caller identity and the organization's master account id. If the module is not run from the management account, Terraform will fail early with a precondition error.

Enable across regions (variable-driven):
- The module now expects a single `region` argument and contains a `deploy_regions` variable in `variables.tf` which lists regions you want to process.
- Instead of provider aliasing inside Terraform, run the module once per region. Two helper scripts are provided to simplify this:
  - `run_access_analyzer_per_region.sh` (bash) — reads `deploy_regions` from `terraform.tfvars` (if present) or falls back to the default in `variables.tf`.
  - `run_access_analyzer_per_region.ps1` (PowerShell) — Windows-friendly equivalent.

Scripts behavior:
- For each region in `deploy_regions`, the script runs `terraform init` and then `terraform plan` or `terraform apply` with `-var="region=<region>"`.
- The module contains a guard that requires the Terraform caller to be the Organization management account; scripts will surface the guard failure and stop if not run from the management account.

Quick usage examples:

```bash
cd terraform/access-analyzer
chmod +x run_access_analyzer_per_region.sh
# Plan for all regions listed in terraform.tfvars or variables.tf
./run_access_analyzer_per_region.sh plan

# Apply to all regions (interactive)
./run_access_analyzer_per_region.sh apply

# Apply to all regions with auto-approve
./run_access_analyzer_per_region.sh apply --auto-approve
```

PowerShell example:

```powershell
cd terraform/access-analyzer
./run_access_analyzer_per_region.ps1 -Action apply -AutoApprove
```

Notes:
- Make sure the Access Analyzer service access for AWS Organizations is enabled in the management account before creating organization analyzers:

```bash
aws organizations enable-aws-service-access --service-principal access-analyzer.amazonaws.com
```

 - Module is organization-level: often a single analyzer suffices, but the per-region approach lets you create a presence in multiple regions where required by policy or audit.

aws organizations enable-aws-service-access \
  --service-principal access-analyzer.amazonaws.com
