# Infrastructure Drift Detection - Quick Start Guide

This guide provides a quick reference for using the LightWave infrastructure drift detection system.

---

## What is Drift Detection?

Drift detection identifies when your live AWS infrastructure differs from what's defined in Terraform code. This happens when:
- Someone makes manual changes in the AWS console
- Auto-scaling adjusts resource counts
- AWS services update configurations
- Third-party tools modify resources

---

## Quick Commands

### Detect Drift Locally

```bash
# Set AWS profile
export AWS_PROFILE=lightwave-admin-new

# Detect drift in non-production
make detect-drift-nonprod

# Detect drift in production
make detect-drift-prod

# Detect drift in all environments
make detect-drift-all
```

### View Drift Reports

```bash
# List recent drift reports
ls -lt drift-reports/

# View latest report
cat drift-reports/$(ls -t drift-reports/*.markdown | head -1)

# Get remediation suggestions
make suggest-remediation DRIFT_REPORT=drift-reports/non-prod-us-east-1-drift-20251029_123456.json
```

### Manual Drift Detection

```bash
# JSON format (machine-readable)
./scripts/detect-drift.sh non-prod us-east-1 json

# Markdown format (human-readable)
./scripts/detect-drift.sh prod us-east-1 markdown

# Text format (console-friendly)
./scripts/detect-drift.sh non-prod us-east-1 text
```

---

## Automated Drift Detection

### Scheduled Runs

Drift detection runs automatically:
- **Frequency:** Daily at 6am UTC
- **Environments:** Both non-prod and production
- **Notifications:**
  - GitHub Issues (critical drift only)
  - Slack alerts (if configured)
  - Workflow artifacts (all runs)

### Manual Workflow Trigger

1. Go to GitHub Actions in `lightwave-infrastructure-live` repo
2. Select "Infrastructure Drift Detection" workflow
3. Click "Run workflow"
4. Choose:
   - Environment: `all`, `non-prod`, or `prod`
   - Output format: `markdown`, `json`, or `text`
5. Click "Run workflow" button

### Viewing Results

**GitHub Actions:**
- Go to Actions tab
- Find "Infrastructure Drift Detection" runs
- Download artifacts to see drift reports

**GitHub Issues:**
- Check Issues tab
- Look for "Critical Infrastructure Drift Detected" issues
- Filter by label: `drift-detection`, `critical`

---

## Understanding Drift Reports

### Drift Severity Levels

| Severity | Meaning | Action |
|----------|---------|--------|
| **NONE** | No drift detected | ✅ No action needed |
| **ACCEPTABLE** | Minor changes (auto-scaling, tags) | Review, may not need action |
| **HIGH** | Resources will be destroyed/replaced | ⚠️ Review carefully |
| **CRITICAL** | Security resources affected | 🚨 Immediate action required |

### Resource Change Types

| Symbol | Type | Description |
|--------|------|-------------|
| `+` | Add | New resource not in Terraform |
| `~` | Change | Existing resource modified |
| `-` | Destroy | Resource will be deleted |
| `-/+` | Replace | Resource destroyed and recreated |

---

## Common Drift Scenarios

### Scenario 1: Auto-Scaling Changed Task Count

**Drift Report Shows:**
```
~ aws_ecs_service.backend
  desired_count: 2 → 5
```

**What Happened:**
- Auto-scaling increased task count due to high CPU
- This is expected behavior

**Action:**
```bash
# Option 1: Ignore this drift (recommended)
# Add to Terraform:
lifecycle {
  ignore_changes = [desired_count]
}

# Option 2: Update Terraform baseline
# Edit terragrunt.hcl:
desired_count = 5
# Then: terragrunt apply
```

---

### Scenario 2: Security Group Rule Added

**Drift Report Shows:**
```
~ aws_security_group.backend
  + ingress {
      from_port = 22
      to_port   = 22
      cidr_blocks = ["0.0.0.0/0"]
    }
```

**What Happened:**
- Someone added SSH access in AWS console
- 🚨 Security risk!

**Action:**
```bash
# 1. Investigate who made the change
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=sg-xxxxx

# 2. Remove unsafe rule
cd non-prod/us-east-1
terragrunt apply  # Will remove the rule

# 3. Document incident
# 4. Review access procedures
```

---

### Scenario 3: RDS Parameter Changed

**Drift Report Shows:**
```
~ aws_db_parameter_group.postgres
  parameter {
    name  = "max_connections"
    value = "100" → "200"
  }
```

**What Happened:**
- DBA tuned database for performance
- Change may be beneficial

**Action:**
```bash
# 1. Review change with DBA
# 2. Test in non-prod first
# 3. Update Terraform code:
# Edit terragrunt.hcl
parameter {
  name  = "max_connections"
  value = "200"
}

# 4. Apply change
terragrunt apply

# 5. Monitor database performance
```

---

## Remediation Workflow

### Step 1: Detect Drift

```bash
make detect-drift-nonprod
# or
make detect-drift-prod
```

### Step 2: Analyze Report

```bash
# Find latest report
LATEST=$(ls -t drift-reports/*.json | head -1)

# Get remediation suggestions
make suggest-remediation DRIFT_REPORT="${LATEST}"
```

### Step 3: Investigate Source

```bash
# Check CloudTrail for manual changes
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=<resource-name> \
  --max-items 20

# Check team Slack for incidents
# Review recent deployments
```

### Step 4: Choose Remediation Strategy

**Option A: Update Terraform** (manual change was correct)
```bash
# 1. Update Terraform code to match AWS
# 2. Run: terragrunt plan
# 3. Run: terragrunt apply
```

**Option B: Revert Changes** (Terraform is correct)
```bash
# 1. Review what will be reverted
terragrunt plan

# 2. Apply to revert
terragrunt apply

# 3. Notify team
```

**Option C: Ignore Drift** (expected behavior)
```bash
# 1. Add lifecycle ignore rule
lifecycle {
  ignore_changes = [attribute_name]
}

# 2. Apply configuration
terragrunt apply
```

### Step 5: Verify Resolution

```bash
# Run drift detection again
make detect-drift-nonprod

# Should show: "No drift detected"
```

---

## Alert Thresholds

### When to Act Immediately (Critical)

- ✅ Security groups modified
- ✅ IAM roles/policies changed
- ✅ Database security settings altered
- ✅ KMS keys modified
- ✅ Network ACLs changed

**Response Time:** Within 4 hours for production, 24 hours for non-prod

### When to Review and Plan (High)

- ⚠️ Resources will be destroyed
- ⚠️ Resources will be replaced
- ⚠️ RDS instances modified
- ⚠️ Load balancers changed

**Response Time:** Within 1 business day

### When to Monitor (Acceptable)

- ℹ️ Auto-scaling adjustments
- ℹ️ Tag modifications
- ℹ️ Service-managed changes
- ℹ️ Task/instance counts

**Response Time:** Review during next sprint planning

---

## Configuration

### Slack Notifications

To enable Slack notifications:

1. Create Slack webhook URL
2. Add to GitHub repository secrets:
   - Name: `SLACK_WEBHOOK_URL`
   - Value: `https://hooks.slack.com/services/...`
3. Or set locally:
   ```bash
   export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."
   ```

### GitHub Issues

Automatic issue creation is enabled for critical drift:
- Issues created with labels: `infrastructure`, `drift-detection`, `critical`
- Assigned to platform team
- Includes full drift report

### Report Retention

- **GitHub Actions Artifacts:** 90 days
- **Local Drift Reports:** Kept indefinitely in `drift-reports/`
- **GitHub Issues:** Kept until manually closed

---

## Troubleshooting

### Error: "AWS credentials not configured"

**Solution:**
```bash
export AWS_PROFILE=lightwave-admin-new
aws sts get-caller-identity  # Verify credentials
```

### Error: "terragrunt is not installed"

**Solution:**
```bash
mise install  # Install via mise
# or
brew install terragrunt  # Install via Homebrew
```

### Error: "Environment directory not found"

**Solution:**
```bash
# Check current directory
pwd
# Should be: .../lightwave-infrastructure-live

# Check environment exists
ls -la non-prod/us-east-1/
ls -la prod/us-east-1/
```

### No Drift Detected But Console Shows Changes

**Possible Causes:**
1. Changes not saved to remote state
2. Terraform refresh needed
3. Resource not managed by Terraform

**Solution:**
```bash
cd <env>/<region>
terragrunt run-all refresh
terragrunt run-all plan
```

---

## Best Practices

1. **Run Before Deployments**
   - Always run drift detection before `terragrunt apply`
   - Investigate unexpected changes
   - Document acceptable drift

2. **Review Drift Reports Weekly**
   - Check GitHub Actions runs
   - Review drift trends
   - Update ignore rules as needed

3. **Document Manual Changes**
   - Post in #infrastructure Slack
   - Create incident ticket
   - Update Terraform within 24 hours

4. **Use Lifecycle Ignore Rules**
   - Add for auto-scaling resources
   - Add for AWS-managed attributes
   - Document why drift is acceptable

5. **Test Remediation in Non-Prod**
   - Never apply untested fixes to production
   - Verify drift resolution before prod
   - Document remediation steps

---

## Resources

- **Full Documentation:** `docs/SOP_DRIFT_DETECTION.md`
- **Deployment Procedures:** `docs/SOP_INFRASTRUCTURE_DEPLOYMENT.md`
- **Makefile Targets:** Run `make help` for all commands
- **GitHub Workflow:** `.github/workflows/drift-detection.yml`
- **Detection Script:** `scripts/detect-drift.sh`
- **Remediation Script:** `scripts/suggest-drift-remediation.sh`

---

## Getting Help

- **Slack:** #infrastructure channel
- **GitHub:** Create issue in `lightwave-infrastructure-live`
- **Emergency:** Page platform team lead

---

**Last Updated:** 2025-10-29
**Version:** 1.0.0
