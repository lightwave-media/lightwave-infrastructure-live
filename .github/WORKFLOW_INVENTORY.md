# Workflow Inventory & Test Results

## Repository: lightwave-infrastructure-live

### Workflow 1: terragrunt-plan.yml
**Status**: 🔄 Testing in progress

**Purpose**:
- Run on PRs to show infrastructure changes before merge
- Post plan output as PR comment
- Detect which environments changed (non-prod vs prod)

**Triggers**:
- Pull requests to `main` branch
- Changes to `non-prod/**`, `prod/**`, `root.hcl`, `*.hcl`, or the workflow file itself

**Dependencies**:
- ✅ Script: `scripts/verify-remote-state.sh` (exists, OIDC-compatible)
- ⏳ Secret: `AWS_GITHUB_ACTIONS_ROLE_ARN` (checking...)
- ✅ Tools: OpenTofu 1.9.0, Terragrunt 0.82.3
- ✅ State resources: S3 bucket, DynamoDB table

**Expected Outcomes**:
1. Detects changed environments (non-prod/prod)
2. Verifies remote state is accessible
3. Runs `terragrunt run-all plan` for changed environments
4. Posts plan output as PR comment
5. Warns if production has destructive changes

**Test Results - Phase 1 (Dependencies)**:
- ✅ Script exists: `scripts/verify-remote-state.sh`
- ✅ Script is OIDC-compatible (uses array for conditional AWS CLI args)
- ✅ S3 state bucket accessible: `lightwave-terraform-state-non-prod-us-east-1`
- ✅ DynamoDB lock table: `lightwave-terraform-locks` (ACTIVE)
- ❌ **BLOCKER**: IAM role `GitHubActionsInfrastructureRole` does NOT exist
- ❌ **BLOCKER**: Secret `AWS_GITHUB_ACTIONS_ROLE_ARN` likely not configured

**Action Required**:
1. Run `scripts/setup-github-oidc.sh` to create IAM role and OIDC provider
2. Add `AWS_GITHUB_ACTIONS_ROLE_ARN` secret to GitHub repository settings

**Cannot proceed with workflow testing until authentication is configured.**

---

### Workflow 2: terragrunt-apply.yml
**Status**: ⏳ Pending

**Purpose**:
- Apply approved infrastructure changes
- Runs after PR merge or manual trigger

**Triggers**:
- TBD (need to read workflow file)

**Dependencies**:
- TBD

**Expected Outcomes**:
- TBD

---

### Workflow 3: deploy-nonprod.yml
**Status**: ⏳ Pending

**Purpose**:
- Deploy infrastructure to non-prod environment

**Triggers**:
- TBD

**Dependencies**:
- TBD

**Expected Outcomes**:
- TBD

---

### Workflow 4: deploy-prod.yml
**Status**: ⏳ Pending

**Purpose**:
- Deploy infrastructure to production environment

**Triggers**:
- TBD

**Dependencies**:
- TBD

**Expected Outcomes**:
- TBD

---

### Workflow 5: drift-detection.yml
**Status**: ⏳ Pending

**Purpose**:
- Detect configuration drift between Terraform state and live AWS resources

**Triggers**:
- TBD

**Dependencies**:
- TBD

**Expected Outcomes**:
- TBD

---

## Test Log

### 2025-11-05

#### terragrunt-plan.yml - Dependency Check

```bash
# Checking secrets...
```
