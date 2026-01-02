# aws-misconfig-remediation — CI for Terraform modules

This repository contains small Terraform modules (one per folder) and GitHub Actions workflows to run `terraform init/ fmt/ validate/ plan` on push to `main`, with optional manual `apply` using GitHub Environments and OIDC.

Quick summary
- Each module lives in its folder (e.g., `secrets-manager-rotation`).
- Workflows are in `.github/workflows/`.
- A reusable workflow `terraform-reusable.yml` performs plan and apply logic; per-module workflows call it.

Running from the GitHub UI
- To run plan automatically: push changes to `main` in the module folder (the workflow triggers and uploads a plan artifact).
- To run apply: go to Actions → choose the module workflow → Run workflow → set `apply=true` and optionally `oidc_role_arn` (or rely on repo secret `OIDC_ROLE_ARN`). The apply job will wait for environment approval.

Running via GH CLI
Example (plan + apply via OIDC role):
```bash
gh workflow run .github/workflows/terraform-secrets-manager-rotation.yml \
  --ref main \
  -f apply=true \
  -f terraform_version=1.5.7 \
  -f aws_region=us-east-1 \
  -f apply_environment=terraform-apply \
  -f oidc_role_arn=arn:aws:iam::123456789012:role/github-actions-terraform
```

OIDC vs Secrets
- Recommended: Configure GitHub OIDC and create an IAM role with a trust policy for your repo, then store the role ARN in repo secret `OIDC_ROLE_ARN` (or pass it when dispatching). The workflow will assume the role via OIDC.
- Fallback: if no OIDC role is provided, the workflow uses `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` repo secrets.

Validation
- There's a small validation workflow `.github/workflows/validate-oidc-secret.yml` you can run manually to check whether `OIDC_ROLE_ARN` or AWS secrets are present.

If you want, I can add example IAM role/trust policy snippets for one of the modules.
# aws-misconfig-remediation
A collection of common AWS misconfigurations and their automated remediations using Terraform and GitHub Actions.
