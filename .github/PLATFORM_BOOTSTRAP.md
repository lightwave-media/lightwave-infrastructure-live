# Platform Bootstrap - Infrastructure Workspace

## Context: What We're Building

This is a **production-grade, multi-environment infrastructure platform** for LightWave Media, using:
- **Infrastructure as Code**: OpenTofu + Terragrunt
- **Multi-repo workspace**: Separate repos for catalog (modules) and live (environments)
- **CI/CD**: GitHub Actions with AWS OIDC
- **Environments**: non-prod (dev/staging combined) + prod

## Current State (2025-11-05)

### ✅ What's Working
1. **AWS OIDC Authentication**:
   - Role: `GitHubActionsInfrastructureRole`
   - Provider: token.actions.githubusercontent.com
   - Secret: `AWS_GITHUB_ACTIONS_ROLE_ARN` configured
   - Trust policy: Correctly scoped to this repo

2. **State Management**:
   - S3 bucket: `lightwave-terraform-state-non-prod-us-east-1` (accessible)
   - DynamoDB: `lightwave-terraform-locks` (ACTIVE)
   - Remote state configured and verified

3. **Workflows**:
   - Scripts OIDC-compatible (array-based AWS CLI args)
   - Workflow syntax valid
   - Triggers correctly configured

### ❌ What's Blocking
1. **Git Authentication for Terragrunt**:
   - Terragrunt sources reference: `git::git@github.com:lightwave-media/lightwave-infrastructure-catalog.git`
   - GitHub Actions runner has no SSH key
   - ERROR: `Permission denied (publickey)`

## Platform Engineering Decision: Git Authentication Strategy

### The Wrong Way (Quick Fix)
- Add SSH deploy key to GitHub Actions
- **Why wrong**: Hard to rotate, single point of failure, SSH not standard for CI/CD

### The Right Way (Platform Approach)

**Use HTTPS + GitHub Token** because:

1. **Industry Standard**:
   - Most CI/CD systems use HTTPS + token
   - Easier to audit (tokens have names, SSH keys don't)
   - Works everywhere (corporate firewalls, cloud runners)

2. **Security Best Practices**:
   - **Use GitHub App** (preferred) or fine-grained PAT
   - Scoped to specific repos only
   - Can be rotated without updating workflows
   - Audit trail of all API usage

3. **Developer Experience**:
   - Same auth method for local dev and CI/CD
   - No SSH key management
   - Token can be stored in password manager

4. **Operational Excellence**:
   - Credentials in GitHub Secrets (encrypted at rest)
   - Can be rotated via API
   - Works with `actions/checkout@v4` automatically

## Implementation Plan (Long-Term Fix)

### Phase 1: GitHub Authentication Setup

**Option A: GitHub App (RECOMMENDED for production)**
- Scoped permissions per repo
- Can be installed org-wide
- Built-in credential refresh
- Better for multiple repos

**Option B: Fine-Grained PAT (Simpler, good enough)**
- Scoped to specific repos: `lightwave-infrastructure-catalog`, `lightwave-infrastructure-live`
- Permissions: `Contents: Read` (for cloning)
- Expiration: 90 days (set calendar reminder)

**We'll use Option B** for now (simpler), migrate to App later if needed.

### Phase 2: Update Terragrunt Source URLs

**Current pattern** (SSH):
```hcl
source = "git::git@github.com:lightwave-media/lightwave-infrastructure-catalog.git//modules/budget?ref=main"
```

**New pattern** (HTTPS with token placeholder):
```hcl
source = "git::https://github.com/lightwave-media/lightwave-infrastructure-catalog.git//modules/budget?ref=main"
```

**Why this works**:
- Git will use credential helper configured in workflow
- Token injected at runtime via `GIT_CONFIG_*` env vars
- No hardcoded tokens in files

### Phase 3: Configure Git Credential Helper

**Add to ALL workflows** that run Terragrunt:

```yaml
- name: Configure Git for Terragrunt
  run: |
    git config --global url."https://oauth2:${{ secrets.GITHUB_TOKEN }}@github.com/".insteadOf "https://github.com/"
```

**What this does**:
- Intercepts all `https://github.com/` URLs
- Injects GitHub token automatically
- Works for any git clone operation (including Terragrunt)

**Alternative** (more explicit):
```yaml
- name: Configure Git credentials
  run: |
    git config --global credential.helper store
    echo "https://oauth2:${{ secrets.GITHUB_TOKEN }}@github.com" > ~/.git-credentials
```

### Phase 4: Bootstrap Checklist

**For setting up a NEW environment** (dev, staging, prod):

- [ ] **AWS Resources**:
  - [ ] Create S3 bucket: `lightwave-terraform-state-{env}-{region}`
  - [ ] Enable versioning on S3 bucket
  - [ ] Create DynamoDB table: `lightwave-terraform-locks`
  - [ ] Run `scripts/verify-remote-state.sh {env} {region}` to verify

- [ ] **GitHub Secrets** (Repository Settings → Secrets):
  - [ ] `AWS_GITHUB_ACTIONS_ROLE_ARN`: IAM role ARN from OIDC setup
  - [ ] `GITHUB_TOKEN`: Auto-provided by GitHub (no setup needed)

- [ ] **GitHub Environments** (Repository Settings → Environments):
  - [ ] `non-prod`: 30-second wait timer
  - [ ] `production`: Require reviewers, restrict to main branch

- [ ] **IAM Role Setup**:
  - [ ] Run `scripts/setup-github-oidc.sh lightwave-media {repo-name}`
  - [ ] Verify role trust policy includes OIDC provider
  - [ ] Verify role has required permissions (S3, DynamoDB, EC2, RDS, etc.)

- [ ] **Workflow Testing**:
  - [ ] Create test PR with infrastructure change
  - [ ] Verify `terragrunt-plan.yml` runs and posts comment
  - [ ] Verify plan output is readable and actionable
  - [ ] Merge PR and verify auto-apply (non-prod only)

### Phase 5: Documentation

**Create these docs** (in `.github/` directory):

1. **PLATFORM_ONBOARDING.md**: How to get started as new engineer
2. **RUNBOOK_DEPLOYMENT.md**: How to deploy infrastructure changes
3. **RUNBOOK_TROUBLESHOOTING.md**: Common issues and solutions
4. **ARCHITECTURE_DECISIONS.md**: Why we chose OIDC, HTTPS, etc.

## Decision Log

### Why HTTPS over SSH for Git?
- **Date**: 2025-11-05
- **Decision**: Use HTTPS with GitHub token for all git operations
- **Rationale**:
  - Industry standard for CI/CD
  - Better security (tokens can be scoped and rotated)
  - Simpler to manage (no SSH key distribution)
  - Works with GitHub's built-in `GITHUB_TOKEN`
- **Trade-offs**: Requires updating all Terragrunt source URLs
- **Alternatives considered**: SSH deploy keys (rejected: harder to rotate)

### Why Fine-Grained PAT over GitHub App initially?
- **Date**: 2025-11-05
- **Decision**: Start with fine-grained PAT, migrate to App later
- **Rationale**:
  - Simpler to set up (2 minutes vs 15 minutes)
  - Good enough for single-org use case
  - Can migrate to App when we have multiple repos/orgs
- **Trade-offs**: Manual rotation every 90 days vs App's auto-refresh
- **Future**: Migrate to GitHub App when scaling to more repos

### Why Not Use `actions/checkout` for Infrastructure Catalog?
- **Date**: 2025-11-05
- **Decision**: Let Terragrunt clone directly, don't pre-checkout
- **Rationale**:
  - Terragrunt manages its own caching
  - Pre-checkout would require knowing all modules in advance
  - Git credential helper works for Terragrunt's clone operations
- **Trade-offs**: Slightly slower (no checkout action caching)

## Next Steps (Immediate)

1. ✅ Create fine-grained PAT for infrastructure repos
2. ✅ Update all Terragrunt source URLs to HTTPS
3. ✅ Add git credential helper to workflows
4. ✅ Test with PR to verify expected outcome
5. ✅ Document for future platform engineers

## Long-Term Platform Goals

**Month 1**:
- [ ] All workflows tested and documented
- [ ] Runbooks created for common operations
- [ ] Onboarding doc tested with new team member

**Month 3**:
- [ ] Migrate to GitHub App for better security
- [ ] Add workflow observability (logs aggregation)
- [ ] Create infrastructure change checklist

**Month 6**:
- [ ] Automate credential rotation
- [ ] Add cost monitoring to workflows
- [ ] Create disaster recovery runbook

## References

- [GitHub OIDC with AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [Terragrunt Source Options](https://terragrunt.gruntwork.io/docs/reference/config-blocks-and-attributes/#source)
- [Git Credential Helpers](https://git-scm.com/docs/gitcredentials)
- [GitHub Fine-Grained PATs](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-fine-grained-personal-access-token)
