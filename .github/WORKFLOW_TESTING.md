# GitHub Actions Workflow Testing Methodology

## Problem Statement

Workflows often fail in production despite passing syntax validation because we don't verify:
1. **Dependencies exist** (scripts, secrets, tools)
2. **Logic is correct** (the workflow does what we expect)
3. **Integration works** (scripts work with the auth method used)
4. **Expected outcomes** (not just "doesn't error")

## Comprehensive Testing Checklist

### Phase 1: Dependency Verification

- [ ] **Secrets exist and are correctly named**
  ```bash
  gh api repos/OWNER/REPO/actions/secrets --jq '.secrets[] | .name'
  ```

- [ ] **Scripts referenced exist**
  ```bash
  # For each script referenced in workflow
  ls -la scripts/script-name.sh
  ```

- [ ] **Tools/binaries are available**
  - OpenTofu/Terragrunt versions match
  - AWS CLI compatible with OIDC
  - jq, grep, awk available in runner

### Phase 2: Authentication Compatibility

- [ ] **Scripts work with OIDC (no --profile flag)**
  ```bash
  grep -r "aws.*--profile" scripts/
  ```
  **Fix**: Make scripts check for AWS_PROFILE and only use --profile if set

- [ ] **IAM role has correct permissions**
  - Check role trust policy includes GitHub OIDC provider
  - Check role has required AWS permissions

### Phase 3: Logic Verification

- [ ] **Workflow triggers are correct**
  - `on:` conditions match intended use case
  - Path filters work (test with git diff simulation)

- [ ] **Job dependencies** make sense
  - `needs:` references exist
  - No circular dependencies

- [ ] **Conditional logic** is valid
  - Can't reference `matrix` in job-level `if`
  - `needs.job.outputs.var` actually exists

- [ ] **Environment variables** are set where needed
  - Scripts that need `TG_BUCKET_PREFIX` receive it
  - Region set correctly

### Phase 4: Expected Outcome Testing

**For each workflow, document:**

#### terragrunt-plan.yml
- **Trigger**: On PR to main with non-prod/* or prod/* changes
- **Expected outcome**:
  1. Detects which environments changed
  2. Verifies S3/DynamoDB state exists
  3. Runs `terragrunt plan` for changed envs
  4. Posts plan output as PR comment
  5. Warns if prod has destructive changes
- **Success criteria**:
  - PR gets comment with plan output
  - No authentication errors
  - Plan completes (exit 0 or shows changes)

#### terragrunt-apply.yml
- **Trigger**: Manual workflow_dispatch or PR merge
- **Expected outcome**:
  1. Requires approval for prod
  2. Runs `terragrunt apply`
  3. Updates infrastructure
- **Success criteria**:
  - Infrastructure changes applied
  - State file updated in S3
  - No lock errors

#### drift-detection.yml
- **Trigger**: Daily cron at 6am UTC
- **Expected outcome**:
  1. Runs `terragrunt plan` to detect drift
  2. Creates GitHub issue if critical drift
  3. Uploads drift reports as artifacts
- **Success criteria**:
  - Runs without auth errors
  - Detects actual drift if present
  - Creates issue for critical drift

### Phase 5: Dry-Run Testing

**Before merging workflow changes:**

```bash
# 1. Trigger workflow manually with dry-run inputs
gh workflow run terragrunt-plan.yml -f dry_run=true

# 2. Monitor workflow
gh run watch

# 3. Review logs
gh run view --log

# 4. Check expected outcome occurred
gh pr view <PR_NUMBER> --comments  # Check for plan comment
```

## Common Issues Found

### Issue: Scripts use --profile but workflow uses OIDC

**Scripts affected:**
- `verify-remote-state.sh`
- `detect-drift.sh`
- `load-dev-secrets.sh`
- `setup-github-oidc.sh`

**Fix**: Make scripts detect if running in GitHub Actions:

```bash
# Check if running in GitHub Actions (OIDC)
if [ -n "${GITHUB_ACTIONS:-}" ]; then
    # No profile flag needed - credentials from OIDC
    AWS_CLI_PROFILE_FLAG=""
else
    # Local execution - use profile
    AWS_CLI_PROFILE_FLAG="--profile ${AWS_PROFILE}"
fi

# Use in commands
aws sts get-caller-identity $AWS_CLI_PROFILE_FLAG
```

### Issue: GitHub environment doesn't exist

**Error**: `Value 'non-prod' is not valid`

**Fix**: Either create the environment in GitHub settings or remove the `environment:` block

### Issue: Matrix in job-level if condition

**Error**: `Unrecognized named-value: 'matrix'`

**Fix**: Split into separate jobs or move condition to step level

## Testing New Workflows

**Process:**
1. Create workflow in a feature branch
2. Complete all 5 phases of checklist above
3. Trigger manually with `workflow_dispatch` first
4. Verify expected outcome (not just "no errors")
5. Document what success looks like
6. Only then merge to main

## Verification Commands

```bash
# Check workflow syntax
gh workflow view workflow-name.yml

# List recent runs
gh run list --workflow=workflow-name.yml --limit 5

# View specific run logs
gh run view RUN_ID --log

# Check secrets configured
gh secret list

# Verify IAM role (local)
aws iam get-role --role-name GitHubActionsRole --profile lightwave-admin-new

# Test script locally with same inputs workflow would use
GITHUB_ACTIONS=true ./scripts/verify-remote-state.sh non-prod us-east-1
```

## Success Criteria Template

For each workflow, fill this out:

```markdown
## Workflow: [name]

**Purpose**: [what problem does it solve]

**Triggers**:
- [when should it run]

**Inputs**:
- [what inputs/secrets does it need]

**Expected Outcome**:
- [step 1 expected result]
- [step 2 expected result]
- [final expected result]

**How to verify it worked**:
- [what to check - PR comment? artifact? AWS resource?]

**Known limitations**:
- [what doesn't it do]
```
