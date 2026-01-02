# Secrets Manager Rotation Module

This module creates an AWS Secrets Manager secret and optionally enables automatic rotation.

Usage:

```hcl
module "secret_with_rotation" {
  source = "../secrets-manager-rotation"

  name                = "my/service/secret"
  description         = "Service credentials"
  secret_string       = jsonencode({ username = "user", password = "p@ssw0rd" })
  rotation_enabled    = true
  rotation_lambda_arn = "arn:aws:lambda:us-east-1:123456789012:function:rotate-secret"
  rotation_days       = 30
}
```

Notes:
- You must supply a `rotation_lambda_arn` if `rotation_enabled` is true. The Lambda must implement the Secrets Manager rotation protocol.
- The module creates `aws_secretsmanager_secret`, optionally `aws_secretsmanager_secret_version`, and `aws_secretsmanager_secret_rotation` when enabled.
