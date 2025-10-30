# Django Backend Production Deployment - Environment Variables

**Purpose:** Required environment variables for deploying the Django backend stack to production

**Last Updated:** 2025-10-29
**Related Task:** TASK-005 - Configure Deployment Environment Variables

---

## Quick Start

```bash
# Source this file before deployment
source ./set-deployment-env.sh

# Or manually export all variables below
export AWS_PROFILE=lightwave-admin-new
export AWS_REGION=us-east-1
export VPC_ID=vpc-02f48c62006cacfae
# ... (continue with all variables)
```

---

## Required Environment Variables

### AWS Configuration

#### `AWS_PROFILE`
- **Description:** AWS CLI profile with admin permissions
- **Value:** `lightwave-admin-new`
- **Required for:** All AWS API calls
- **Verification:** `aws sts get-caller-identity --profile lightwave-admin-new`

#### `AWS_REGION`
- **Description:** AWS region for infrastructure deployment
- **Value:** `us-east-1`
- **Required for:** All AWS resource creation
- **Default:** Already set in Makefile

---

### Networking Configuration

#### `VPC_ID`
- **Description:** VPC ID where all infrastructure will be deployed
- **Value:** `vpc-02f48c62006cacfae` (lightwave-dev-vpc)
- **Required for:**
  - PostgreSQL RDS security groups
  - Redis ElastiCache configuration
  - ECS Fargate services
  - ALB deployment
- **Discovery Command:**
  ```bash
  aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=lightwave-dev-vpc" \
    --query 'Vpcs[0].VpcId' --output text
  ```

#### `DB_SUBNET_IDS`
- **Description:** Comma-separated list of database subnet IDs (private-persistence tier)
- **Value:** `subnet-0ba0de978370667c6,subnet-0f6f1ca30b5154984`
- **Required for:**
  - PostgreSQL RDS (Multi-AZ deployment)
  - Redis ElastiCache
- **Requirements:**
  - Must span at least 2 AZs (Multi-AZ requirement)
  - Must be in `private-persistence` tier (not public)
  - Must be in same VPC as `VPC_ID`
- **Discovery Command:**
  ```bash
  aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Tier,Values=private-persistence" \
    --query 'Subnets[*].SubnetId' --output text | tr '\t' ','
  ```

#### `PRIVATE_SUBNET_IDS`
- **Description:** Comma-separated list of private app subnet IDs (for ECS Fargate)
- **Value:** `subnet-00e39a8d07f4c256b` (currently only 1 AZ)
- **Required for:**
  - ECS Fargate tasks (Django containers)
  - Redis ElastiCache (alternative to DB_SUBNET_IDS)
- **Discovery Command:**
  ```bash
  aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Tier,Values=private-app" \
    --query 'Subnets[*].SubnetId' --output text | tr '\t' ','
  ```

#### `PUBLIC_SUBNET_IDS`
- **Description:** Comma-separated list of public subnet IDs (for ALB)
- **Value:** `subnet-0c51a5b50a08876a4,subnet-0b1a6a9c31139a96e`
- **Required for:**
  - Application Load Balancer (internet-facing)
  - NAT Gateways (if needed)
- **Requirements:**
  - Must have route to Internet Gateway
  - Must span at least 2 AZs (ALB requirement)
- **Discovery Command:**
  ```bash
  aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Tier,Values=public-dmz" \
    --query 'Subnets[*].SubnetId' --output text | tr '\t' ','
  ```

---

### Database Configuration

#### `DB_MASTER_USERNAME`
- **Description:** PostgreSQL master username
- **Value:** `postgres` (default) or custom username
- **Required for:** RDS PostgreSQL instance creation
- **Default:** `postgres`
- **Security Note:** Change default for production deployments

#### `DB_MASTER_PASSWORD`
- **Description:** PostgreSQL master password
- **Value:** **REQUIRED** - Must be set from AWS Secrets Manager
- **Required for:** RDS PostgreSQL instance creation
- **Security:**
  - Do NOT hardcode in files
  - Store in AWS Secrets Manager
  - Retrieve dynamically in deployment scripts
- **Retrieval Command:**
  ```bash
  export DB_MASTER_PASSWORD=$(aws secretsmanager get-secret-value \
    --secret-id lightwave/prod/db/master-password \
    --query 'SecretString' --output text)
  ```

---

### Container Configuration

#### `ECR_REPOSITORY_URL`
- **Description:** Full ECR repository URL for Django Docker images
- **Value:** **REQUIRED** - Format: `{account-id}.dkr.ecr.{region}.amazonaws.com/{repo-name}`
- **Example:** `738605694078.dkr.ecr.us-east-1.amazonaws.com/lightwave-django`
- **Required for:** ECS Fargate task definition
- **Discovery Command:**
  ```bash
  aws ecr describe-repositories \
    --repository-names lightwave-django \
    --query 'repositories[0].repositoryUri' --output text
  ```

#### `IMAGE_TAG`
- **Description:** Docker image tag to deploy
- **Value:** `prod` (default) or specific version tag
- **Required for:** ECS Fargate task definition
- **Default:** `prod`
- **Examples:** `prod`, `v1.2.3`, `sha-a1b2c3d`

---

### Django Application Configuration

#### `DJANGO_SECRET_KEY_ARN`
- **Description:** ARN of AWS Secrets Manager secret containing Django SECRET_KEY
- **Value:** **REQUIRED** - Format: `arn:aws:secretsmanager:{region}:{account-id}:secret:{name}`
- **Example:** `arn:aws:secretsmanager:us-east-1:738605694078:secret:lightwave/prod/django/secret-key-AbCdEf`
- **Required for:** Django application security (session signing, CSRF protection)
- **Security:**
  - Never expose in logs or environment variables
  - ECS task definition references ARN only
  - Django app retrieves secret at runtime
- **Discovery Command:**
  ```bash
  aws secretsmanager list-secrets \
    --filters Key=name,Values=lightwave/prod/django/secret-key \
    --query 'SecretList[0].ARN' --output text
  ```

#### `DJANGO_SETTINGS_MODULE`
- **Description:** Django settings module to use
- **Value:** `config.settings.prod` (hardcoded in stack)
- **Required for:** Django application configuration
- **Note:** Set in stack configuration, not as environment variable

#### `DJANGO_ALLOWED_HOSTS`
- **Description:** Comma-separated list of allowed hosts for Django
- **Value:** `*.lightwave-media.ltd,*.amazonaws.com` (default)
- **Required for:** Django host header validation
- **Default:** `*.lightwave-media.ltd,*.amazonaws.com`
- **Examples:**
  - `api.lightwave-media.ltd,*.amazonaws.com`
  - `*.lightwave-media.ltd,localhost`

---

### Cloudflare Configuration

#### `CLOUDFLARE_ZONE_ID`
- **Description:** Cloudflare Zone ID for lightwave-media.ltd domain
- **Value:** **REQUIRED** - Obtain from Cloudflare dashboard
- **Required for:** DNS record creation (api.lightwave-media.ltd)
- **Discovery:**
  1. Log in to Cloudflare dashboard
  2. Select `lightwave-media.ltd` domain
  3. Zone ID is in the sidebar under "API" section
- **Format:** 32-character hex string

#### `CLOUDFLARE_API_TOKEN`
- **Description:** Cloudflare API token with DNS edit permissions
- **Value:** **REQUIRED** - Create in Cloudflare dashboard
- **Required for:** Terraform Cloudflare provider authentication
- **Security:**
  - Do NOT hardcode in files
  - Store in AWS Secrets Manager or environment variable
  - Scope token to DNS edit only
- **Permissions Required:**
  - Zone.DNS Edit
  - Zone.Zone Read
- **Creation:**
  1. Cloudflare Dashboard → My Profile → API Tokens
  2. Create Token → Edit zone DNS template
  3. Select `lightwave-media.ltd` zone
  4. Create token and save securely

#### `ALB_DNS_NAME`
- **Description:** ALB DNS name (obtained from Django service deployment)
- **Value:** **DYNAMIC** - Available after ECS service deployment
- **Required for:** Cloudflare DNS CNAME record creation
- **Note:** This is an output from the Django ECS service, not a pre-deployment input
- **Discovery Command (after deployment):**
  ```bash
  aws elbv2 describe-load-balancers \
    --names lightwave-django-prod \
    --query 'LoadBalancers[0].DNSName' --output text
  ```

---

## Environment Variable Template

Copy this template to create your deployment script:

```bash
#!/bin/bash
# Deployment environment variables for Django backend production stack
# Usage: source ./set-deployment-env.sh

set -e

echo "Setting deployment environment variables..."

# AWS Configuration
export AWS_PROFILE=lightwave-admin-new
export AWS_REGION=us-east-1

# Networking (discovered from VPC)
export VPC_ID=vpc-02f48c62006cacfae
export DB_SUBNET_IDS=subnet-0ba0de978370667c6,subnet-0f6f1ca30b5154984
export PRIVATE_SUBNET_IDS=subnet-00e39a8d07f4c256b
export PUBLIC_SUBNET_IDS=subnet-0c51a5b50a08876a4,subnet-0b1a6a9c31139a96e

# Database (TODO: Retrieve from Secrets Manager)
export DB_MASTER_USERNAME=postgres
export DB_MASTER_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id lightwave/prod/db/master-password \
  --query 'SecretString' --output text 2>/dev/null || echo "")

if [ -z "$DB_MASTER_PASSWORD" ]; then
  echo "⚠️  WARNING: DB_MASTER_PASSWORD not retrieved from Secrets Manager"
  echo "    Please set manually or create secret: lightwave/prod/db/master-password"
fi

# Container Configuration (TODO: Update with actual ECR repo URL)
export ECR_REPOSITORY_URL=738605694078.dkr.ecr.us-east-1.amazonaws.com/lightwave-django
export IMAGE_TAG=prod

# Django Configuration (TODO: Retrieve from Secrets Manager)
export DJANGO_SECRET_KEY_ARN=$(aws secretsmanager list-secrets \
  --filters Key=name,Values=lightwave/prod/django/secret-key \
  --query 'SecretList[0].ARN' --output text 2>/dev/null || echo "")

if [ -z "$DJANGO_SECRET_KEY_ARN" ]; then
  echo "⚠️  WARNING: DJANGO_SECRET_KEY_ARN not found in Secrets Manager"
  echo "    Please create secret: lightwave/prod/django/secret-key"
fi

export DJANGO_ALLOWED_HOSTS="*.lightwave-media.ltd,*.amazonaws.com"

# Cloudflare Configuration (TODO: Set from Cloudflare dashboard)
export CLOUDFLARE_ZONE_ID=""
export CLOUDFLARE_API_TOKEN=""

if [ -z "$CLOUDFLARE_ZONE_ID" ]; then
  echo "⚠️  WARNING: CLOUDFLARE_ZONE_ID not set"
  echo "    Please obtain from Cloudflare dashboard"
fi

if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
  echo "⚠️  WARNING: CLOUDFLARE_API_TOKEN not set"
  echo "    Please create API token with DNS edit permissions"
fi

# Verification
echo ""
echo "✅ Environment variables set:"
echo "   AWS_PROFILE=$AWS_PROFILE"
echo "   AWS_REGION=$AWS_REGION"
echo "   VPC_ID=$VPC_ID"
echo "   DB_SUBNET_IDS=$DB_SUBNET_IDS"
echo "   PRIVATE_SUBNET_IDS=$PRIVATE_SUBNET_IDS"
echo "   PUBLIC_SUBNET_IDS=$PUBLIC_SUBNET_IDS"
echo "   DB_MASTER_USERNAME=$DB_MASTER_USERNAME"
echo "   DB_MASTER_PASSWORD=$([ -n "$DB_MASTER_PASSWORD" ] && echo "***SET***" || echo "NOT SET")"
echo "   ECR_REPOSITORY_URL=$ECR_REPOSITORY_URL"
echo "   IMAGE_TAG=$IMAGE_TAG"
echo "   DJANGO_SECRET_KEY_ARN=$([ -n "$DJANGO_SECRET_KEY_ARN" ] && echo "$DJANGO_SECRET_KEY_ARN" || echo "NOT SET")"
echo "   DJANGO_ALLOWED_HOSTS=$DJANGO_ALLOWED_HOSTS"
echo "   CLOUDFLARE_ZONE_ID=$([ -n "$CLOUDFLARE_ZONE_ID" ] && echo "$CLOUDFLARE_ZONE_ID" || echo "NOT SET")"
echo "   CLOUDFLARE_API_TOKEN=$([ -n "$CLOUDFLARE_API_TOKEN" ] && echo "***SET***" || echo "NOT SET")"
echo ""
echo "Ready for deployment!"
```

---

## Pre-Deployment Checklist

Before running `make apply-prod`, verify all environment variables are set:

```bash
# Run this verification script
./verify-deployment-env.sh
```

**Verification script:**
```bash
#!/bin/bash
# Verify all required environment variables are set

MISSING=()

check_var() {
  if [ -z "${!1}" ]; then
    MISSING+=("$1")
    echo "❌ $1 is NOT set"
  else
    echo "✅ $1 is set"
  fi
}

echo "Checking required environment variables..."
echo ""

check_var AWS_PROFILE
check_var AWS_REGION
check_var VPC_ID
check_var DB_SUBNET_IDS
check_var PRIVATE_SUBNET_IDS
check_var PUBLIC_SUBNET_IDS
check_var DB_MASTER_USERNAME
check_var DB_MASTER_PASSWORD
check_var ECR_REPOSITORY_URL
check_var DJANGO_SECRET_KEY_ARN
check_var CLOUDFLARE_ZONE_ID

echo ""
if [ ${#MISSING[@]} -eq 0 ]; then
  echo "✅ All required environment variables are set!"
  exit 0
else
  echo "❌ Missing ${#MISSING[@]} required environment variable(s)"
  echo ""
  echo "Missing variables:"
  for var in "${MISSING[@]}"; do
    echo "  - $var"
  done
  exit 1
fi
```

---

## Security Best Practices

1. **Never commit secrets to git:**
   - Add `set-deployment-env.sh` to `.gitignore`
   - Use AWS Secrets Manager for sensitive values
   - Use environment variables for deployment-time injection

2. **Use AWS Secrets Manager:**
   ```bash
   # Create secret
   aws secretsmanager create-secret \
     --name lightwave/prod/db/master-password \
     --secret-string "$(openssl rand -base64 32)"

   # Create Django secret key
   aws secretsmanager create-secret \
     --name lightwave/prod/django/secret-key \
     --secret-string "$(python -c 'from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())')"
   ```

3. **Restrict API token permissions:**
   - Cloudflare API token should only have DNS edit for lightwave-media.ltd
   - Do NOT use Global API Key
   - Set token expiration

4. **Rotate secrets regularly:**
   - Database passwords: Every 90 days
   - Django SECRET_KEY: Every 90 days
   - API tokens: Every 90 days

---

## Troubleshooting

### Issue: "Required environment variable not found"

**Cause:** Environment variable not exported before running terragrunt

**Solution:**
```bash
source ./set-deployment-env.sh
# Or manually export the missing variable
```

### Issue: "Invalid VPC ID"

**Cause:** VPC_ID is incorrect or VPC doesn't exist

**Solution:**
```bash
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=lightwave-dev-vpc"
```

### Issue: "Subnet not found in VPC"

**Cause:** Subnet IDs don't match VPC or subnet doesn't exist

**Solution:**
```bash
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID"
```

### Issue: "Access denied to Secrets Manager"

**Cause:** AWS profile doesn't have secretsmanager:GetSecretValue permission

**Solution:**
```bash
# Verify IAM permissions
aws iam get-user --profile lightwave-admin-new
# Add secretsmanager:GetSecretValue to IAM policy
```

---

## Related Documentation

- **TASK-000:** Main deployment blockers task
- **TASK-001:** Security group VPC parameter (requires VPC_ID)
- **TASK-002:** PostgreSQL subnet groups (requires DB_SUBNET_IDS)
- **TASK-003:** Public subnets (provides PUBLIC_SUBNET_IDS)
- **TASK-004:** Django VPC parameterization (requires VPC_ID)
- **TASK-007:** Cloudflare provider configuration (requires CLOUDFLARE_ZONE_ID, CLOUDFLARE_API_TOKEN)

---

**Next Steps:**
1. Copy environment variable template to `set-deployment-env.sh`
2. Fill in missing values (Cloudflare credentials)
3. Create AWS Secrets Manager secrets for sensitive values
4. Run verification script
5. Proceed with `make plan-prod`
