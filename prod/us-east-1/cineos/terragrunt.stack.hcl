locals {
  environment = "prod"
  name        = "cineos-${local.environment}"
  app_name    = "cineos"
}

# =============================================================================
# CineOS Production Stack
# =============================================================================
#
# This stack deploys a complete production CineOS (Django + Wagtail) backend:
# 1. VPC Endpoints (Secrets Manager, ECR, S3, CloudWatch Logs)
# 2. PostgreSQL RDS database (Multi-AZ)
# 3. Redis ElastiCache cluster (Multi-AZ, replication)
# 4. Django on ECS Fargate (auto-scaling, health checks)
# 5. S3 bucket for Wagtail media storage (manual, see below)
# 6. Cloudflare DNS (DDoS protection, SSL, caching - manual, see below)
#
# Prerequisites:
#   - VPC with public and private subnets
#   - ECR repository with CineOS image
#   - GitHub secrets configured
#   - AWS Secrets Manager secrets created:
#       /lightwave/prod/cineos/secret-key
#       /lightwave/prod/cineos/database-password
#       /lightwave/prod/cineos/cloudflare-zone-id
#       /lightwave/prod/cineos/allowed-hosts
#       /lightwave/prod/cineos/s3-media-bucket
# =============================================================================

# -----------------------------------------------------------------------------
# S3 Media Bucket (Wagtail storage)
# -----------------------------------------------------------------------------
# NOTE: S3 bucket created manually via AWS CLI:
#   - Bucket name: cineos-media-prod
#   - Versioning: Enabled
#   - CORS: Configured for https://cineos.io, https://www.cineos.io
# REQUIRED: Wagtail CMS needs persistent storage for media files
# ECS Fargate containers are ephemeral - S3 provides durability

# -----------------------------------------------------------------------------
# VPC Endpoints (CRITICAL: Deploy FIRST for private subnet connectivity)
# -----------------------------------------------------------------------------
unit "vpc_endpoints" {
  source = "git::https://github.com/lightwave-media/lightwave-infrastructure-catalog.git//units/vpc-endpoints?ref=feature/prod-bootstrap-initial-deployment"
  path   = "vpc-endpoints"

  values = {
    version                 = "feature/prod-bootstrap-initial-deployment"
    name                    = local.name
    vpc_id                  = get_env("VPC_ID")
    vpc_cidr                = "10.1.0.0/16"
    private_subnet_ids      = [get_env("PRIVATE_SUBNET_IDS")]
    private_route_table_ids = ["rtb-02b15726e674339cd"]

    environment = local.environment
    aws_region  = get_env("AWS_REGION", "us-east-1")

    # Enable all endpoints needed for ECS Fargate in private subnets
    enable_secretsmanager = true # Pull Django secrets
    enable_ecr            = true # Pull Docker images
    enable_s3             = true # ECR image layers (gateway, FREE)
    enable_logs           = true # Send CloudWatch Logs
  }
}

# -----------------------------------------------------------------------------
# PostgreSQL Database
# -----------------------------------------------------------------------------
unit "postgresql" {
  source = "git::https://github.com/lightwave-media/lightwave-infrastructure-catalog.git//units/postgresql?ref=v1.0.0"
  path   = "postgresql"

  values = {
    version           = "v1.0.0"
    name              = local.name
    instance_class    = "db.t4g.small"
    allocated_storage = 50

    # Load master credentials from Secrets Manager
    master_username = "postgres"
    master_password = get_env("DB_MASTER_PASSWORD") # From /lightwave/prod/cineos/database-password

    # Database name for CineOS (alphanumeric only, no hyphens)
    db_name = "cineosconfig"

    # Networking
    vpc_id     = get_env("VPC_ID")
    subnet_ids = split(",", get_env("DB_SUBNET_IDS", ""))

    # Production settings
    environment             = local.environment
    multi_az                = true
    backup_retention_period = 30
    deletion_protection     = true
    skip_final_snapshot     = false

    # Storage auto-scaling
    max_allocated_storage = 250

    # Security
    storage_encrypted = true

    # Performance
    performance_insights_enabled = true

    # CloudWatch logs
    enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  }
}

# -----------------------------------------------------------------------------
# Redis ElastiCache
# -----------------------------------------------------------------------------
unit "redis" {
  source = "git::https://github.com/lightwave-media/lightwave-infrastructure-catalog.git//units/redis?ref=v1.0.0"
  path   = "redis"

  values = {
    version    = "v1.0.0"
    name       = local.name
    node_type  = "cache.t4g.small"
    subnet_ids = split(",", get_env("DB_SUBNET_IDS", ""))
    vpc_id     = get_env("VPC_ID")

    # Production settings
    environment                = local.environment
    num_cache_clusters         = 2 # 1 primary + 1 replica
    automatic_failover_enabled = true
    multi_az_enabled           = true

    # Security
    at_rest_encryption_enabled = true
    transit_encryption_enabled = true

    # Backups
    snapshot_retention_limit = 7

    # Redis version
    engine_version = "7.1"

    # Parameter group for Celery optimization
    parameter_group_family = "redis7"
    parameters = [
      {
        name  = "maxmemory-policy"
        value = "allkeys-lru"
      },
      {
        name  = "timeout"
        value = "300"
      }
    ]
  }
}

# -----------------------------------------------------------------------------
# Django ECS Fargate Service (CineOS)
# -----------------------------------------------------------------------------
unit "django_service" {
  source = "git::https://github.com/lightwave-media/lightwave-infrastructure-catalog.git//units/django-fargate-stateful-service?ref=v1.0.0"
  path   = "django"

  values = {
    version            = "v1.0.0"
    name               = local.name
    desired_count      = 2 # Production: 2 containers for HA
    cpu                = 512
    memory             = 1024
    ecr_repository_url = get_env("ECR_REPOSITORY_URL")
    image_tag          = get_env("IMAGE_TAG", "prod")

    # Django configuration
    django_secret_key_arn  = get_env("DJANGO_SECRET_KEY_ARN") # /lightwave/prod/cineos/secret-key
    django_settings_module = "cineos_config.settings"
    django_allowed_hosts   = get_env("DJANGO_ALLOWED_HOSTS", "cineos.io,www.cineos.io,*.amazonaws.com")

    # Wagtail S3 media storage
    use_s3_media           = true
    s3_media_bucket_name   = get_env("S3_MEDIA_BUCKET_NAME", "cineos-media-prod")
    s3_media_bucket_region = get_env("AWS_REGION", "us-east-1")

    # Database URL is provided by dependency
    # Redis URLs are provided by dependency

    # Environment
    environment = local.environment
    debug       = false
    aws_region  = get_env("AWS_REGION", "us-east-1")

    # Networking
    vpc_id             = get_env("VPC_ID")
    private_subnet_ids = split(",", get_env("PRIVATE_SUBNET_IDS", ""))
    public_subnet_ids  = split(",", get_env("PUBLIC_SUBNET_IDS", ""))

    # Health checks
    health_check_path                = "/health/live/"
    health_check_interval            = 30
    health_check_timeout             = 5
    health_check_healthy_threshold   = 2
    health_check_unhealthy_threshold = 3

    # CloudWatch
    cloudwatch_log_retention_days = 30
    enable_container_insights     = true

    # Celery for background tasks
    enable_celery       = true
    celery_worker_count = 1
    celery_beat_enabled = true

    # Additional environment variables
    extra_environment_variables = {
      APP_NAME            = "CineOS"
      APP_DOMAIN          = "cineos.io"
      TIME_ZONE           = "America/New_York"
      LANGUAGE_CODE       = "en-us"
      ENABLE_WEBSOCKETS   = "true"
      ENABLE_AI_FEATURES  = "false" # Enable when API keys are added
      DEFAULT_AGENT_MODEL = "openai:gpt-4o"
      DEFAULT_LLM_MODEL   = "gpt-4o"
    }
  }
}

# -----------------------------------------------------------------------------
# Cloudflare DNS - Will configure manually after Django service deploys
# -----------------------------------------------------------------------------
# NOTE: Cloudflare DNS requires ALB DNS name from django_service output
# After infrastructure deploys, run:
#   aws elbv2 describe-load-balancers --profile lightwave-admin-new \
#     --query 'LoadBalancers[?starts_with(LoadBalancerName, `cineos-prod`)].DNSName'
# Then configure Cloudflare CNAME records manually or via separate apply
