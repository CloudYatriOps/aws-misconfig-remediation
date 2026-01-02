# ECR Scan module

Configures registry-level ECR scanning behavior. This module does not create repositories — repositories must already exist or be managed separately.

Usage:

1. Add repository names in `terraform.tfvars` or pass them as variables.
2. Run:

```bash
terraform init
terraform plan
terraform apply
```

Variables:
- `repositories`: list of repo names.
 - `registry_scan_type`: BASIC or ENHANCED.
 - `basic_scan_frequency`: frequency used when `registry_scan_type` is `BASIC` (default `SCAN_ON_PUSH`).
 - `enhanced_scan_frequency`: frequency used when `registry_scan_type` is `ENHANCED` (default `CONTINUOUS`).

Behavior:
 - `ENHANCED`: continuously scan all repositories (uses `enhanced_scan_frequency`).
 - `BASIC`: scan on push for all repositories (uses `basic_scan_frequency`).
