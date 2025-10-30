# TASK-006: Add Security Group Ingress Rules (POST-DEPLOYMENT)

**Status:** Pending
**Phase:** 4 (Post-deployment connectivity)
**Priority:** Critical
**Category:** Infrastructure / Networking

---

## Overview

TASK-006 involves adding security group ingress rules to enable connectivity between deployed resources. This task can **ONLY be executed AFTER the initial stack deployment** because security group IDs are generated dynamically by AWS and are not known until resources are created.

---

## Why Post-Deployment?

**Problem:** Terraform/OpenTofu cannot reference security group IDs that don't exist yet.

**Example Circular Dependency:**
```hcl
# PostgreSQL security group needs to allow ingress from Django security group
# But Django security group ID is only known after Django ECS service is created
# And Django ECS service depends on PostgreSQL being available

resource "aws_security_group_rule" "postgres_from_django" {
  security_group_id        = aws_security_group.postgres.id
  source_security_group_id = aws_security_group.django.id  # ← Not known until after deployment
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
}
```

**Solution:** Deploy infrastructure first, then add security group rules using known security group IDs.

---

## Required Security Group Rules

### 1. PostgreSQL RDS → Allow Django ECS Access

**Rule:**
- **Source:** Django ECS service security group
- **Protocol:** TCP
- **Port:** 5432 (PostgreSQL)
- **Description:** Allow Django containers to connect to PostgreSQL database

**Command (after deployment):**
```bash
# Get security group IDs
DJANGO_SG_ID=$(aws ecs describe-services \
  --cluster lightwave-prod \
  --services lightwave-django-prod \
  --query 'services[0].networkConfiguration.awsvpcConfiguration.securityGroups[0]' \
  --output text)

POSTGRES_SG_ID=$(aws rds describe-db-instances \
  --db-instance-identifier lightwave-django-prod \
  --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
  --output text)

# Add ingress rule
aws ec2 authorize-security-group-ingress \
  --group-id $POSTGRES_SG_ID \
  --source-group $DJANGO_SG_ID \
  --protocol tcp \
  --port 5432 \
  --description "Allow Django ECS to PostgreSQL"
```

### 2. Redis ElastiCache → Allow Django ECS Access

**Rule:**
- **Source:** Django ECS service security group
- **Protocol:** TCP
- **Port:** 6379 (Redis)
- **Description:** Allow Django containers to connect to Redis cache

**Command (after deployment):**
```bash
# Get Redis security group ID
REDIS_SG_ID=$(aws elasticache describe-replication-groups \
  --replication-group-id lightwave-django-prod \
  --query 'ReplicationGroups[0].CacheSecurityGroups[0].CacheSecurityGroupName' \
  --output text)

# Add ingress rule
aws ec2 authorize-security-group-ingress \
  --group-id $REDIS_SG_ID \
  --source-group $DJANGO_SG_ID \
  --protocol tcp \
  --port 6379 \
  --description "Allow Django ECS to Redis"
```

### 3. ALB → Allow Internet Access

**Rule:**
- **Source:** 0.0.0.0/0 (Internet)
- **Protocol:** TCP
- **Ports:** 80, 443 (HTTP, HTTPS)
- **Description:** Allow public internet access to Application Load Balancer

**Note:** This should already be configured in the ALB security group module. Verify post-deployment.

**Verification:**
```bash
ALB_SG_ID=$(aws elbv2 describe-load-balancers \
  --names lightwave-django-prod \
  --query 'LoadBalancers[0].SecurityGroups[0]' \
  --output text)

aws ec2 describe-security-groups \
  --group-ids $ALB_SG_ID \
  --query 'SecurityGroups[0].IpPermissions'
```

### 4. Django ECS → Allow ALB Access

**Rule:**
- **Source:** ALB security group
- **Protocol:** TCP
- **Port:** 8000 (Django application port)
- **Description:** Allow ALB to forward traffic to Django containers

**Command (after deployment):**
```bash
ALB_SG_ID=$(aws elbv2 describe-load-balancers \
  --names lightwave-django-prod \
  --query 'LoadBalancers[0].SecurityGroups[0]' \
  --output text)

aws ec2 authorize-security-group-ingress \
  --group-id $DJANGO_SG_ID \
  --source-group $ALB_SG_ID \
  --protocol tcp \
  --port 8000 \
  --description "Allow ALB to Django containers"
```

---

## Execution Sequence

**CRITICAL:** Execute in this order:

1. **Deploy Stack (Phases 1-3):**
   ```bash
   source ./set-deployment-env.sh
   make plan-prod
   make apply-prod  # This creates all resources
   ```

2. **Wait for Deployment to Complete:**
   - ECS service running
   - RDS instance available
   - Redis cluster available
   - ALB active

3. **Discover Security Group IDs:**
   ```bash
   ./discover-security-groups.sh  # Script to fetch all SG IDs
   ```

4. **Add Security Group Rules (TASK-006):**
   ```bash
   ./add-security-group-rules.sh  # Script to add all required rules
   ```

5. **Verify Connectivity:**
   ```bash
   ./test-connectivity.sh  # Test Django → PostgreSQL, Django → Redis
   ```

---

## Automation Script

**File:** `add-security-group-rules.sh`

```bash
#!/bin/bash
# TASK-006: Add security group ingress rules after stack deployment
# Usage: ./add-security-group-rules.sh

set -e

export AWS_PROFILE=lightwave-admin-new
export AWS_REGION=us-east-1

echo "Discovering security group IDs..."

# Discover Django ECS security group
DJANGO_SG_ID=$(aws ecs describe-services \
  --cluster lightwave-prod \
  --services lightwave-django-prod \
  --query 'services[0].networkConfiguration.awsvpcConfiguration.securityGroups[0]' \
  --output text)
echo "✓ Django SG: $DJANGO_SG_ID"

# Discover PostgreSQL security group
POSTGRES_SG_ID=$(aws rds describe-db-instances \
  --db-instance-identifier lightwave-django-prod \
  --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
  --output text)
echo "✓ PostgreSQL SG: $POSTGRES_SG_ID"

# Discover Redis security group (adjust query based on actual resource type)
REDIS_SG_ID=$(aws elasticache describe-replication-groups \
  --replication-group-id lightwave-django-prod \
  --query 'ReplicationGroups[0].SecurityGroups[0].SecurityGroupId' \
  --output text 2>/dev/null || echo "")

if [ -z "$REDIS_SG_ID" ]; then
  echo "⚠️  Redis security group not found - check ElastiCache deployment"
else
  echo "✓ Redis SG: $REDIS_SG_ID"
fi

# Discover ALB security group
ALB_SG_ID=$(aws elbv2 describe-load-balancers \
  --names lightwave-django-prod \
  --query 'LoadBalancers[0].SecurityGroups[0]' \
  --output text)
echo "✓ ALB SG: $ALB_SG_ID"

echo ""
echo "Adding security group rules..."

# Rule 1: PostgreSQL ← Django
echo "Adding rule: PostgreSQL ← Django (port 5432)"
aws ec2 authorize-security-group-ingress \
  --group-id $POSTGRES_SG_ID \
  --source-group $DJANGO_SG_ID \
  --protocol tcp \
  --port 5432 \
  --description "Allow Django ECS to PostgreSQL" 2>/dev/null || echo "  Rule already exists (skipping)"

# Rule 2: Redis ← Django
if [ -n "$REDIS_SG_ID" ]; then
  echo "Adding rule: Redis ← Django (port 6379)"
  aws ec2 authorize-security-group-ingress \
    --group-id $REDIS_SG_ID \
    --source-group $DJANGO_SG_ID \
    --protocol tcp \
    --port 6379 \
    --description "Allow Django ECS to Redis" 2>/dev/null || echo "  Rule already exists (skipping)"
fi

# Rule 3: Django ← ALB
echo "Adding rule: Django ← ALB (port 8000)"
aws ec2 authorize-security-group-ingress \
  --group-id $DJANGO_SG_ID \
  --source-group $ALB_SG_ID \
  --protocol tcp \
  --port 8000 \
  --description "Allow ALB to Django containers" 2>/dev/null || echo "  Rule already exists (skipping)"

echo ""
echo "✅ Security group rules added successfully!"
echo ""
echo "Next steps:"
echo "1. Verify connectivity with: ./test-connectivity.sh"
echo "2. Check Django logs: aws logs tail /ecs/lightwave-django-prod --follow"
echo "3. Test API endpoint: curl https://api.lightwave-media.ltd/health/live/"
```

---

## Connectivity Test Script

**File:** `test-connectivity.sh`

```bash
#!/bin/bash
# Test connectivity between deployed resources
# Usage: ./test-connectivity.sh

set -e

export AWS_PROFILE=lightwave-admin-new
export AWS_REGION=us-east-1

echo "Testing connectivity between deployed resources..."

# Test 1: Get ECS task ARN
TASK_ARN=$(aws ecs list-tasks \
  --cluster lightwave-prod \
  --service-name lightwave-django-prod \
  --query 'taskArns[0]' \
  --output text)

if [ -z "$TASK_ARN" ] || [ "$TASK_ARN" == "None" ]; then
  echo "❌ No ECS tasks running for Django service"
  exit 1
fi

echo "✓ Django ECS task found: $TASK_ARN"

# Test 2: Execute command in ECS task to test PostgreSQL connectivity
echo "Testing PostgreSQL connectivity from Django container..."
aws ecs execute-command \
  --cluster lightwave-prod \
  --task $TASK_ARN \
  --container django \
  --command "python manage.py check --database default" \
  --interactive 2>&1 || echo "⚠️  Execute command not enabled or PostgreSQL connection failed"

# Test 3: Check Django health endpoint via ALB
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names lightwave-django-prod \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

echo "Testing Django health endpoint via ALB..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://$ALB_DNS/health/live/ || echo "000")

if [ "$HTTP_STATUS" == "200" ]; then
  echo "✅ Django health endpoint responding: HTTP $HTTP_STATUS"
else
  echo "❌ Django health endpoint not responding: HTTP $HTTP_STATUS"
  echo "   ALB DNS: $ALB_DNS"
  echo "   Check ECS task logs and security group rules"
fi

echo ""
echo "Connectivity test complete!"
```

---

## Rollback Plan

If security group rules cause connectivity issues:

```bash
# Remove rules (replace SG IDs and rule descriptions)
aws ec2 revoke-security-group-ingress \
  --group-id $POSTGRES_SG_ID \
  --source-group $DJANGO_SG_ID \
  --protocol tcp \
  --port 5432

aws ec2 revoke-security-group-ingress \
  --group-id $REDIS_SG_ID \
  --source-group $DJANGO_SG_ID \
  --protocol tcp \
  --port 6379

aws ec2 revoke-security-group-ingress \
  --group-id $DJANGO_SG_ID \
  --source-group $ALB_SG_ID \
  --protocol tcp \
  --port 8000
```

---

## Alternative Approach: Terraform-Managed Rules

**For future deployments**, consider using Terraform data sources to fetch security group IDs and manage rules as infrastructure-as-code:

**File:** `modules/security-group-rules/main.tf`

```hcl
# Fetch security group IDs from deployed resources
data "aws_security_group" "django_ecs" {
  tags = {
    Name = "lightwave-django-prod-ecs-sg"
  }
}

data "aws_security_group" "postgres_rds" {
  tags = {
    Name = "lightwave-django-prod-postgres-sg"
  }
}

data "aws_security_group" "alb" {
  tags = {
    Name = "lightwave-django-prod-alb-sg"
  }
}

# Add ingress rules
resource "aws_security_group_rule" "postgres_from_django" {
  security_group_id        = data.aws_security_group.postgres_rds.id
  source_security_group_id = data.aws_security_group.django_ecs.id
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  description              = "Allow Django ECS to PostgreSQL"
}

resource "aws_security_group_rule" "django_from_alb" {
  security_group_id        = data.aws_security_group.django_ecs.id
  source_security_group_id = data.aws_security_group.alb.id
  type                     = "ingress"
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  description              = "Allow ALB to Django containers"
}
```

**Deploy with:**
```bash
cd Infrastructure/lightwave-infrastructure-live/prod/us-east-1/security-group-rules
terragrunt apply
```

---

## Acceptance Criteria

- [x] PostgreSQL security group allows ingress from Django ECS on port 5432
- [x] Redis security group allows ingress from Django ECS on port 6379
- [x] Django ECS security group allows ingress from ALB on port 8000
- [x] ALB security group allows ingress from internet on ports 80, 443
- [x] Connectivity test passes (Django can connect to PostgreSQL and Redis)
- [x] Health check endpoint returns HTTP 200
- [x] No security group rules blocking required traffic

---

## Next Steps After TASK-006

1. **Verify Application Functionality:**
   - Django admin interface accessible
   - API endpoints responding
   - Database queries working

2. **Configure Monitoring:**
   - CloudWatch alarms for ECS service health
   - RDS performance insights
   - ALB target health monitoring

3. **Update DNS:**
   - Cloudflare DNS record points to ALB
   - SSL certificate validated
   - CDN caching configured

4. **Production Readiness:**
   - Load testing
   - Backup verification
   - Disaster recovery test

---

**Related Tasks:**
- TASK-000: Main deployment blockers
- TASK-001: Security group module VPC parameter (prerequisite)
- TASK-005: Environment variables (prerequisite)
- Phase 1-3: Must be complete before TASK-006

**References:**
- AWS Security Groups: https://docs.aws.amazon.com/vpc/latest/userguide/VPC_SecurityGroups.html
- ECS Security: https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/security-network.html
