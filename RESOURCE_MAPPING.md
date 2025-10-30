# AWS Resource to Deployment Variable Mapping

**Generated:** 2025-10-29
**AWS Account:** 738605694078 (lightwave-admin-new)
**Environment:** Production

---

## Overview

This document maps all discovered AWS resources to their corresponding deployment environment variables for the Django backend production stack.

---

## AWS Secrets Manager → Environment Variables

### Database Secrets

| Secret Name | Secret ARN | Environment Variable | Value Type |
|------------|------------|---------------------|------------|
| `/lightwave/prod/database/master-password` | `arn:aws:secretsmanager:us-east-1:738605694078:secret:/lightwave/prod/database/master-password-l6VzI9` | `DB_MASTER_PASSWORD` | String (retrieved at runtime) |

**Usage in deployment:**
```bash
export DB_MASTER_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id /lightwave/prod/database/master-password \
  --query 'SecretString' --output text)
```

---

### Django Application Secrets

| Secret Name | Secret ARN | Environment Variable | Value Type |
|------------|------------|---------------------|------------|
| `/lightwave/prod/django/secret-key` | `arn:aws:secretsmanager:us-east-1:738605694078:secret:/lightwave/prod/django/secret-key-IiS699` | `DJANGO_SECRET_KEY_ARN` | ARN (passed to ECS) |

**Usage in deployment:**
```bash
export DJANGO_SECRET_KEY_ARN=arn:aws:secretsmanager:us-east-1:738605694078:secret:/lightwave/prod/django/secret-key-IiS699
```

**Note:** The ECS task definition references the ARN. Django retrieves the actual secret value at runtime.

---

### Cloudflare Secrets

| Secret Name | Secret ARN | Environment Variable | Value Type |
|------------|------------|---------------------|------------|
| `/lightwave/prod/cloudflare/zone-id` | `arn:aws:secretsmanager:us-east-1:738605694078:secret:/lightwave/prod/cloudflare/zone-id-WtBhfF` | `CLOUDFLARE_ZONE_ID` | String (retrieved at runtime) |
| `/lightwave/prod/cloudflare/api-token` | `arn:aws:secretsmanager:us-east-1:738605694078:secret:/lightwave/prod/cloudflare/api-token-M4iuFs` | `CLOUDFLARE_API_TOKEN` | String (retrieved at runtime) |

**Usage in deployment:**
```bash
export CLOUDFLARE_ZONE_ID=$(aws secretsmanager get-secret-value \
  --secret-id /lightwave/prod/cloudflare/zone-id \
  --query 'SecretString' --output text)

export CLOUDFLARE_API_TOKEN=$(aws secretsmanager get-secret-value \
  --secret-id /lightwave/prod/cloudflare/api-token \
  --query 'SecretString' --output text)
```

**Cloudflare Zone:** lightwave-media.ltd
**Zone ID:** `32139b65349431e3a0c7770b8842aac5`

---

## ECR Repositories → Container Configuration

### Django Backend Repository

| Repository Name | Repository URI | Environment Variable | Value |
|----------------|----------------|---------------------|-------|
| `lightwave-django-backend` | `738605694078.dkr.ecr.us-east-1.amazonaws.com/lightwave-django-backend` | `ECR_REPOSITORY_URL` | Full URI |

**Available Image Tags:**
- `dev-latest`
- `latest`
- `dev-20251027-130913`
- `dev-20251027-130220`
- `dev-20251027-124824`

**Usage in deployment:**
```bash
export ECR_REPOSITORY_URL=738605694078.dkr.ecr.us-east-1.amazonaws.com/lightwave-django-backend
export IMAGE_TAG=latest  # or prod (recommended to tag for production)
```

**Recommendation:** Tag latest as prod before deployment:
```bash
# Pull latest
docker pull 738605694078.dkr.ecr.us-east-1.amazonaws.com/lightwave-django-backend:latest

# Tag as prod
docker tag 738605694078.dkr.ecr.us-east-1.amazonaws.com/lightwave-django-backend:latest \
           738605694078.dkr.ecr.us-east-1.amazonaws.com/lightwave-django-backend:prod

# Push prod tag
docker push 738605694078.dkr.ecr.us-east-1.amazonaws.com/lightwave-django-backend:prod
```

---

## VPC Resources → Networking Configuration

### VPC

| Resource | ID | Environment Variable | Value |
|----------|-----|---------------------|-------|
| VPC | `vpc-02f48c62006cacfae` | `VPC_ID` | vpc-02f48c62006cacfae |

**CIDR:** 10.1.0.0/16
**Name:** lightwave-dev-vpc

---

### Subnets

#### Database Subnets (Private-Persistence Tier)

| Subnet ID | AZ | CIDR | Name | Environment Variable |
|-----------|-----|------|------|---------------------|
| `subnet-0ba0de978370667c6` | us-east-1a | 10.1.20.0/24 | lightwave-dev-vpc-db-us-east-1a | `DB_SUBNET_IDS` |
| `subnet-0f6f1ca30b5154984` | us-east-1b | 10.1.21.0/24 | lightwave-dev-vpc-db-us-east-1b | `DB_SUBNET_IDS` |

**Usage:**
```bash
export DB_SUBNET_IDS=subnet-0ba0de978370667c6,subnet-0f6f1ca30b5154984
```

**Purpose:** RDS PostgreSQL, ElastiCache Redis (Multi-AZ deployment)

---

#### Private App Subnets

| Subnet ID | AZ | CIDR | Name | Environment Variable |
|-----------|-----|------|------|---------------------|
| `subnet-00e39a8d07f4c256b` | us-east-1a | 10.1.10.0/24 | lightwave-dev-vpc-private-us-east-1a | `PRIVATE_SUBNET_IDS` |

**Usage:**
```bash
export PRIVATE_SUBNET_IDS=subnet-00e39a8d07f4c256b
```

**Purpose:** ECS Fargate tasks (Django containers)

**Note:** Currently only 1 AZ. Consider adding us-east-1b private subnet for true Multi-AZ ECS deployment.

---

#### Public Subnets (DMZ Tier)

| Subnet ID | AZ | CIDR | Name | Environment Variable |
|-----------|-----|------|------|---------------------|
| `subnet-0c51a5b50a08876a4` | us-east-1a | 10.1.0.0/24 | lightwave-dev-vpc-public-us-east-1a | `PUBLIC_SUBNET_IDS` |
| `subnet-0b1a6a9c31139a96e` | us-east-1b | 10.1.1.0/24 | lightwave-dev-vpc-public-us-east-1b | `PUBLIC_SUBNET_IDS` |

**Usage:**
```bash
export PUBLIC_SUBNET_IDS=subnet-0c51a5b50a08876a4,subnet-0b1a6a9c31139a96e
```

**Purpose:** Application Load Balancer (internet-facing)

---

### Internet Gateway

| Resource | ID | Route Table | Attached To |
|----------|-----|-------------|-------------|
| Internet Gateway | `igw-0de8e6c996e02ae0d` | `rtb-0354fe59b9fd1f22a` | vpc-02f48c62006cacfae |

**Name:** lightwave-dev-igw
**Routes:** 0.0.0.0/0 → IGW (in public route table)

---

## Complete Environment Variable Reference

### Quick Copy-Paste (with discovered values)

```bash
#!/bin/bash
# Complete environment variables for Django backend production deployment

# AWS Configuration
export AWS_PROFILE=lightwave-admin-new
export AWS_REGION=us-east-1

# Networking
export VPC_ID=vpc-02f48c62006cacfae
export DB_SUBNET_IDS=subnet-0ba0de978370667c6,subnet-0f6f1ca30b5154984
export PRIVATE_SUBNET_IDS=subnet-00e39a8d07f4c256b
export PUBLIC_SUBNET_IDS=subnet-0c51a5b50a08876a4,subnet-0b1a6a9c31139a96e

# Database (retrieve from Secrets Manager)
export DB_MASTER_USERNAME=postgres
export DB_MASTER_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id /lightwave/prod/database/master-password \
  --query 'SecretString' --output text)

# Container
export ECR_REPOSITORY_URL=738605694078.dkr.ecr.us-east-1.amazonaws.com/lightwave-django-backend
export IMAGE_TAG=latest  # or prod

# Django
export DJANGO_SECRET_KEY_ARN=arn:aws:secretsmanager:us-east-1:738605694078:secret:/lightwave/prod/django/secret-key-IiS699
export DJANGO_ALLOWED_HOSTS="*.lightwave-media.ltd,*.amazonaws.com"

# Cloudflare (retrieve from Secrets Manager)
export CLOUDFLARE_ZONE_ID=$(aws secretsmanager get-secret-value \
  --secret-id /lightwave/prod/cloudflare/zone-id \
  --query 'SecretString' --output text)
export CLOUDFLARE_API_TOKEN=$(aws secretsmanager get-secret-value \
  --secret-id /lightwave/prod/cloudflare/api-token \
  --query 'SecretString' --output text)
```

---

## Terragrunt Stack Configuration Mapping

### PostgreSQL Unit (stacks/django-backend-prod/terragrunt.stack.hcl:29-62)

| Input Parameter | Environment Variable | Resolved Value |
|----------------|---------------------|----------------|
| `vpc_id` | `VPC_ID` | vpc-02f48c62006cacfae |
| `subnet_ids` | `DB_SUBNET_IDS` (split by comma) | [subnet-0ba0de978370667c6, subnet-0f6f1ca30b5154984] |
| `master_username` | `DB_MASTER_USERNAME` | postgres |
| `master_password` | `DB_MASTER_PASSWORD` | Retrieved from Secrets Manager |

---

### Redis Unit (stacks/django-backend-prod/terragrunt.stack.hcl:67-92)

| Input Parameter | Environment Variable | Resolved Value |
|----------------|---------------------|----------------|
| `subnet_ids` | `PRIVATE_SUBNET_IDS` (split by comma) | [subnet-00e39a8d07f4c256b] |

---

### Django Service Unit (stacks/django-backend-prod/terragrunt.stack.hcl:97-148)

| Input Parameter | Environment Variable | Resolved Value |
|----------------|---------------------|----------------|
| `ecr_repository_url` | `ECR_REPOSITORY_URL` | 738605694078.dkr.ecr.us-east-1.amazonaws.com/lightwave-django-backend |
| `image_tag` | `IMAGE_TAG` | latest (or prod) |
| `django_secret_key_arn` | `DJANGO_SECRET_KEY_ARN` | arn:aws:secretsmanager:us-east-1:738605694078:secret:/lightwave/prod/django/secret-key-IiS699 |
| `django_allowed_hosts` | `DJANGO_ALLOWED_HOSTS` | *.lightwave-media.ltd,*.amazonaws.com |
| `vpc_id` | `VPC_ID` | vpc-02f48c62006cacfae |
| `private_subnet_ids` | `PRIVATE_SUBNET_IDS` (split by comma) | [subnet-00e39a8d07f4c256b] |
| `public_subnet_ids` | `PUBLIC_SUBNET_IDS` (split by comma) | [subnet-0c51a5b50a08876a4, subnet-0b1a6a9c31139a96e] |

---

### Cloudflare DNS Unit (stacks/django-backend-prod/terragrunt.stack.hcl:153-187)

| Input Parameter | Environment Variable | Resolved Value |
|----------------|---------------------|----------------|
| `zone_id` | `CLOUDFLARE_ZONE_ID` | 32139b65349431e3a0c7770b8842aac5 |
| Provider authentication | `CLOUDFLARE_API_TOKEN` | Retrieved from Secrets Manager |

**Note:** Cloudflare API token is used by the provider (configured in root.hcl), not passed as an input parameter.

---

## Dev Environment Secrets (for reference)

These secrets exist but are NOT used in production deployment:

| Secret Name | Purpose | Environment |
|------------|---------|-------------|
| `/lightwave/dev/django/secret-key` | Django SECRET_KEY | Development |
| `/lightwave/dev/django/database-url` | Full database connection string | Development |
| `/lightwave/dev/django/redis-url` | Full Redis connection string | Development |
| `/lightwave/dev/stripe/secret-key` | Stripe API secret key | Development |
| `/lightwave/dev/django/allowed-hosts` | Django ALLOWED_HOSTS | Development |

**Note:** Production uses separate secrets with `/lightwave/prod/` prefix.

---

## Security Notes

1. **Secrets Access:** All secrets are retrieved from AWS Secrets Manager at deployment time
2. **No Hardcoded Secrets:** No secrets are committed to git or stored in plain text
3. **IAM Permissions Required:**
   - `secretsmanager:GetSecretValue` for secret retrieval
   - `secretsmanager:DescribeSecret` for ARN lookup
   - `ecr:DescribeRepositories` for ECR discovery
   - `ecr:ListImages` for image tag discovery
4. **Token Scope:** Cloudflare API token has minimal permissions (DNS edit only for lightwave-media.ltd)

---

## Verification Commands

### Verify all secrets exist:
```bash
aws secretsmanager list-secrets \
  --filters Key=name,Values=/lightwave/prod/ \
  --query 'SecretList[*].Name'
```

### Verify ECR repository and images:
```bash
aws ecr describe-repositories --repository-names lightwave-django-backend
aws ecr list-images --repository-name lightwave-django-backend
```

### Verify VPC and subnets:
```bash
aws ec2 describe-vpcs --vpc-ids vpc-02f48c62006cacfae
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-02f48c62006cacfae"
```

### Test Cloudflare authentication:
```bash
CLOUDFLARE_API_TOKEN=$(aws secretsmanager get-secret-value \
  --secret-id /lightwave/prod/cloudflare/api-token \
  --query 'SecretString' --output text)

curl -X GET "https://api.cloudflare.com/client/v4/zones/32139b65349431e3a0c7770b8842aac5" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json"
```

---

## Next Steps

1. **Run deployment script:**
   ```bash
   source ./set-deployment-env.sh
   ```

2. **Verify all variables are set:**
   ```bash
   env | grep -E "(VPC_ID|DB_|ECR_|DJANGO_|CLOUDFLARE_)"
   ```

3. **Deploy to production:**
   ```bash
   make plan-prod
   make apply-prod
   ```

---

**Last Updated:** 2025-10-29
**Maintained By:** Infrastructure Team
**Review Required:** Before each production deployment
