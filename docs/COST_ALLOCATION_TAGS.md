# Cost Allocation Tags - LightWave Media

This document defines the cost allocation tagging strategy for LightWave Media's AWS infrastructure. Consistent tagging enables accurate cost tracking, budget allocation, and optimization opportunities.

## Table of Contents

- [Required Tags](#required-tags)
- [Tag Implementation](#tag-implementation)
- [Tag Activation](#tag-activation)
- [Cost Reports by Tag](#cost-reports-by-tag)
- [Best Practices](#best-practices)
- [Examples](#examples)

---

## Required Tags

All AWS resources MUST include the following tags:

### Core Tags

| Tag Key | Description | Values | Example |
|---------|-------------|--------|---------|
| `Environment` | Deployment environment | `prod`, `non-prod`, `dev`, `staging` | `prod` |
| `ManagedBy` | Management tool | `Terragrunt`, `Manual`, `CloudFormation` | `Terragrunt` |
| `Owner` | Responsible team or person | Team name or email | `Platform Team` |
| `CostCenter` | Department or business unit | Department name | `Engineering` |
| `Project` | Project or product name | Project identifier | `LightWave Media` |

### Optional but Recommended Tags

| Tag Key | Description | Values | Example |
|---------|-------------|--------|---------|
| `Service` | Application or service name | Service identifier | `backend`, `frontend` |
| `Component` | Infrastructure component | Component type | `database`, `cache`, `compute` |
| `Backup` | Backup retention requirement | `true`, `false`, retention days | `true` |
| `Compliance` | Compliance requirements | Compliance standard | `HIPAA`, `PCI-DSS` |
| `DataClassification` | Data sensitivity level | `public`, `internal`, `confidential` | `internal` |

---

## Tag Implementation

### 1. Provider-Level Default Tags (Recommended)

Apply tags automatically to all resources using the AWS provider's `default_tags` feature in Terraform/OpenTofu.

**In `root.hcl`:**

```hcl
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.aws_region}"

  # Default tags applied to all resources
  default_tags {
    tags = {
      Environment = "${local.account_name}"
      ManagedBy   = "Terragrunt"
      Owner       = "Platform Team"
      CostCenter  = "Engineering"
      Project     = "LightWave Media"
      Repository  = "lightwave-infrastructure-live"
    }
  }
}
EOF
}
```

**Benefit:** All resources automatically inherit these tags without explicit declaration.

### 2. Resource-Specific Tags

Add additional tags at the resource level for finer granularity:

```hcl
resource "aws_db_instance" "postgres" {
  identifier     = "prod-postgres"
  instance_class = "db.t3.medium"

  tags = {
    Name      = "prod-postgres"
    Service   = "backend"
    Component = "database"
    Backup    = "true"
  }
}
```

### 3. Module-Level Tags

Pass tags as variables to reusable modules:

```hcl
module "backend_service" {
  source = "../../modules/ecs-fargate-service"

  name = "backend-prod"

  tags = merge(
    local.common_tags,
    {
      Service   = "backend"
      Component = "compute"
    }
  )
}
```

---

## Tag Activation

AWS Cost Explorer requires tags to be activated before they appear in cost reports.

### Activate Cost Allocation Tags

```bash
# List available tags
aws ce list-cost-allocation-tags

# Activate tags for cost allocation
aws ce update-cost-allocation-tags-status \
  --cost-allocation-tags-status \
    TagKey=Environment,Status=Active \
    TagKey=ManagedBy,Status=Active \
    TagKey=Owner,Status=Active \
    TagKey=CostCenter,Status=Active \
    TagKey=Project,Status=Active \
    TagKey=Service,Status=Active \
    TagKey=Component,Status=Active

# Verify activation
aws ce list-cost-allocation-tags --status Active
```

**Note:** It may take up to 24 hours for activated tags to appear in Cost Explorer.

---

## Cost Reports by Tag

### 1. Cost by Environment

```bash
aws ce get-cost-and-usage \
  --time-period Start=2025-10-01,End=2025-10-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=TAG,Key=Environment \
  --output table
```

### 2. Cost by Service

```bash
aws ce get-cost-and-usage \
  --time-period Start=2025-10-01,End=2025-10-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=TAG,Key=Service \
  --output table
```

### 3. Cost by Owner/Team

```bash
aws ce get-cost-and-usage \
  --time-period Start=2025-10-01,End=2025-10-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=TAG,Key=Owner \
  --output table
```

### 4. Untagged Resources

Identify resources missing required tags:

```bash
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Environment,Values= \
  --resource-type-filters ec2 rds elasticache s3
```

---

## Best Practices

### 1. Tag Consistency

- Use lowercase for tag values where possible
- Use hyphens for multi-word values: `non-prod` not `NonProd`
- Avoid special characters except hyphens and underscores

### 2. Tag Validation

Use pre-commit hooks to validate tags before deployment:

```yaml
# .pre-commit-config.yaml
- repo: local
  hooks:
    - id: validate-tags
      name: Validate AWS Tags
      entry: ./scripts/validate-tags.sh
      language: script
      files: \.tf$
```

### 3. Tag Auditing

Schedule regular tag audits to ensure compliance:

```bash
# Run weekly via cron
./scripts/audit-tags.sh > reports/tag-audit-$(date +%Y-%m-%d).txt
```

### 4. Tag Naming Conventions

- **PascalCase** for tag keys: `Environment`, `CostCenter`
- **lowercase or kebab-case** for tag values: `prod`, `non-prod`
- Avoid abbreviations unless well-known

### 5. Tag Governance

- Document all approved tags in this file
- Require team approval before adding new tag keys
- Review and deprecate unused tags quarterly

---

## Examples

### Example 1: Production RDS Instance

```hcl
resource "aws_db_instance" "prod_postgres" {
  identifier     = "lightwave-prod-postgres"
  instance_class = "db.t3.medium"
  engine         = "postgres"

  tags = {
    Name               = "lightwave-prod-postgres"
    Environment        = "prod"
    ManagedBy          = "Terragrunt"
    Owner              = "Backend Team"
    CostCenter         = "Engineering"
    Project            = "LightWave Media"
    Service            = "backend"
    Component          = "database"
    Backup             = "true"
    DataClassification = "internal"
  }
}
```

**Cost Allocation:**
- Charged to: Engineering department
- Environment: Production
- Service: Backend
- Owner: Backend Team

### Example 2: Development ECS Service

```hcl
resource "aws_ecs_service" "dev_backend" {
  name            = "backend-dev"
  cluster         = aws_ecs_cluster.dev.id
  task_definition = aws_ecs_task_definition.backend_dev.arn

  tags = {
    Name        = "backend-dev"
    Environment = "dev"
    ManagedBy   = "Terragrunt"
    Owner       = "Platform Team"
    CostCenter  = "Engineering"
    Project     = "LightWave Media"
    Service     = "backend"
    Component   = "compute"
  }
}
```

**Cost Allocation:**
- Charged to: Engineering department
- Environment: Development
- Service: Backend
- Owner: Platform Team

### Example 3: Shared S3 Bucket

```hcl
resource "aws_s3_bucket" "media_assets" {
  bucket = "lightwave-media-assets-prod"

  tags = {
    Name        = "lightwave-media-assets-prod"
    Environment = "prod"
    ManagedBy   = "Terragrunt"
    Owner       = "Platform Team"
    CostCenter  = "Engineering"
    Project     = "LightWave Media"
    Service     = "shared"
    Component   = "storage"
    Backup      = "true"
  }
}
```

**Cost Allocation:**
- Charged to: Engineering department (shared across services)
- Environment: Production
- Service: Shared
- Owner: Platform Team

### Example 4: Using Locals for Consistent Tags

```hcl
# locals.tf
locals {
  common_tags = {
    Environment = "prod"
    ManagedBy   = "Terragrunt"
    Owner       = "Platform Team"
    CostCenter  = "Engineering"
    Project     = "LightWave Media"
  }

  backend_tags = merge(
    local.common_tags,
    {
      Service   = "backend"
      Component = "compute"
    }
  )
}

# Use in resources
resource "aws_ecs_service" "backend" {
  name = "backend-prod"
  tags = local.backend_tags
}
```

---

## Tag Verification Script

Create a script to verify all resources have required tags:

```bash
#!/usr/bin/env bash
# scripts/verify-tags.sh

REQUIRED_TAGS="Environment ManagedBy Owner CostCenter Project"

echo "Checking for resources missing required tags..."

for tag in $REQUIRED_TAGS; do
  echo "Checking for resources missing: $tag"

  aws resourcegroupstaggingapi get-resources \
    --tag-filters Key=$tag,Values= \
    --query 'ResourceTagMappingList[*].ResourceARN' \
    --output text
done
```

---

## Cost Allocation Report Example

After activating tags, you can generate detailed cost allocation reports:

```bash
# Generate monthly cost report by environment and service
aws ce get-cost-and-usage \
  --time-period Start=2025-10-01,End=2025-10-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=TAG,Key=Environment Type=TAG,Key=Service \
  --filter file://filter.json \
  --output json | jq -r '
    .ResultsByTime[0].Groups[] |
    "\(.Keys[0])\t\(.Keys[1])\t$\(.Metrics.BlendedCost.Amount)"
  ' | column -t
```

**Output:**
```
Environment  Service   Cost
prod         backend   $280.50
prod         frontend  $120.00
non-prod     backend   $45.20
non-prod     frontend  $30.00
```

---

## Related Documents

- [AWS Cost Allocation Tags Documentation](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/cost-alloc-tags.html)
- [Terraform AWS Provider Default Tags](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#default_tags)
- [SOP: Cost Management](../.agent/sops/SOP_COST_MANAGEMENT.md)
- [Naming Conventions](../../.agent/metadata/naming_conventions.yaml)

---

**Last Updated:** 2025-10-29
**Maintained By:** Platform Team
**Version:** 1.0.0
