variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# Registry-level scanning only. Repositories are expected to exist or be
# managed outside this module.

variable "registry_scan_type" {
  description = "Registry scan type (BASIC or ENHANCED)"
  type        = string
  default     = "BASIC"
}

variable "basic_scan_frequency" {
  description = "Frequency to use for BASIC scan type (SCAN_ON_PUSH)"
  type        = string
  default     = "SCAN_ON_PUSH"
}

variable "enhanced_scan_frequency" {
  description = "Frequency to use for ENHANCED scan type (CONTINUOUS)"
  type        = string
  default     = "CONTINUOUS_SCAN"
}

variable "tags" {
  description = "Tags applied to ECR repositories"
  type        = map(string)
  default     = {}
}
