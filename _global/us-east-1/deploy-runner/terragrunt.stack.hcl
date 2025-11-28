locals {
  environment = "global"
  name        = "lightwave-deploy-runner"
}

# =============================================================================
# LightWave Deploy Runner Stack
# =============================================================================
#
# This stack deploys the centralized CI/CD infrastructure:
# 1. ECS Deploy Runner (Fargate cluster + task definitions)
# 2. Invoker Lambda (triggers ECS tasks)
# 3. GitHub OIDC Role (allows GitHub Actions to invoke Lambda)
#
# Based on Gruntwork Pipelines architecture pattern.
# See: modules/ecs-deploy-runner/ARCHITECTURE.md
# =============================================================================

# -----------------------------------------------------------------------------
# ECS Deploy Runner
# Creates ECS cluster with task definitions for:
# - Docker image builds (Kaniko)
# - Terraform/Terragrunt operations
# - App deployments (build + deploy)
# -----------------------------------------------------------------------------
unit "ecs_deploy_runner" {
  source = "git::https://github.com/lightwave-media/lightwave-infrastructure-catalog.git//modules/ecs-deploy-runner?ref=main"
  path   = "ecs-deploy-runner"

  values = {
    name        = local.name
    environment = local.environment

    # Use existing VPC (same as cineos production)
    vpc_id             = get_env("VPC_ID")
    private_subnet_ids = split(",", get_env("PRIVATE_SUBNET_IDS", ""))

    # Task sizing
    docker_builder_cpu      = 1024
    docker_builder_memory   = 4096
    terraform_runner_cpu    = 512
    terraform_runner_memory = 2048
    app_deployer_cpu        = 1024
    app_deployer_memory     = 4096

    # Logging
    cloudwatch_log_retention_days = 30

    # ECR for custom deployer image
    create_ecr_repository = true
    ecr_repository_name   = "${local.name}-images"

    tags = {
      Purpose = "CI/CD Deploy Runner"
      Stack   = "deploy-runner"
    }
  }
}

# -----------------------------------------------------------------------------
# Invoker Lambda
# Triggers ECS tasks when called from GitHub Actions
# -----------------------------------------------------------------------------
unit "invoker_lambda" {
  source = "git::https://github.com/lightwave-media/lightwave-infrastructure-catalog.git//modules/deploy-runner-invoker?ref=main"
  path   = "invoker-lambda"

  values = {
    name        = local.name
    environment = local.environment

    # ECS configuration (from ecs_deploy_runner unit)
    # These will be resolved from dependency outputs
    ecs_cluster_arn           = dependency.ecs_deploy_runner.outputs.cluster_arn
    subnet_ids                = split(",", get_env("PRIVATE_SUBNET_IDS", ""))
    security_group_ids        = [dependency.ecs_deploy_runner.outputs.security_group_id]
    docker_builder_task_arn   = dependency.ecs_deploy_runner.outputs.docker_builder_task_definition_arn
    terraform_runner_task_arn = dependency.ecs_deploy_runner.outputs.terraform_runner_task_definition_arn
    app_deployer_task_arn     = dependency.ecs_deploy_runner.outputs.app_deployer_task_definition_arn

    task_role_arns = [
      dependency.ecs_deploy_runner.outputs.docker_builder_task_role_arn,
      dependency.ecs_deploy_runner.outputs.terraform_runner_task_role_arn,
      dependency.ecs_deploy_runner.outputs.app_deployer_task_role_arn,
    ]

    # Allowed apps
    allowed_apps = ["cineos", "photographos", "createos", "lightwave-backend", "lightwave-media-site"]

    # Logging
    log_retention_days = 30

    tags = {
      Purpose = "CI/CD Deploy Runner Invoker"
      Stack   = "deploy-runner"
    }
  }

  # Dependency: ECS cluster must exist first
  dependencies = ["../ecs-deploy-runner"]
}

# -----------------------------------------------------------------------------
# GitHub OIDC Role
# Allows GitHub Actions to assume AWS role without stored credentials
# -----------------------------------------------------------------------------
unit "github_oidc_role" {
  source = "git::https://github.com/lightwave-media/lightwave-infrastructure-catalog.git//modules/github-oidc-role?ref=main"
  path   = "github-oidc-role"

  values = {
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

    # Create OIDC provider (only needed once per account)
    create_oidc_provider = true

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

  # Dependencies: Lambda must exist first
  dependencies = ["../invoker-lambda"]
}
