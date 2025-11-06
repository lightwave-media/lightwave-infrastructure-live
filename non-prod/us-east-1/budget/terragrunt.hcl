# ---------------------------------------------------------------------------------------------------------------------
# TERRAGRUNT CONFIGURATION FOR NON-PROD BUDGET
# Creates AWS Budget with alerts for non-production environments (dev + staging)
# Test: Verify workflow with merged catalog modules
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "git::https://github.com/lightwave-media/lightwave-infrastructure-catalog.git//modules/budget?ref=main"
}

# Include root configuration
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Include environment configuration
include "account" {
  path = find_in_parent_folders("account.hcl")
}

# Include region configuration
include "region" {
  path = find_in_parent_folders("region.hcl")
}

# ---------------------------------------------------------------------------------------------------------------------
# LOCALS
# ---------------------------------------------------------------------------------------------------------------------

locals {
  account_vars = read_terragrunt_config(find_in_parent_folders("account.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))

  account_name = local.account_vars.locals.account_name
  aws_region   = local.region_vars.locals.aws_region

  # Budget configuration for non-prod (dev + staging combined)
  # Dev: $50/month, Staging: $100/month = $150/month total
  monthly_budget_limit = 150

  # Alert email addresses
  alert_emails = [
    "team@lightwave-media.ltd"
  ]
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE INPUTS
# ---------------------------------------------------------------------------------------------------------------------

inputs = {
  # Budget configuration
  budget_name          = "${local.account_name}-monthly-budget"
  monthly_budget_limit = local.monthly_budget_limit
  environment          = local.account_name

  # SNS topic creation
  create_sns_topic      = true
  alert_email_addresses = local.alert_emails

  # Slack webhook URL (optional)
  # slack_webhook_url = data.aws_secretsmanager_secret_version.slack_webhook.secret_string

  # Multiple notification thresholds
  notification_thresholds = [
    # 80% threshold - Email alert
    {
      threshold_percentage = 80
      threshold_type       = "PERCENTAGE"
      notification_type    = "ACTUAL"
      email_addresses      = local.alert_emails
      sns_topic_arn        = null
    },
    # 100% threshold - Email + SNS alert
    {
      threshold_percentage = 100
      threshold_type       = "PERCENTAGE"
      notification_type    = "ACTUAL"
      email_addresses      = local.alert_emails
      sns_topic_arn        = null # Will use module-created SNS topic
    },
    # 150% threshold - Critical alert (triggers emergency shutdown consideration)
    {
      threshold_percentage = 150
      threshold_type       = "PERCENTAGE"
      notification_type    = "ACTUAL"
      email_addresses      = concat(local.alert_emails, ["management@lightwave-media.ltd"])
      sns_topic_arn        = null
    }
  ]

  # Create CloudWatch alarm for critical threshold
  create_cloudwatch_alarm = true

  # Cost types configuration
  cost_types_include_credit             = true
  cost_types_include_discount           = true
  cost_types_include_other_subscription = true
  cost_types_include_recurring          = true
  cost_types_include_refund             = true
  cost_types_include_subscription       = true
  cost_types_include_support            = true
  cost_types_include_tax                = true
  cost_types_include_upfront            = true
  cost_types_use_amortized              = false
  cost_types_use_blended                = false

  # Tags
  tags = {
    Environment = local.account_name
    ManagedBy   = "Terragrunt"
    Purpose     = "Cost Monitoring"
    Owner       = "Platform Team"
  }
}
