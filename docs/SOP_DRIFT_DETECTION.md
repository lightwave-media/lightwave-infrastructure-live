# SOP: Infrastructure Drift Detection and Resolution

**Version:** 1.0.0
**Last Updated:** 2025-10-29
**Owner:** Platform Team
**Purpose:** Detect and resolve configuration drift between Terraform state and live AWS resources to maintain infrastructure consistency and prevent unexpected behavior.

---

## Table of Contents

1. [Overview](#overview)
2. [What is Infrastructure Drift?](#what-is-infrastructure-drift)
3. [Drift Detection Methods](#drift-detection-methods)
4. [Running Drift Detection](#running-drift-detection)
5. [Analyzing Drift Reports](#analyzing-drift-reports)
6. [Drift Resolution Procedures](#drift-resolution-procedures)
7. [Common Drift Scenarios](#common-drift-scenarios)
8. [Prevention Strategies](#prevention-strategies)
9. [Alerting and Notifications](#alerting-and-notifications)
10. [Troubleshooting](#troubleshooting)

---

## Overview

Infrastructure drift occurs when the actual state of AWS resources differs from what's defined in Terraform code. This can happen due to:

- Manual changes in AWS console
- Changes made by AWS services (auto-scaling, managed services)
- Emergency fixes applied outside normal deployment process
- Third-party tools modifying resources
- AWS API changes or service updates

Undetected drift can lead to:
- Failed deployments
- Security vulnerabilities
- Configuration inconsistencies
- Unexpected behavior
- Data loss

This SOP establishes procedures for detecting, analyzing, and resolving infrastructure drift.

---

## What is Infrastructure Drift?

### Types of Drift

#### 1. Acceptable Drift
**Definition:** Expected changes made by AWS services or auto-scaling.

**Examples:**
- ECS service `desired_count` changed by auto-scaling
- Auto Scaling Group instance counts
- CloudWatch alarm state changes
- DynamoDB throughput adjusted by auto-scaling
- Tags added by AWS Cost Explorer

**Action:** Add lifecycle rules to ignore these attributes.

#### 2. Intentional Drift
**Definition:** Manual changes made during incidents or emergencies.

**Examples:**
- Security group rule added during security incident
- RDS instance stopped to reduce costs
- ECS task count increased during traffic spike
- Resource tags modified for cost tracking

**Action:** Update Terraform code to reflect changes, then apply.

#### 3. Unintended Drift
**Definition:** Accidental or unauthorized manual changes.

**Examples:**
- Developer testing in console
- Misconfigured third-party tool
- Mistake during troubleshooting
- Unauthorized configuration change

**Action:** Revert changes by applying Terraform.

#### 4. Critical Drift
**Definition:** Changes to security-sensitive resources.

**Examples:**
- Security group rules modified
- IAM roles/policies changed
- Database security settings altered
- Network ACLs modified
- KMS key policies changed

**Action:** Immediate investigation and remediation required.

---

## Drift Detection Methods

### Method 1: Automated Scheduled Detection (Recommended)

**Frequency:** Daily at 6am UTC

**How it works:**
- GitHub Actions workflow runs `terragrunt plan`
- Compares Terraform state with live AWS resources
- Generates drift report
- Creates GitHub issue if critical drift detected
- Sends Slack notification (if configured)

**Advantages:**
- Automatic and consistent
- Early detection of issues
- Audit trail via GitHub Actions
- No manual intervention required

### Method 2: Manual Detection

**When to use:**
- Before deployments
- After incidents
- During troubleshooting
- When investigating suspected drift

**How to run:**
```bash
# Detect drift in non-prod
make detect-drift-nonprod

# Detect drift in production
make detect-drift-prod

# Detect drift in all environments
make detect-drift-all
```

### Method 3: Pre-Deployment Detection

**When to use:** Before every `terragrunt apply`

**How it works:**
- Run `terragrunt plan` before applying
- Review output for unexpected changes
- Investigate any changes not in your PR

---

## Running Drift Detection

### Prerequisites

- AWS credentials configured (`AWS_PROFILE=lightwave-admin-new`)
- Terragrunt and OpenTofu installed (`mise install`)
- Access to target environment

### Local Drift Detection

**Non-Production:**
```bash
cd Infrastructure/lightwave-infrastructure-live
export AWS_PROFILE=lightwave-admin-new

# Run drift detection
make detect-drift-nonprod

# Check output
ls -lt drift-reports/
```

**Production:**
```bash
cd Infrastructure/lightwave-infrastructure-live
export AWS_PROFILE=lightwave-admin-new

# Run drift detection
make detect-drift-prod

# Check output
ls -lt drift-reports/
```

**Custom Detection:**
```bash
# Specify output format
./scripts/detect-drift.sh non-prod us-east-1 json
./scripts/detect-drift.sh prod us-east-1 markdown
./scripts/detect-drift.sh non-prod us-east-1 text
```

### GitHub Actions Drift Detection

**Manual Trigger:**
1. Go to GitHub Actions
2. Select "Infrastructure Drift Detection" workflow
3. Click "Run workflow"
4. Select environment (all, non-prod, or prod)
5. Select output format
6. Click "Run workflow"

**Scheduled Runs:**
- Runs automatically daily at 6am UTC
- Check workflow runs in GitHub Actions
- Review artifacts for drift reports
- Check Issues tab for critical drift alerts

### Exit Codes

The drift detection script uses these exit codes:

- `0` - No drift detected
- `1` - Error running detection
- `2` - Drift detected (acceptable or high severity)
- `3` - Critical drift detected (requires immediate action)

---

## Analyzing Drift Reports

### Report Formats

#### JSON Report
```json
{
  "timestamp": "2025-10-29T06:00:00Z",
  "environment": "prod",
  "region": "us-east-1",
  "drift_detected": true,
  "drift_severity": "high",
  "summary": {
    "resources_to_add": 0,
    "resources_to_change": 3,
    "resources_to_destroy": 1,
    "resources_to_replace": 0,
    "total_changes": 4
  }
}
```

#### Markdown Report
- Human-readable format
- Severity classification
- Recommended actions
- Links to detailed plan output

#### Text Report
- Console-friendly format
- Good for CI/CD pipelines
- Easy to parse with scripts

### Reading Drift Severity

| Severity | Description | Action Required |
|----------|-------------|----------------|
| **NONE** | No drift detected | None - infrastructure in sync |
| **ACCEPTABLE** | Minor configuration changes | Review and decide if action needed |
| **HIGH** | Resources will be destroyed/replaced | Review carefully before remediation |
| **CRITICAL** | Security-related resources affected | IMMEDIATE action required |

### Interpreting Plan Output

**Resources to Add (+ symbol):**
- New resources not in Terraform state
- Usually indicates manual resource creation
- May need to import or document

**Resources to Change (~ symbol):**
- Existing resources with modified attributes
- Most common type of drift
- Review specific attribute changes

**Resources to Destroy (- symbol):**
- Resources in state but not in AWS
- May indicate manual deletion
- Could cause Terraform errors

**Resources to Replace (-/+ symbol):**
- Resources that must be destroyed and recreated
- High impact - may cause downtime
- Requires careful planning

---

## Drift Resolution Procedures

### Step 1: Investigate Source of Drift

**Check AWS CloudTrail:**
```bash
# Find recent changes to a specific resource
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=<resource-name> \
  --max-items 20 \
  --profile lightwave-admin-new

# Find IAM changes
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceType,AttributeValue=AWS::IAM::Role \
  --max-items 20 \
  --profile lightwave-admin-new
```

**Check Recent Incidents:**
- Review Slack #infrastructure channel
- Check recent support tickets
- Ask team if manual changes were made

**Check AWS Service Events:**
- Review AWS Personal Health Dashboard
- Check service-specific consoles (ECS, RDS, etc.)
- Look for auto-scaling events

### Step 2: Classify Drift

Use the remediation suggestion script:
```bash
# Find latest drift report
LATEST_REPORT=$(ls -t drift-reports/*.json | head -1)

# Get remediation suggestions
make suggest-remediation DRIFT_REPORT="${LATEST_REPORT}"
```

Classify each drifted resource:
1. **Acceptable** - Expected behavior (auto-scaling, etc.)
2. **Intentional** - Manual emergency fix (needs code update)
3. **Unintended** - Accidental change (revert via Terraform)
4. **Critical** - Security issue (immediate action)

### Step 3: Choose Remediation Strategy

#### Strategy A: Update Terraform Code

**When to use:**
- Manual changes were correct and intentional
- Emergency fix that should be permanent
- AWS service made beneficial changes

**Procedure:**
```bash
cd Infrastructure/lightwave-infrastructure-live/<env>/<region>

# 1. Review current AWS configuration
aws <service> describe-<resource> --<identifier> <name>

# 2. Update Terraform code to match current state
# Edit relevant .hcl files

# 3. Validate changes
terragrunt run-all validate

# 4. Plan to verify no destructive changes
terragrunt run-all plan --terragrunt-non-interactive

# 5. Apply changes
terragrunt run-all apply --terragrunt-non-interactive

# 6. Verify drift resolved
./scripts/detect-drift.sh <env> us-east-1 markdown
```

**Document:**
- Why manual change was necessary
- Why it should be permanent
- Prevention measures for future

#### Strategy B: Revert Manual Changes

**When to use:**
- Manual changes were accidental
- Changes violate security policies
- Terraform configuration is correct

**Procedure:**
```bash
cd Infrastructure/lightwave-infrastructure-live/<env>/<region>

# 1. Review what will be reverted
terragrunt run-all plan --terragrunt-non-interactive

# 2. If resources will be destroyed/replaced, create backups
# For RDS:
aws rds create-db-snapshot \
  --db-instance-identifier <name> \
  --db-snapshot-identifier pre-revert-$(date +%Y%m%d) \
  --profile lightwave-admin-new

# 3. Apply Terraform to revert changes
terragrunt run-all apply --terragrunt-non-interactive

# 4. Verify resources restored
aws <service> describe-<resource> --<identifier> <name>

# 5. Test application functionality
make test-<env>

# 6. Verify drift resolved
./scripts/detect-drift.sh <env> us-east-1 markdown
```

**Notify:**
- Team about reverted changes
- Document incident and cause
- Implement prevention measures

#### Strategy C: Ignore Drift

**When to use:**
- Drift is expected (auto-scaling)
- AWS service manages attribute
- Changes are ephemeral

**Procedure:**
```bash
# 1. Add lifecycle rule to Terraform resource
# Edit relevant terragrunt.hcl or module

resource "aws_ecs_service" "main" {
  # ... other configuration ...

  lifecycle {
    ignore_changes = [
      desired_count,  # Managed by auto-scaling
      task_definition  # May be updated outside Terraform
    ]
  }
}

# 2. Apply configuration
terragrunt apply

# 3. Verify drift is now ignored
terragrunt plan  # Should show no changes
```

**Document:**
- Which attributes are ignored
- Why drift is acceptable
- How to update if needed in future

### Step 4: Verify Resolution

**After remediation:**
```bash
# Run drift detection again
./scripts/detect-drift.sh <env> us-east-1 markdown

# Expected result: No drift detected or only acceptable drift

# Verify application functionality
make test-<env>

# Check resource health
make health-check-<env>
```

---

## Common Drift Scenarios

### Scenario 1: ECS Service Desired Count Changed

**Cause:** Auto-scaling or manual scaling during incident

**Severity:** Acceptable

**Remediation:**
```hcl
resource "aws_ecs_service" "main" {
  lifecycle {
    ignore_changes = [desired_count]
  }
}
```

**Rationale:** ECS auto-scaling should control task count.

---

### Scenario 2: Security Group Rule Added Manually

**Cause:** Emergency access needed during incident

**Severity:** Critical

**Remediation:**
1. Review rule in AWS console
2. Determine if rule should be permanent
3. If temporary: Remove via console or Terraform apply
4. If permanent: Add to Terraform code, then apply
5. Document incident and update runbooks

**Prevention:**
- Document emergency access procedures
- Use AWS SSM Session Manager instead of SSH
- Pre-define emergency security groups

---

### Scenario 3: RDS Instance Stopped

**Cause:** Manual cost-saving measure

**Severity:** High

**Remediation:**
1. Determine if stopping was intentional
2. If intentional: Remove from Terraform management or add lifecycle rule
3. If accidental: Run `terragrunt apply` to restart
4. Update cost-saving procedures

**Prevention:**
- Use scheduled stop/start automation
- Set up proper dev/staging environments
- Use Aurora Serverless for non-production

---

### Scenario 4: IAM Policy Modified

**Cause:** Developer added permissions manually

**Severity:** Critical

**Remediation:**
1. **IMMEDIATE:** Review policy changes in CloudTrail
2. Determine if permissions are excessive
3. Check for privilege escalation risk
4. If unsafe: Revert immediately via Terraform apply
5. If safe but needed: Update Terraform, get security review, apply
6. Notify security team

**Prevention:**
- Restrict IAM console access
- Require PR review for IAM changes
- Use AWS IAM Access Analyzer
- Set up CloudTrail alerts for IAM changes

---

### Scenario 5: Tags Modified

**Cause:** Cost allocation tags added by AWS or third-party tools

**Severity:** Acceptable

**Remediation:**
```hcl
resource "aws_instance" "main" {
  lifecycle {
    ignore_changes = [tags["CostCenter"], tags["Environment"]]
  }
}

# Or ignore all tags
lifecycle {
  ignore_changes = [tags]
}
```

**Rationale:** Tags often managed by external systems.

---

### Scenario 6: RDS Parameter Group Modified

**Cause:** DBA tuned database performance

**Severity:** High

**Remediation:**
1. Export current parameter group:
```bash
aws rds describe-db-parameters \
  --db-parameter-group-name <name> \
  --profile lightwave-admin-new > current-params.json
```

2. Update Terraform with new parameters
3. Test in non-production first
4. Apply to production during maintenance window
5. Document parameter changes and rationale

**Prevention:**
- Require Terraform for all parameter changes
- Test parameter changes in non-prod first
- Document performance tuning decisions

---

### Scenario 7: Load Balancer Target Group Unhealthy

**Cause:** Manual deregistration during maintenance

**Severity:** High

**Remediation:**
1. Verify maintenance is complete
2. Re-register targets manually or via Terraform apply
3. Check target health
4. Monitor application logs

**Prevention:**
- Document maintenance procedures
- Use scheduled maintenance windows
- Automate target registration/deregistration

---

## Prevention Strategies

### 1. Restrict Console Access

**Implementation:**
- Use IAM policies to restrict write access
- Require MFA for destructive operations
- Audit console usage with CloudTrail

**Example IAM Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyManualChangesToManagedResources",
      "Effect": "Deny",
      "Action": [
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:ModifySecurityGroup*",
        "iam:PutRolePolicy",
        "rds:ModifyDBInstance"
      ],
      "Resource": "*",
      "Condition": {
        "StringNotEquals": {
          "aws:PrincipalTag/AllowManualChanges": "true"
        }
      }
    }
  ]
}
```

### 2. Use AWS Config Rules

**Implementation:**
- Enable AWS Config
- Create rules to detect unauthorized changes
- Set up SNS notifications for violations

**Example Config Rules:**
- `required-tags` - Ensure resources have required tags
- `restricted-ssh` - Detect SSH open to 0.0.0.0/0
- `iam-policy-no-statements-with-admin-access` - Detect overly permissive policies

### 3. CloudTrail Alerts

**Implementation:**
- Create CloudWatch alarms for critical API calls
- Send to SNS topic
- Integrate with Slack/PagerDuty

**Example CloudWatch Filter:**
```json
{
  "$.eventName": "AuthorizeSecurityGroupIngress",
  "$.sourceIPAddress": "console.aws.amazon.com"
}
```

### 4. Scheduled Drift Detection

**Implementation:**
- GitHub Actions workflow (already configured)
- Runs daily at 6am UTC
- Creates issues for critical drift
- Sends Slack notifications

**Monitoring:**
- Check GitHub Actions runs weekly
- Review drift reports monthly
- Track drift trends over time

### 5. Lifecycle Ignore Rules

**Implementation:**
- Add to resources with expected drift
- Document why drift is acceptable
- Review periodically

**Example:**
```hcl
resource "aws_ecs_service" "main" {
  # Accept auto-scaling changes
  lifecycle {
    ignore_changes = [desired_count]
  }
}

resource "aws_instance" "main" {
  # Accept cost allocation tags
  lifecycle {
    ignore_changes = [tags]
  }
}
```

### 6. Documentation and Training

**Implementation:**
- Document proper change procedures
- Train team on Terraform workflows
- Create runbooks for common scenarios
- Regular team reviews of drift reports

### 7. Emergency Access Procedures

**Implementation:**
- Document when manual changes are acceptable
- Require post-incident Terraform updates
- Create emergency access security groups
- Use break-glass IAM roles

**Example Procedure:**
```markdown
## Emergency Access Procedure

1. Make manual change in AWS console
2. Document change in #infrastructure Slack
3. Create incident ticket
4. Within 24 hours: Update Terraform code
5. Within 48 hours: Apply Terraform changes
6. Document in post-incident review
```

---

## Alerting and Notifications

### GitHub Issues

**Automatic Creation:**
- Critical drift triggers issue creation
- Issue includes drift report
- Tagged with severity and environment
- Assigned to platform team

**Issue Management:**
- Triage within 4 hours (production)
- Triage within 24 hours (non-production)
- Close only after drift resolved
- Document resolution in issue

### Slack Notifications

**Configuration:**
1. Create Slack webhook URL
2. Add to GitHub secrets: `SLACK_WEBHOOK_URL`
3. Or set environment variable locally

**Notification Format:**
- Environment affected
- Drift severity
- Number of changes
- Link to workflow run

**Example:**
```
⚠️ Infrastructure Drift Detected

Environment: PRODUCTION
Severity: HIGH
Changes: 5
Workflow: [View Details](https://github.com/...)
```

### Email Notifications

**Configuration:**
- GitHub Actions sends email to watchers
- Configure in GitHub notification settings
- Create distribution list for platform team

### Drift Detection Dashboard

**Future Enhancement:**
- Track drift over time
- Visualize trends
- Identify frequent drift sources
- Report on resolution time

**Recommended Tools:**
- Grafana with GitHub Actions exporter
- AWS QuickSight
- Custom dashboard with drift report JSON

---

## Troubleshooting

### Issue: Drift Detection Script Fails

**Symptoms:**
- Exit code 1
- Error in plan output
- No drift report generated

**Causes:**
- AWS credentials not configured
- Terraform/Terragrunt not installed
- State backend unavailable
- Resource access denied

**Resolution:**
```bash
# Check AWS credentials
aws sts get-caller-identity --profile lightwave-admin-new

# Check Terragrunt installation
terragrunt --version

# Check state backend
aws s3 ls s3://lightwave-terraform-state/ --profile lightwave-admin-new

# Check detailed error
./scripts/detect-drift.sh non-prod us-east-1 text 2>&1 | tee debug.log
```

---

### Issue: False Positive Drift Detection

**Symptoms:**
- Drift detected but no actual changes
- Resources shown as changed but identical

**Causes:**
- Terraform provider version mismatch
- State file out of sync
- Resource defaults changed

**Resolution:**
```bash
# Refresh state
cd <env>/<region>
terragrunt run-all refresh

# Update providers
terragrunt init -upgrade

# Re-run detection
./scripts/detect-drift.sh <env> us-east-1 markdown
```

---

### Issue: Critical Drift Not Creating Issues

**Symptoms:**
- Critical drift detected
- No GitHub issue created
- No Slack notification

**Causes:**
- Workflow permissions insufficient
- Slack webhook not configured
- Drift severity not classified as critical

**Resolution:**
```bash
# Check workflow permissions in .github/workflows/drift-detection.yml
# Ensure: permissions.issues: write

# Check Slack webhook
echo $SLACK_WEBHOOK_URL  # Should not be empty

# Review drift classification logic in detect-drift.sh
grep -A 10 "drift_severity" scripts/detect-drift.sh
```

---

### Issue: Too Many Acceptable Drift Alerts

**Symptoms:**
- Drift detected daily
- Always the same resources
- Changes are expected (auto-scaling, etc.)

**Causes:**
- Missing lifecycle ignore rules
- Resources managed by AWS services

**Resolution:**
1. Identify frequently drifting resources
2. Classify drift as acceptable
3. Add lifecycle ignore rules
4. Update drift detection to skip these resources
5. Document acceptable drift in code comments

---

## Related Documents

- **Deployment Procedures:** `SOP_INFRASTRUCTURE_DEPLOYMENT.md`
- **Remote State Management:** `SOP_REMOTE_STATE_MANAGEMENT.md`
- **Disaster Recovery:** `SOP_DISASTER_RECOVERY.md`
- **Secrets Management:** `SOP_SECRETS_MANAGEMENT.md`

---

## Appendix A: Drift Detection Workflow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    Scheduled Trigger                         │
│                   (Daily at 6am UTC)                         │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              Run Terragrunt Plan (All Resources)            │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
                   ┌───────────┐
                   │  Drift?   │
                   └─────┬─────┘
                         │
           ┌─────────────┴─────────────┐
           │                           │
           ▼ No                     Yes▼
    ┌────────────┐          ┌──────────────────┐
    │  Success   │          │  Parse Changes   │
    │  (Exit 0)  │          │  Classify Drift  │
    └────────────┘          └────────┬─────────┘
                                     │
                    ┌────────────────┼────────────────┐
                    │                │                │
                    ▼                ▼                ▼
             ┌─────────────┐ ┌──────────┐  ┌─────────────┐
             │ Acceptable  │ │   High   │  │  Critical   │
             │  (Exit 2)   │ │ (Exit 2) │  │  (Exit 3)   │
             └──────┬──────┘ └─────┬────┘  └──────┬──────┘
                    │              │               │
                    └──────────────┼───────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────┐
                    │   Generate Drift Report  │
                    │   (JSON, Markdown, Text) │
                    └────────────┬─────────────┘
                                 │
                    ┌────────────┼────────────┐
                    │            │            │
                    ▼            ▼            ▼
            ┌────────────┐ ┌─────────┐ ┌──────────┐
            │  Upload    │ │ Create  │ │  Send    │
            │  Artifact  │ │  Issue  │ │  Slack   │
            │  (GitHub)  │ │ (Crit)  │ │  Alert   │
            └────────────┘ └─────────┘ └──────────┘
```

---

## Appendix B: Drift Severity Decision Tree

```
Drift Detected
│
├─ Security Resources Modified? ────────────────► CRITICAL
│  (IAM, Security Groups, KMS, Network ACLs)
│
├─ Resources to be Destroyed/Replaced? ─────────► HIGH
│  (RDS, Data Stores, Load Balancers)
│
├─ Configuration Changes Only? ─────────────────► ACCEPTABLE
│  (Tags, Counts, Non-critical Settings)
│
└─ Auto-Scaling/AWS-Managed Changes? ───────────► ACCEPTABLE
   (ECS Desired Count, ASG Capacity)
```

---

## Revision History

- **2025-10-29:** Initial version (1.0.0) - Comprehensive drift detection procedures
- **Future:** Add drift trend analysis and dashboard implementation

---

**For Questions or Issues:**
- Slack: #infrastructure
- GitHub: Create issue in `lightwave-infrastructure-live`
- Email: platform-team@lightwave-media.com
