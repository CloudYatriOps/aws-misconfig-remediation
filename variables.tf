variable "region" {
  description = "Primary region (used for identity/org lookup)"
  type        = string
  default     = "us-west-2"
}

variable "analyzer_name" {
  description = "Base name for Access Analyzer"
  type        = string
  default     = "winfo-org-access-analyzer"
}

variable "tags" {
  description = "Tags to apply to Access Analyzer"
  type        = map(string)
  default     = {}
}

#variable "aws_profile" {
#  description = "AWS CLI profile to use"
#  type        = string
#  default     = "AdministratorAccess-803103365620"
#}
