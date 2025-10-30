# ---------------------------------------------------------------------------------------------------------------------
# TERRAGRUNT CONFIGURATION FOR PRODUCTION BUDGET
# Creates AWS Budget with alerts for production environment
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

  # Budget configuration for prod
  monthly_budget_limit = 500 # $500/month for production

  # Alert email addresses - replace with actual addresses
  alert_emails = [
    "team@lightwave-media.ltd",
    "management@lightwave-media.ltd"
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

  # Slack webhook URL (optional) - store in AWS Secrets Manager and reference here
  # slack_webhook_url = data.aws_secretsmanager_secret_version.slack_webhook.secret_string

  # Multiple notification thresholds
  notification_thresholds = [
    # 70% threshold - Management email only
    {
      threshold_percentage = 70
      threshold_type       = "PERCENTAGE"
      notification_type    = "ACTUAL"
      email_addresses      = ["management@lightwave-media.ltd"]
      sns_topic_arn        = null
    },
    # 85% threshold - Team + management, with SNS
    {
      threshold_percentage = 85
      threshold_type       = "PERCENTAGE"
      notification_type    = "ACTUAL"
      email_addresses      = local.alert_emails
      sns_topic_arn        = null # Will use module-created SNS topic
    },
    # 100% threshold - Critical alert to everyone
    {
      threshold_percentage = 100
      threshold_type       = "PERCENTAGE"
      notification_type    = "ACTUAL"
      email_addresses      = local.alert_emails
      sns_topic_arn        = null # Will use module-created SNS topic
    },
    # 110% threshold - Forecasted overage alert
    {
      threshold_percentage = 110
      threshold_type       = "PERCENTAGE"
      notification_type    = "FORECASTED"
      email_addresses      = local.alert_emails
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
