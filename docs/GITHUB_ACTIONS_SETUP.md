# GitHub Actions CI/CD Setup Guide

This document provides step-by-step instructions for configuring AWS OIDC authentication and IAM roles for the Terragrunt CI/CD pipeline.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [AWS OIDC Provider Setup](#aws-oidc-provider-setup)
4. [IAM Role Creation](#iam-role-creation)
5. [GitHub Secrets Configuration](#github-secrets-configuration)
6. [GitHub Environments Setup](#github-environments-setup)
7. [Testing the Pipeline](#testing-the-pipeline)
8. [Troubleshooting](#troubleshooting)

---

## Overview

The CI/CD pipeline uses **AWS OIDC (OpenID Connect)** for authentication instead of long-lived AWS access keys. This provides:

- ✅ **No long-lived credentials** to manage or rotate
- ✅ **Automatic token expiration** (1 hour sessions)
- ✅ **Fine-grained permissions** per environment
- ✅ **Audit trail** via CloudTrail with GitHub context
- ✅ **Reduced security risk** if GitHub is compromised

### Workflow Architecture

```
┌─────────────────┐
│  GitHub Actions │
│   (PR opened)   │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────┐
│ terragrunt-plan.yml         │
│ - Detects changed envs      │
│ - Runs plan for each env    │
│ - Posts results to PR       │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│  Merge to main              │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│ terragrunt-apply.yml        │
│ - Non-prod: Auto-applies    │
│ - Prod: Requires approval   │
└─────────────────────────────┘
```

---

## Prerequisites

Before starting, ensure you have:

- [x] AWS CLI configured with admin privileges (`AWS_PROFILE=lightwave-admin-new`)
- [x] Terraform/OpenTofu and Terragrunt installed locally
- [x] Repository admin access to configure GitHub settings
- [x] Access to the AWS account where infrastructure will be deployed

---

## AWS OIDC Provider Setup

### Step 1: Create OIDC Identity Provider

The OIDC provider allows GitHub Actions to authenticate with AWS without credentials.

**Option A: Using AWS Console**

1. Navigate to **IAM → Identity Providers**
2. Click **Add Provider**
3. Select **OpenID Connect**
4. Configure:
   - **Provider URL:** `https://token.actions.githubusercontent.com`
   - **Audience:** `sts.amazonaws.com`
5. Click **Add Provider**

**Option B: Using AWS CLI**

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 \
  --profile lightwave-admin-new
```

**Option C: Using Terraform/OpenTofu**

Create `github-oidc-provider.tf` in your infrastructure modules:

```hcl
resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1"
  ]

  tags = {
    Name        = "github-actions-oidc"
    ManagedBy   = "Terraform"
    Environment = "shared"
  }
}
```

### Step 2: Verify OIDC Provider

```bash
aws iam list-open-id-connect-providers --profile lightwave-admin-new
```

You should see output like:

```json
{
  "OpenIDConnectProviderList": [
    {
      "Arn": "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    }
  ]
}
```

---

## IAM Role Creation

### Step 3: Create IAM Policy for Terragrunt

Create a policy with the minimum permissions needed for Terragrunt operations.

**Create `github-actions-terragrunt-policy.json`:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TerraformStateManagement",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::lightwave-terraform-state-*",
        "arn:aws:s3:::lightwave-terraform-state-*/*"
      ]
    },
    {
      "Sid": "TerraformStateLocking",
      "Effect": "Allow",
      "Action": [
        "dynamodb:DescribeTable",
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:*:*:table/lightwave-terraform-locks"
    },
    {
      "Sid": "InfrastructureDeployment",
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "ecs:*",
        "rds:*",
        "elasticache:*",
        "elasticloadbalancing:*",
        "cloudwatch:*",
        "logs:*",
        "iam:GetRole",
        "iam:PassRole",
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:GetPolicy",
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "kms:Decrypt",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    },
    {
      "Sid": "NetworkingServices",
      "Effect": "Allow",
      "Action": [
        "route53:*",
        "acm:*",
        "cloudfront:*"
      ],
      "Resource": "*"
    }
  ]
}
```

**Create the policy:**

```bash
aws iam create-policy \
  --policy-name GitHubActionsTerragruntPolicy \
  --policy-document file://github-actions-terragrunt-policy.json \
  --description "Permissions for GitHub Actions to run Terragrunt deployments" \
  --profile lightwave-admin-new
```

**Note the ARN output** - you'll need it in the next step.

### Step 4: Create IAM Role for GitHub Actions

**Create `github-actions-trust-policy.json`:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:lightwave-media/lightwave-infrastructure-live:*"
        }
      }
    }
  ]
}
```

**Replace `YOUR_ACCOUNT_ID`** with your actual AWS account ID:

```bash
# Get your account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile lightwave-admin-new)

# Update the trust policy
sed -i "" "s/YOUR_ACCOUNT_ID/$AWS_ACCOUNT_ID/g" github-actions-trust-policy.json
```

**Create the IAM role:**

```bash
aws iam create-role \
  --role-name GitHubActionsInfrastructureRole \
  --assume-role-policy-document file://github-actions-trust-policy.json \
  --description "Role for GitHub Actions to deploy infrastructure via Terragrunt" \
  --profile lightwave-admin-new
```

**Attach the policy to the role:**

```bash
# Get the policy ARN (replace with your actual policy ARN from step 3)
POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/GitHubActionsTerragruntPolicy"

aws iam attach-role-policy \
  --role-name GitHubActionsInfrastructureRole \
  --policy-arn "$POLICY_ARN" \
  --profile lightwave-admin-new
```

### Step 5: Get the Role ARN

```bash
aws iam get-role \
  --role-name GitHubActionsInfrastructureRole \
  --query 'Role.Arn' \
  --output text \
  --profile lightwave-admin-new
```

**Save this ARN** - you'll need it for GitHub secrets.

Example output:
```
arn:aws:iam::123456789012:role/GitHubActionsInfrastructureRole
```

---

## GitHub Secrets Configuration

### Step 6: Add GitHub Repository Secrets

1. Navigate to your repository: `https://github.com/lightwave-media/lightwave-infrastructure-live`
2. Go to **Settings → Secrets and variables → Actions**
3. Click **New repository secret**

**Required Secrets:**

| Secret Name | Value | Description |
|-------------|-------|-------------|
| `AWS_GITHUB_ACTIONS_ROLE_ARN` | `arn:aws:iam::123456789012:role/GitHubActionsInfrastructureRole` | IAM role ARN from Step 5 |

**Important:** Do NOT add `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` - OIDC doesn't need them!

---

## GitHub Environments Setup

GitHub Environments provide deployment protection rules and approval gates.

### Step 7: Create Environments

1. Navigate to **Settings → Environments**
2. Create the following environments:

#### Environment: `non-prod-plan`

- **Description:** Non-production plan operations
- **Protection Rules:** None (plans don't modify infrastructure)
- **Deployment branches:** Any branch

#### Environment: `non-prod`

- **Description:** Non-production deployments
- **Protection Rules:**
  - ✅ Wait timer: 30 seconds (time to cancel if needed)
- **Deployment branches:** Only `main` branch

#### Environment: `prod-plan`

- **Description:** Production plan operations
- **Protection Rules:** None (plans don't modify infrastructure)
- **Deployment branches:** Any branch

#### Environment: `production`

- **Description:** Production deployments
- **Protection Rules:**
  - ✅ **Required reviewers:** Add your infrastructure team (at least 1 required)
  - ✅ Wait timer: 5 minutes (for final review)
  - ✅ Prevent self-review: Enabled
- **Deployment branches:** Only `main` branch

#### Environment: `non-prod-destroy` (optional)

- **Description:** For emergency teardown of non-prod
- **Protection Rules:**
  - ✅ Required reviewers: 1
- **Deployment branches:** Only `main` branch

### Step 8: Configure Branch Protection

1. Navigate to **Settings → Branches**
2. Add rule for `main` branch:
   - ✅ Require pull request reviews before merging (1 approval)
   - ✅ Require status checks to pass before merging
     - Add: `Detect Changed Environments`
     - Add: `Plan Non-Prod Infrastructure` (if applicable)
     - Add: `Plan Production Infrastructure` (if applicable)
   - ✅ Require conversation resolution before merging
   - ✅ Do not allow bypassing the above settings

---

## Testing the Pipeline

### Step 9: Test PR Workflow

1. Create a test branch:
   ```bash
   git checkout -b test/ci-cd-pipeline
   ```

2. Make a trivial change to non-prod infrastructure:
   ```bash
   # Example: Update a tag in non-prod
   cd non-prod/us-east-1
   # Edit any module's terragrunt.hcl and add a tag
   ```

3. Commit and push:
   ```bash
   git add .
   git commit -m "test: verify CI/CD pipeline with trivial change"
   git push origin test/ci-cd-pipeline
   ```

4. Create a pull request on GitHub

5. **Verify the following:**
   - ✅ `terragrunt-plan.yml` workflow starts automatically
   - ✅ Plan output is posted as a PR comment
   - ✅ No errors in workflow logs
   - ✅ Changes detected correctly

### Step 10: Test Auto-Apply (Non-Prod)

1. Merge the test PR after approval

2. **Verify the following:**
   - ✅ `terragrunt-apply.yml` workflow starts automatically
   - ✅ Non-prod plan runs successfully
   - ✅ Non-prod apply runs after 30 second wait timer
   - ✅ Changes are applied to AWS
   - ✅ Smoke tests run (if configured)

### Step 11: Test Manual Approval (Production)

1. Create another test branch with prod changes:
   ```bash
   git checkout -b test/prod-deployment
   # Make a change in prod/us-east-1
   ```

2. Create PR, review plan, merge

3. **Verify the following:**
   - ✅ `terragrunt-apply.yml` workflow starts
   - ✅ Production plan runs
   - ✅ Workflow pauses at `production` environment
   - ✅ Approval request sent to configured reviewers
   - ✅ After approval, apply runs
   - ✅ Production state backup runs before apply

---

## Troubleshooting

### Issue: "Error: Not authorized to perform sts:AssumeRoleWithWebIdentity"

**Cause:** Trust relationship doesn't allow GitHub Actions to assume the role.

**Solution:**
1. Verify the trust policy includes the correct repository name:
   ```bash
   aws iam get-role --role-name GitHubActionsInfrastructureRole --profile lightwave-admin-new
   ```

2. Ensure the `StringLike` condition matches:
   ```json
   "token.actions.githubusercontent.com:sub": "repo:lightwave-media/lightwave-infrastructure-live:*"
   ```

3. Update trust policy if needed:
   ```bash
   aws iam update-assume-role-policy \
     --role-name GitHubActionsInfrastructureRole \
     --policy-document file://github-actions-trust-policy.json \
     --profile lightwave-admin-new
   ```

### Issue: "Error acquiring state lock"

**Cause:** Previous workflow crashed and didn't release the lock.

**Solution:**
1. Check for active locks:
   ```bash
   aws dynamodb scan \
     --table-name lightwave-terraform-locks \
     --profile lightwave-admin-new
   ```

2. Force unlock if safe (no operations running):
   ```bash
   cd non-prod/us-east-1/<module>
   terragrunt force-unlock <LOCK_ID>
   ```

### Issue: "OpenTofu/Terragrunt not found"

**Cause:** Incorrect installation in workflow.

**Solution:**
- Check the workflow versions match installed versions:
  ```yaml
  TERRAGRUNT_VERSION: 0.82.3
  OPENTOFU_VERSION: 1.9.0
  ```

- Verify download URLs are correct and accessible

### Issue: "Plan output not posted to PR"

**Cause:** GitHub token doesn't have PR write permissions.

**Solution:**
- Ensure workflow has correct permissions:
  ```yaml
  permissions:
    contents: read
    pull-requests: write
    id-token: write
  ```

### Issue: "Workflow not triggering on PR"

**Cause:** File path filters don't match changed files.

**Solution:**
- Check `paths` in workflow triggers:
  ```yaml
  paths:
    - 'non-prod/**'
    - 'prod/**'
    - 'root.hcl'
  ```

- Make sure your changes are in one of these directories

---

## Security Best Practices

### Principle of Least Privilege

The IAM policy provided is intentionally broad for initial setup. For production:

1. **Restrict by environment:**
   ```json
   "Condition": {
     "StringEquals": {
       "aws:ResourceTag/Environment": "non-prod"
     }
   }
   ```

2. **Separate roles per environment:**
   - Create `GitHubActionsNonProdRole` with limited permissions
   - Create `GitHubActionsProdRole` with full permissions
   - Use different secrets per environment

3. **Limit repository access:**
   ```json
   "StringEquals": {
     "token.actions.githubusercontent.com:sub": [
       "repo:lightwave-media/lightwave-infrastructure-live:ref:refs/heads/main"
     ]
   }
   ```

### Audit Logging

Enable CloudTrail to track all GitHub Actions API calls:

```bash
# CloudTrail logs will show:
# - Which GitHub workflow assumed the role
# - Which repository and commit triggered the action
# - All AWS API calls made during the workflow
```

### Secret Rotation

- OIDC tokens automatically expire after 1 hour
- No manual credential rotation needed
- IAM role credentials are temporary and short-lived

---

## Next Steps

1. ✅ Configure monitoring and alerting for failed deployments
2. ✅ Set up Slack notifications for deployment events
3. ✅ Create runbooks for common failure scenarios
4. ✅ Implement drift detection workflow
5. ✅ Add cost estimation to PR comments (Infracost)

---

## Additional Resources

- [GitHub Actions OIDC with AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [Terragrunt Best Practices](https://terragrunt.gruntwork.io/docs/getting-started/quick-start/)
- [AWS IAM Roles for OIDC](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [Gruntwork Security Best Practices](https://gruntwork.io/guides/foundations/how-to-configure-production-grade-aws-account-structure/)

---

**Last Updated:** 2025-10-28
**Maintained By:** Platform Team
**Version:** 1.0.0
