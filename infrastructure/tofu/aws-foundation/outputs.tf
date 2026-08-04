output "state_bucket" {
  value = aws_s3_bucket.state.id
}

output "recovery_bucket" {
  value = aws_s3_bucket.recovery.id
}

output "kms_key_arn" {
  value = aws_kms_key.opentofu.arn
}

output "mutation_lease_table" {
  value = aws_dynamodb_table.mutation_lease.name
}

output "github_plan_role_arn" {
  value = aws_iam_role.github_plan.arn
}

output "github_apply_role_arn" {
  value = aws_iam_role.github_apply.arn
}
