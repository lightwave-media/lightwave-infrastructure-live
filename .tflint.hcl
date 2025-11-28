plugin "terraform" {
  enabled = true
  version = "0.5.0"
  source  = "github.com/terraform-linters/tflint-ruleset-terraform"
}

plugin "aws" {
  enabled = true
  version = "0.29.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

config {
  module = true
  force = false
}

# Security rules
rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}

rule "terraform_naming_convention" {
  enabled = true
}

# AWS-specific security rules
rule "aws_resource_missing_tags" {
  enabled = true
  tags = ["Environment", "ManagedBy", "Project"]
}

rule "aws_security_group_rule_description" {
  enabled = true
}

rule "aws_db_instance_backup_retention_period" {
  enabled = true
}

rule "aws_db_instance_default_parameter_group" {
  enabled = true
}

rule "aws_elasticache_cluster_default_parameter_group" {
  enabled = true
}

rule "aws_iam_policy_document_gov_friendly_arns" {
  enabled = true
}

rule "aws_iam_policy_gov_friendly_arns" {
  enabled = true
}

rule "aws_iam_role_policy_gov_friendly_arns" {
  enabled = true
}

rule "aws_s3_bucket_versioning_enabled" {
  enabled = true
}

rule "aws_s3_bucket_encryption_enabled" {
  enabled = true
}
