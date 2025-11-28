locals {
  environment = "prod"
  name        = "lightwave-django-${local.environment}"
}

# =============================================================================
# Django Backend Production Stack
# =============================================================================
#
# This stack deploys a complete production Django backend:
# 1. PostgreSQL RDS database (Multi-AZ)
# 2. Redis ElastiCache cluster (Multi-AZ, replication)
# 3. Django on ECS Fargate (auto-scaling, health checks)
# 4. Cloudflare DNS (DDoS protection, SSL, caching)
#
# Prerequisites:
#   - VPC with public and private subnets
#   - ECR repository with Django image
#   - GitHub secrets configured
#   - AWS Secrets Manager secrets created
# =============================================================================

# -----------------------------------------------------------------------------
# PostgreSQL Database
# -----------------------------------------------------------------------------
unit "postgresql" {
  source = "git::https://github.com/lightwave-media/lightwave-infrastructure-catalog.git//units/postgresql?ref=main"
  path   = "postgresql"

  values = {
    name              = local.name
    instance_class    = "db.t4g.small"
    allocated_storage = 50

    # Load master credentials from environment (set in GitHub secrets)
    master_username = get_env("DB_MASTER_USERNAME", "postgres")
    master_password = get_env("DB_MASTER_PASSWORD")

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
  }
}

# -----------------------------------------------------------------------------
# Redis ElastiCache
# -----------------------------------------------------------------------------
unit "redis" {
  source = "git::https://github.com/lightwave-media/lightwave-infrastructure-catalog.git//units/redis?ref=main"
  path   = "redis"

  values = {
    name       = local.name
    node_type  = "cache.t4g.small"
    subnet_ids = split(",", get_env("PRIVATE_SUBNET_IDS", ""))

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
  }
}

# -----------------------------------------------------------------------------
# Django ECS Fargate Service
# -----------------------------------------------------------------------------
unit "django_service" {
  source = "git::https://github.com/lightwave-media/lightwave-infrastructure-catalog.git//units/django-fargate-stateful-service?ref=main"
  path   = "django"

  values = {
    name               = local.name
    desired_count      = 2 # Production: 2 containers for HA
    cpu                = 512
    memory             = 1024
    ecr_repository_url = get_env("ECR_REPOSITORY_URL")
    image_tag          = get_env("IMAGE_TAG", "prod")

    # Django configuration
    django_secret_key_arn  = get_env("DJANGO_SECRET_KEY_ARN")
    django_settings_module = "config.settings.prod"
    django_allowed_hosts   = get_env("DJANGO_ALLOWED_HOSTS", "*.lightwave-media.ltd,*.amazonaws.com")

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
  }
}

# -----------------------------------------------------------------------------
# Cloudflare DNS
# -----------------------------------------------------------------------------
unit "cloudflare_dns" {
  source = "git::https://github.com/lightwave-media/lightwave-infrastructure-catalog.git//units/cloudflare-dns?ref=main"
  path   = "cloudflare"

  values = {
    # DNS configuration
    zone_id     = get_env("CLOUDFLARE_ZONE_ID")
    record_name = "api" # Creates api.lightwave-media.ltd
    record_type = "CNAME"
    target      = get_env("ALB_DNS_NAME") # From Django service output
    ttl         = 1                       # Auto (Cloudflare proxy)
    proxied     = true                    # Enable Cloudflare proxy (DDoS, SSL, caching)

    # Security
    security_level = "medium"

    # SSL/TLS
    ssl_mode = "full" # Full SSL

    # Caching
    cache_level = "standard"
  }
}
