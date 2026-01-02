output "management_account_id" {
  value = data.aws_organizations_organization.org.master_account_id
}

output "current_account_id" {
  value = data.aws_caller_identity.current.account_id
}

output "access_analyzers" {
  description = "Organization-level Access Analyzers created per region"
  value = aws_accessanalyzer_analyzer.this[0].arn
}
