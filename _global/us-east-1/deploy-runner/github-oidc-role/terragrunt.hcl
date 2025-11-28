# ---------------------------------------------------------------------------------------------------------------------
# GITHUB OIDC ROLE
# IAM role for GitHub Actions to assume via OIDC (no stored credentials)
# ---------------------------------------------------------------------------------------------------------------------

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "git::https://github.com/lightwave-media/lightwave-infrastructure-catalog.git//modules/github-oidc-role?ref=feature/prod-bootstrap-initial-deployment"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCIES - Needs ECS cluster and Lambda function ARNs
# ---------------------------------------------------------------------------------------------------------------------

dependency "ecs_deploy_runner" {
  config_path = "../ecs-deploy-runner"

  mock_outputs = {
    cluster_arn = "arn:aws:ecs:us-east-1:738605694078:cluster/mock-cluster"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

dependency "invoker_lambda" {
  config_path = "../invoker-lambda"

  mock_outputs = {
    lambda_function_arn = "arn:aws:lambda:us-east-1:738605694078:function/mock-invoker"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

locals {
  name        = "lightwave-deploy-runner"
  environment = "global"
}

inputs = {
  name        = local.name
  environment = local.environment

  # GitHub configuration
  github_org = "lightwave-media"
  github_repositories = [
    "lightwave-infrastructure-live", # Can trigger deployments
    "cineos",                        # Can trigger its own deployment
    "photographos",
    "createos",
    "lightwave-backend",
    "lightwave-media-site",
  ]
  restrict_to_main_branch = true # Only main branch can deploy

  # Use existing OIDC provider (already exists in account)
  create_oidc_provider = false

  # Permissions: invoke Lambda + read logs
  lambda_function_arn = dependency.invoker_lambda.outputs.lambda_function_arn
  ecs_cluster_arn     = dependency.ecs_deploy_runner.outputs.cluster_arn
  log_group_arns = [
    "arn:aws:logs:us-east-1:738605694078:log-group:/ecs/${local.name}-global/*",
    "arn:aws:logs:us-east-1:738605694078:log-group:/aws/lambda/${local.name}-global-invoker:*",
  ]

  tags = {
    Purpose = "GitHub Actions OIDC Authentication"
    Stack   = "deploy-runner"
  }
}
