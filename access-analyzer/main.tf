########################################
# Default provider (module-run mode)
# Uses `var.region` and `var.aws_profile` to target the desired region.
########################################
provider "aws" {
  region = var.region
  #profile = var.aws_profile
}

########################################
# Identify current account and organization
########################################
data "aws_caller_identity" "current" {}

data "aws_organizations_organization" "org" {}

locals {
  is_management_account = data.aws_caller_identity.current.account_id == data.aws_organizations_organization.org.master_account_id
}

########################################
# Organization-level Access Analyzer (single-region)
########################################
resource "aws_accessanalyzer_analyzer" "this" {
  count         = local.is_management_account ? 1 : 0
  analyzer_name = var.analyzer_name
  type          = "ORGANIZATION"
  tags          = var.tags
}

########################################
# Fail fast if not running from management account
########################################
resource "null_resource" "fail_if_not_management" {
  count = local.is_management_account ? 0 : 1

  provisioner "local-exec" {
    command = <<EOT
echo "ERROR: This Terraform must be executed from the AWS Organization MANAGEMENT account." >&2
exit 1
EOT
  }
}
