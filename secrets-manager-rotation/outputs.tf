output "secret_arn" {
  value = aws_secretsmanager_secret.this.arn
}

output "secret_id" {
  value = aws_secretsmanager_secret.this.id
}

output "rotation_lambda_arn" {
  value       = var.create_rotation_lambda ? aws_lambda_function.rotation_lambda[0].arn : var.rotation_lambda_arn
  description = "ARN of the rotation lambda (created or provided)"
}
