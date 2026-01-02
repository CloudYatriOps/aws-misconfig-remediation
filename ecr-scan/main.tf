provider "aws" {
  region = var.region
  profile = "AdministratorAccess-803103365620"
}

locals {
  effective_scan_frequency = var.registry_scan_type == "ENHANCED" ? var.enhanced_scan_frequency : var.basic_scan_frequency
}

resource "aws_ecr_registry_scanning_configuration" "ecr_registry" {
  scan_type = var.registry_scan_type
  rule {
    repository_filter {
      filter = "*"
      filter_type = "WILDCARD"
    }
    scan_frequency = local.effective_scan_frequency
  }
}
