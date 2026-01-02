variable "name" {
  description = "Name of the Secrets Manager secret"
  type        = string
}

variable "description" {
  description = "Description for the secret"
  type        = string
  default     = "Managed by Terraform"
}

variable "kms_key_id" {
  description = "KMS key ARN or ID for secret encryption (optional)"
  type        = string
  default     = ""
}

variable "secret_string" {
  description = "Initial secret string (optional)"
  type        = string
  default     = ""
}

variable "rotation_enabled" {
  description = "Enable automatic rotation"
  type        = bool
  default     = true
}

variable "rotation_lambda_arn" {
  description = "ARN of the rotation Lambda that implements SecretsManager rotation"
  type        = string
  default     = ""
}

variable "rotation_days" {
  description = "Rotation interval in days"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply to the secret"
  type        = map(string)
  default     = {}
}

variable "create_rotation_lambda" {
  description = "If true and no rotation_lambda_arn is provided, create a basic rotation Lambda in this module"
  type        = bool
  default     = false
}

variable "rotation_lambda_name" {
  description = "Name for the generated rotation Lambda (when create_rotation_lambda = true)"
  type        = string
  default     = "secrets-rotation-lambda"
}

variable "rotation_lambda_runtime" {
  description = "Runtime for the generated Lambda"
  type        = string
  default     = "python3.9"
}

variable "rotation_lambda_handler" {
  description = "Handler for the generated Lambda"
  type        = string
  default     = "rotation_handler.lambda_handler"
}

variable "rotation_lambda_subnet_ids" {
  description = "Optional subnet IDs for Lambda VPC configuration (if needed)"
  type        = list(string)
  default     = []
}

variable "rotation_lambda_security_group_ids" {
  description = "Optional security group IDs for Lambda VPC configuration"
  type        = list(string)
  default     = []
}

