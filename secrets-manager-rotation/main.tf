resource "aws_secretsmanager_secret" "this" {
  name        = var.name
  description = var.description
  kms_key_id  = var.kms_key_id
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "this" {
  count         = var.secret_string != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = var.secret_string
}

resource "aws_secretsmanager_secret_rotation" "this" {
  count               = var.rotation_enabled ? 1 : 0
  secret_id           = aws_secretsmanager_secret.this.id
  rotation_lambda_arn = var.rotation_lambda_arn != "" ? var.rotation_lambda_arn : (
    var.create_rotation_lambda ? aws_lambda_function.rotation_lambda[0].arn : ""
  )

  rotation_rules {
    automatically_after_days = var.rotation_days
  }
}

# Optional rotation lambda: create a simple rotation handler if requested
resource "aws_iam_role" "rotation_lambda_role" {
  count = var.create_rotation_lambda ? 1 : 0

  name = "${var.rotation_lambda_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "rotation_lambda_policy" {
  count = var.create_rotation_lambda ? 1 : 0

  name = "${var.rotation_lambda_name}-policy"
  role = aws_iam_role.rotation_lambda_role[0].id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage",
          "secretsmanager:DescribeSecret",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

data "archive_file" "rotation_lambda_zip" {
  count = var.create_rotation_lambda ? 1 : 0

  type        = "zip"
  source_file = "${path.module}/rotation_handler.py"
  output_path = "${path.module}/rotation_handler.zip"
}

resource "aws_lambda_function" "rotation_lambda" {
  count = var.create_rotation_lambda ? 1 : 0

  filename         = data.archive_file.rotation_lambda_zip[0].output_path
  function_name    = var.rotation_lambda_name
  role             = aws_iam_role.rotation_lambda_role[0].arn
  handler          = var.rotation_lambda_handler
  runtime          = var.rotation_lambda_runtime
  source_code_hash = data.archive_file.rotation_lambda_zip[0].output_base64sha256

  vpc_config {
    subnet_ids         = var.rotation_lambda_subnet_ids
    security_group_ids = var.rotation_lambda_security_group_ids
  }
}

