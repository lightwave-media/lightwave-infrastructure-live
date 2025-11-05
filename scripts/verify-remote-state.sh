#!/bin/bash
# Verifies remote state is healthy before deployment
# Usage: ./verify-remote-state.sh [environment] [region]
# Example: ./verify-remote-state.sh non-prod us-east-1

set -euo pipefail

# Configuration
AWS_PROFILE=${AWS_PROFILE:-lightwave-admin-new}
ENVIRONMENT=${1:-non-prod}
REGION=${2:-us-east-1}
BUCKET="lightwave-terraform-state-${ENVIRONMENT}-${REGION}"
TABLE="lightwave-terraform-locks"

# Detect if running in GitHub Actions (uses OIDC, no profile needed)
if [ -n "${GITHUB_ACTIONS:-}" ]; then
    AWS_CLI_ARGS=()
else
    AWS_CLI_ARGS=("--profile" "${AWS_PROFILE}")
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "Remote State Verification"
echo "========================================="
echo "Environment: ${ENVIRONMENT}"
echo "Region:      ${REGION}"
echo "Bucket:      ${BUCKET}"
echo "Lock Table:  ${TABLE}"
echo "AWS Profile: ${AWS_PROFILE}"
echo "========================================="
echo ""

# Verify AWS credentials
if ! aws sts get-caller-identity "${AWS_CLI_ARGS[@]}" > /dev/null 2>&1; then
    echo -e "${RED}❌ Failed to authenticate with AWS${NC}"
    echo "Please verify your AWS credentials are configured correctly."
    exit 1
fi

echo -e "${GREEN}✅ AWS credentials verified${NC}"

# Check S3 bucket
echo ""
echo "Checking S3 bucket..."
if aws s3 ls "s3://${BUCKET}" "${AWS_CLI_ARGS[@]}" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ S3 bucket accessible: ${BUCKET}${NC}"

    # Check versioning
    VERSIONING=$(aws s3api get-bucket-versioning --bucket "${BUCKET}" "${AWS_CLI_ARGS[@]}" --query 'Status' --output text 2>/dev/null || echo "Disabled")
    if [ "${VERSIONING}" == "Enabled" ]; then
        echo -e "${GREEN}✅ S3 versioning enabled${NC}"
    else
        echo -e "${YELLOW}⚠️  S3 versioning not enabled (recommended for state files)${NC}"
    fi
else
    echo -e "${RED}❌ S3 bucket NOT accessible: ${BUCKET}${NC}"
    echo "The state bucket may not exist or you lack permissions."
    echo "To create: aws s3 mb s3://${BUCKET} --profile ${AWS_PROFILE}"
    exit 1
fi

# Check DynamoDB table
echo ""
echo "Checking DynamoDB lock table..."
if aws dynamodb describe-table --table-name "${TABLE}" "${AWS_CLI_ARGS[@]}" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ DynamoDB lock table accessible: ${TABLE}${NC}"

    TABLE_STATUS=$(aws dynamodb describe-table --table-name "${TABLE}" "${AWS_CLI_ARGS[@]}" --query 'Table.TableStatus' --output text)
    if [ "${TABLE_STATUS}" == "ACTIVE" ]; then
        echo -e "${GREEN}✅ Table status: ACTIVE${NC}"
    else
        echo -e "${YELLOW}⚠️  Table status: ${TABLE_STATUS}${NC}"
    fi
else
    echo -e "${RED}❌ DynamoDB lock table NOT accessible: ${TABLE}${NC}"
    echo "The lock table may not exist or you lack permissions."
    exit 1
fi

# Check for stale locks
echo ""
echo "Checking for stale locks..."
LOCK_COUNT=$(aws dynamodb scan \
    --table-name "${TABLE}" \
    --select COUNT \
    "${AWS_CLI_ARGS[@]}" \
    --output text 2>/dev/null | awk '{print $2}' || echo "0")

if [ "${LOCK_COUNT}" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Warning: ${LOCK_COUNT} active locks found${NC}"
    echo "This may indicate ongoing operations or stale locks."
    echo ""
    echo "To view locks:"
    echo "  aws dynamodb scan --table-name ${TABLE} --profile ${AWS_PROFILE} --output table"
    echo ""
    echo "To force-unlock (CAUTION - only if no operations running):"
    echo "  cd <module-directory>"
    echo "  terragrunt force-unlock <LOCK_ID>"
else
    echo -e "${GREEN}✅ No active locks${NC}"
fi

# Summary
echo ""
echo "========================================="
echo -e "${GREEN}✅ Remote state verification complete${NC}"
echo "========================================="
echo ""
echo "You can now safely run Terragrunt commands."

exit 0
