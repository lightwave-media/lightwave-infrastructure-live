# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY RUNNER INVOKER LAMBDA
# Lambda function to trigger ECS Deploy Runner tasks from GitHub Actions
# ---------------------------------------------------------------------------------------------------------------------

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "git::https://github.com/lightwave-media/lightwave-infrastructure-catalog.git//modules/deploy-runner-invoker?ref=feature/prod-bootstrap-initial-deployment"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCIES - ECS Deploy Runner must exist first
# ---------------------------------------------------------------------------------------------------------------------

dependency "ecs_deploy_runner" {
  config_path = "../ecs-deploy-runner"

  mock_outputs = {
    cluster_arn                          = "arn:aws:ecs:us-east-1:738605694078:cluster/mock-cluster"
    security_group_id                    = "sg-12345678"
    docker_builder_task_definition_arn   = "arn:aws:ecs:us-east-1:738605694078:task-definition/mock-docker-builder:1"
    terraform_runner_task_definition_arn = "arn:aws:ecs:us-east-1:738605694078:task-definition/mock-terraform-runner:1"
    app_deployer_task_definition_arn     = "arn:aws:ecs:us-east-1:738605694078:task-definition/mock-app-deployer:1"
    docker_builder_task_role_arn         = "arn:aws:iam::738605694078:role/mock-docker-builder-task"
    terraform_runner_task_role_arn       = "arn:aws:iam::738605694078:role/mock-terraform-runner-task"
    app_deployer_task_role_arn           = "arn:aws:iam::738605694078:role/mock-app-deployer-task"
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

  # ECS configuration from dependency
  ecs_cluster_arn           = dependency.ecs_deploy_runner.outputs.cluster_arn
  subnet_ids                = ["subnet-00e39a8d07f4c256b"]
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
