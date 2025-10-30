#!/bin/bash
# Setup AWS OIDC provider and IAM role for GitHub Actions
# Usage: ./setup-github-oidc.sh [github-org] [github-repo]
# Example: ./setup-github-oidc.sh lightwave-media lightwave-infrastructure-live

set -euo pipefail

# Configuration
AWS_PROFILE=${AWS_PROFILE:-lightwave-admin-new}
GITHUB_ORG=${1:-lightwave-media}
GITHUB_REPO=${2:-lightwave-infrastructure-live}
ROLE_NAME="GitHubActionsInfrastructureRole"
POLICY_NAME="GitHubActionsTerragruntPolicy"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "========================================="
echo "GitHub Actions OIDC Setup for AWS"
echo "========================================="
echo "GitHub Org:  ${GITHUB_ORG}"
echo "GitHub Repo: ${GITHUB_REPO}"
echo "AWS Profile: ${AWS_PROFILE}"
echo "Role Name:   ${ROLE_NAME}"
echo "========================================="
echo ""

# Get AWS account ID
echo -e "${BLUE}[1/5] Retrieving AWS account ID...${NC}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile "${AWS_PROFILE}")
echo -e "${GREEN}✅ AWS Account ID: ${AWS_ACCOUNT_ID}${NC}"
echo ""

# Check if OIDC provider already exists
echo -e "${BLUE}[2/5] Checking for existing OIDC provider...${NC}"
OIDC_PROVIDER_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "${OIDC_PROVIDER_ARN}" --profile "${AWS_PROFILE}" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ OIDC provider already exists${NC}"
else
    echo -e "${YELLOW}⚠️  OIDC provider not found, creating...${NC}"
    aws iam create-open-id-connect-provider \
        --url https://token.actions.githubusercontent.com \
        --client-id-list sts.amazonaws.com \
        --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 \
        --profile "${AWS_PROFILE}"
    echo -e "${GREEN}✅ OIDC provider created${NC}"
fi
echo ""

# Create IAM policy
echo -e "${BLUE}[3/5] Creating IAM policy for Terragrunt...${NC}"

cat > /tmp/github-actions-policy.json <<EOF
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
        "s3:DeleteObject",
        "s3:GetBucketVersioning",
        "s3:GetBucketLocation"
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
        "dynamodb:DeleteItem",
        "dynamodb:Scan"
      ],
      "Resource": "arn:aws:dynamodb:*:*:table/lightwave-terraform-locks"
    },
    {
      "Sid": "EC2Management",
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "ec2:Get*",
        "ec2:List*",
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupEgress",
        "ec2:CreateVpc",
        "ec2:DeleteVpc",
        "ec2:ModifyVpcAttribute",
        "ec2:CreateSubnet",
        "ec2:DeleteSubnet",
        "ec2:CreateInternetGateway",
        "ec2:DeleteInternetGateway",
        "ec2:AttachInternetGateway",
        "ec2:DetachInternetGateway",
        "ec2:CreateRouteTable",
        "ec2:DeleteRouteTable",
        "ec2:CreateRoute",
        "ec2:DeleteRoute",
        "ec2:AssociateRouteTable",
        "ec2:DisassociateRouteTable"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ECSManagement",
      "Effect": "Allow",
      "Action": [
        "ecs:*",
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ],
      "Resource": "*"
    },
    {
      "Sid": "RDSManagement",
      "Effect": "Allow",
      "Action": [
        "rds:Describe*",
        "rds:List*",
        "rds:CreateDBInstance",
        "rds:DeleteDBInstance",
        "rds:ModifyDBInstance",
        "rds:CreateDBSubnetGroup",
        "rds:DeleteDBSubnetGroup",
        "rds:ModifyDBSubnetGroup",
        "rds:AddTagsToResource",
        "rds:RemoveTagsFromResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ElastiCacheManagement",
      "Effect": "Allow",
      "Action": [
        "elasticache:Describe*",
        "elasticache:List*",
        "elasticache:CreateCacheCluster",
        "elasticache:DeleteCacheCluster",
        "elasticache:ModifyCacheCluster",
        "elasticache:CreateCacheSubnetGroup",
        "elasticache:DeleteCacheSubnetGroup",
        "elasticache:ModifyCacheSubnetGroup",
        "elasticache:AddTagsToResource",
        "elasticache:RemoveTagsFromResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "LoadBalancerManagement",
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:Describe*",
        "elasticloadbalancing:CreateLoadBalancer",
        "elasticloadbalancing:DeleteLoadBalancer",
        "elasticloadbalancing:ModifyLoadBalancerAttributes",
        "elasticloadbalancing:CreateTargetGroup",
        "elasticloadbalancing:DeleteTargetGroup",
        "elasticloadbalancing:ModifyTargetGroup",
        "elasticloadbalancing:CreateListener",
        "elasticloadbalancing:DeleteListener",
        "elasticloadbalancing:ModifyListener",
        "elasticloadbalancing:AddTags",
        "elasticloadbalancing:RemoveTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchAndLogs",
      "Effect": "Allow",
      "Action": [
        "cloudwatch:*",
        "logs:CreateLogGroup",
        "logs:DeleteLogGroup",
        "logs:DescribeLogGroups",
        "logs:PutRetentionPolicy",
        "logs:TagLogGroup",
        "logs:UntagLogGroup"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMManagement",
      "Effect": "Allow",
      "Action": [
        "iam:GetRole",
        "iam:GetRolePolicy",
        "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies",
        "iam:PassRole",
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:CreatePolicy",
        "iam:CreatePolicyVersion",
        "iam:DeletePolicy",
        "iam:DeletePolicyVersion"
      ],
      "Resource": [
        "arn:aws:iam::${AWS_ACCOUNT_ID}:role/lightwave-*",
        "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/lightwave-*"
      ]
    },
    {
      "Sid": "SecretsManagement",
      "Effect": "Allow",
      "Action": [
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
        "route53:Get*",
        "route53:List*",
        "route53:CreateHostedZone",
        "route53:DeleteHostedZone",
        "route53:ChangeResourceRecordSets",
        "acm:Describe*",
        "acm:List*",
        "acm:RequestCertificate",
        "acm:DeleteCertificate"
      ],
      "Resource": "*"
    }
  ]
}
EOF

POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"

if aws iam get-policy --policy-arn "${POLICY_ARN}" --profile "${AWS_PROFILE}" > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Policy already exists, updating...${NC}"

    # Get current default version
    CURRENT_VERSION=$(aws iam get-policy --policy-arn "${POLICY_ARN}" --profile "${AWS_PROFILE}" --query 'Policy.DefaultVersionId' --output text)

    # Create new version
    aws iam create-policy-version \
        --policy-arn "${POLICY_ARN}" \
        --policy-document file:///tmp/github-actions-policy.json \
        --set-as-default \
        --profile "${AWS_PROFILE}" > /dev/null

    # Delete old version
    if [ "${CURRENT_VERSION}" != "v1" ]; then
        aws iam delete-policy-version \
            --policy-arn "${POLICY_ARN}" \
            --version-id "${CURRENT_VERSION}" \
            --profile "${AWS_PROFILE}" || true
    fi

    echo -e "${GREEN}✅ Policy updated${NC}"
else
    aws iam create-policy \
        --policy-name "${POLICY_NAME}" \
        --policy-document file:///tmp/github-actions-policy.json \
        --description "Permissions for GitHub Actions to run Terragrunt deployments" \
        --profile "${AWS_PROFILE}" > /dev/null
    echo -e "${GREEN}✅ Policy created${NC}"
fi
echo ""

# Create trust policy
echo -e "${BLUE}[4/5] Creating IAM role with trust policy...${NC}"

cat > /tmp/github-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${OIDC_PROVIDER_ARN}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_ORG}/${GITHUB_REPO}:*"
        }
      }
    }
  ]
}
EOF

ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"

if aws iam get-role --role-name "${ROLE_NAME}" --profile "${AWS_PROFILE}" > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Role already exists, updating trust policy...${NC}"
    aws iam update-assume-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-document file:///tmp/github-trust-policy.json \
        --profile "${AWS_PROFILE}"
    echo -e "${GREEN}✅ Trust policy updated${NC}"
else
    aws iam create-role \
        --role-name "${ROLE_NAME}" \
        --assume-role-policy-document file:///tmp/github-trust-policy.json \
        --description "Role for GitHub Actions to deploy infrastructure via Terragrunt" \
        --profile "${AWS_PROFILE}" > /dev/null
    echo -e "${GREEN}✅ Role created${NC}"
fi
echo ""

# Attach policy to role
echo -e "${BLUE}[5/5] Attaching policy to role...${NC}"
if aws iam list-attached-role-policies --role-name "${ROLE_NAME}" --profile "${AWS_PROFILE}" | grep -q "${POLICY_NAME}"; then
    echo -e "${GREEN}✅ Policy already attached${NC}"
else
    aws iam attach-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-arn "${POLICY_ARN}" \
        --profile "${AWS_PROFILE}"
    echo -e "${GREEN}✅ Policy attached to role${NC}"
fi
echo ""

# Cleanup temp files
rm -f /tmp/github-actions-policy.json /tmp/github-trust-policy.json

# Summary
echo "========================================="
echo -e "${GREEN}✅ Setup Complete!${NC}"
echo "========================================="
echo ""
echo "📋 Next Steps:"
echo ""
echo "1. Add this secret to GitHub repository secrets:"
echo "   Name:  AWS_GITHUB_ACTIONS_ROLE_ARN"
echo "   Value: ${ROLE_ARN}"
echo ""
echo "2. Configure GitHub Environments:"
echo "   - non-prod-plan (no protection)"
echo "   - non-prod (30s wait timer)"
echo "   - prod-plan (no protection)"
echo "   - production (manual approval required)"
echo ""
echo "3. Test the pipeline:"
echo "   - Create a PR with infrastructure changes"
echo "   - Verify plan runs and posts to PR"
echo "   - Merge and verify auto-apply (non-prod)"
echo ""
echo "📖 Full setup guide: docs/GITHUB_ACTIONS_SETUP.md"
echo ""
echo "========================================="

exit 0
