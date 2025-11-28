# ---------------------------------------------------------------------------------------------------------------------
# ECS DEPLOY RUNNER
# Creates ECS Fargate cluster with task definitions for CI/CD operations
# ---------------------------------------------------------------------------------------------------------------------

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "git::https://github.com/lightwave-media/lightwave-infrastructure-catalog.git//modules/ecs-deploy-runner?ref=feature/prod-bootstrap-initial-deployment"
}

locals {
  name        = "lightwave-deploy-runner"
  environment = "global"
}

inputs = {
  name        = local.name
  environment = local.environment

  # Use existing VPC
  vpc_id             = "vpc-02f48c62006cacfae"
  private_subnet_ids = ["subnet-00e39a8d07f4c256b"]

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
