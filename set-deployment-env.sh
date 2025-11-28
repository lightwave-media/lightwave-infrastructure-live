#!/bin/bash
# ============================================================================
# Django Backend Production Deployment - Environment Variables
# ============================================================================
#
# This script sets all required environment variables for deploying the
# Django backend stack to production.
#
# All values are discovered from AWS Secrets Manager and AWS resources.
#
# Usage:
#   source ./set-deployment-env.sh
#
# DO NOT commit this file with secrets - it's in .gitignore
# ============================================================================

set -e

echo "🔐 Setting deployment environment variables from AWS..."
echo ""

# ============================================================================
# AWS Configuration
# ============================================================================
export AWS_PROFILE=lightwave-admin-new
export AWS_REGION=us-east-1

echo "✓ AWS_PROFILE=$AWS_PROFILE"
echo "✓ AWS_REGION=$AWS_REGION"

# ============================================================================
# Networking Configuration (from VPC vpc-02f48c62006cacfae)
# ============================================================================
export VPC_ID=vpc-02f48c62006cacfae

# Database subnets (private-persistence tier, Multi-AZ)
export DB_SUBNET_IDS=subnet-0ba0de978370667c6,subnet-0f6f1ca30b5154984

# Private app subnets (for ECS Fargate)
export PRIVATE_SUBNET_IDS=subnet-00e39a8d07f4c256b

# Public subnets (for ALB)
export PUBLIC_SUBNET_IDS=subnet-0c51a5b50a08876a4,subnet-0b1a6a9c31139a96e

echo "✓ VPC_ID=$VPC_ID"
echo "✓ DB_SUBNET_IDS=$DB_SUBNET_IDS"
echo "✓ PRIVATE_SUBNET_IDS=$PRIVATE_SUBNET_IDS"
echo "✓ PUBLIC_SUBNET_IDS=$PUBLIC_SUBNET_IDS"

# ============================================================================
# Database Configuration (from AWS Secrets Manager)
# ============================================================================
export DB_MASTER_USERNAME=postgres

echo "📥 Retrieving database master password from Secrets Manager..."
export DB_MASTER_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id /lightwave/prod/database/master-password \
  --query 'SecretString' --output text 2>/dev/null || echo "")

if [ -z "$DB_MASTER_PASSWORD" ]; then
  echo "❌ ERROR: Failed to retrieve database master password"
  echo "   Secret: /lightwave/prod/database/master-password"
  exit 1
fi

echo "✓ DB_MASTER_USERNAME=$DB_MASTER_USERNAME"
echo "✓ DB_MASTER_PASSWORD=***REDACTED***"

# ============================================================================
# Container Configuration (from ECR)
# ============================================================================
# Repository: lightwave-django-backend
export ECR_REPOSITORY_URL=738605694078.dkr.ecr.us-east-1.amazonaws.com/lightwave-django-backend

# Check for prod tag, fall back to latest
echo "📥 Checking for Docker images in ECR..."
AVAILABLE_TAGS=$(aws ecr list-images \
  --repository-name lightwave-django-backend \
  --query 'imageIds[*].imageTag' \
  --output text 2>/dev/null || echo "")

if echo "$AVAILABLE_TAGS" | grep -q "prod"; then
  export IMAGE_TAG=prod
  echo "✓ Found 'prod' tag in ECR"
elif echo "$AVAILABLE_TAGS" | grep -q "latest"; then
  export IMAGE_TAG=latest
  echo "⚠️  No 'prod' tag found, using 'latest'"
  echo "   Consider tagging latest as prod: docker tag $ECR_REPOSITORY_URL:latest $ECR_REPOSITORY_URL:prod"
else
  export IMAGE_TAG=latest
  echo "⚠️  No images found in ECR - deployment will fail"
  echo "   Please build and push Django image first"
  echo ""
  echo "   Quick start:"
  echo "   cd ../../Backend/lightwave-backend"
  echo "   docker build -t lightwave-django:prod ."
  echo "   aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_REPOSITORY_URL"
  echo "   docker tag lightwave-django:prod $ECR_REPOSITORY_URL:prod"
  echo "   docker push $ECR_REPOSITORY_URL:prod"
fi

echo "✓ ECR_REPOSITORY_URL=$ECR_REPOSITORY_URL"
echo "✓ IMAGE_TAG=$IMAGE_TAG"

# ============================================================================
# Django Configuration (from AWS Secrets Manager)
# ============================================================================
echo "📥 Retrieving Django secret key ARN from Secrets Manager..."
export DJANGO_SECRET_KEY_ARN=$(aws secretsmanager describe-secret \
  --secret-id /lightwave/prod/django/secret-key \
  --query 'ARN' --output text 2>/dev/null || echo "")

if [ -z "$DJANGO_SECRET_KEY_ARN" ]; then
  echo "❌ ERROR: Failed to retrieve Django secret key ARN"
  echo "   Secret: /lightwave/prod/django/secret-key"
  exit 1
fi

# Django allowed hosts for production
export DJANGO_ALLOWED_HOSTS="*.lightwave-media.ltd,*.amazonaws.com"

echo "✓ DJANGO_SECRET_KEY_ARN=$DJANGO_SECRET_KEY_ARN"
echo "✓ DJANGO_ALLOWED_HOSTS=$DJANGO_ALLOWED_HOSTS"

# ============================================================================
# Cloudflare Configuration (from AWS Secrets Manager)
# ============================================================================
echo "📥 Retrieving Cloudflare credentials from Secrets Manager..."

export CLOUDFLARE_ZONE_ID=$(aws secretsmanager get-secret-value \
  --secret-id /lightwave/prod/cloudflare/zone-id \
  --query 'SecretString' --output text 2>/dev/null || echo "")

export CLOUDFLARE_API_TOKEN=$(aws secretsmanager get-secret-value \
  --secret-id /lightwave/prod/cloudflare/api-token \
  --query 'SecretString' --output text 2>/dev/null || echo "")

if [ -z "$CLOUDFLARE_ZONE_ID" ]; then
  echo "❌ ERROR: Failed to retrieve Cloudflare Zone ID"
  echo "   Secret: /lightwave/prod/cloudflare/zone-id"
  exit 1
fi

if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
  echo "❌ ERROR: Failed to retrieve Cloudflare API token"
  echo "   Secret: /lightwave/prod/cloudflare/api-token"
  exit 1
fi

echo "✓ CLOUDFLARE_ZONE_ID=$CLOUDFLARE_ZONE_ID"
echo "✓ CLOUDFLARE_API_TOKEN=***REDACTED***"

# ============================================================================
# Verification Summary
# ============================================================================
echo ""
echo "=========================================="
echo "✅ All environment variables set!"
echo "=========================================="
echo ""
echo "AWS Configuration:"
echo "  AWS_PROFILE: $AWS_PROFILE"
echo "  AWS_REGION: $AWS_REGION"
echo ""
echo "Networking:"
echo "  VPC_ID: $VPC_ID"
echo "  DB_SUBNET_IDS: $DB_SUBNET_IDS"
echo "  PRIVATE_SUBNET_IDS: $PRIVATE_SUBNET_IDS"
echo "  PUBLIC_SUBNET_IDS: $PUBLIC_SUBNET_IDS"
echo ""
echo "Database:"
echo "  DB_MASTER_USERNAME: $DB_MASTER_USERNAME"
echo "  DB_MASTER_PASSWORD: ***REDACTED***"
echo ""
echo "Container:"
echo "  ECR_REPOSITORY_URL: $ECR_REPOSITORY_URL"
echo "  IMAGE_TAG: $IMAGE_TAG"
echo ""
echo "Django:"
echo "  DJANGO_SECRET_KEY_ARN: $DJANGO_SECRET_KEY_ARN"
echo "  DJANGO_ALLOWED_HOSTS: $DJANGO_ALLOWED_HOSTS"
echo ""
echo "Cloudflare:"
echo "  CLOUDFLARE_ZONE_ID: $CLOUDFLARE_ZONE_ID"
echo "  CLOUDFLARE_API_TOKEN: ***REDACTED***"
echo ""
echo "=========================================="
echo "🚀 Ready for deployment!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Review environment variables above"
echo "  2. Run: make plan-prod"
echo "  3. Review the plan output"
echo "  4. Run: make apply-prod"
echo ""
