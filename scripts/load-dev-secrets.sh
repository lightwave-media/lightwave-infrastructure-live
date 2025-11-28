#!/bin/bash
# Load development secrets from AWS Secrets Manager into environment variables
# Usage: source ./load-dev-secrets.sh
#
# Note: This script must be sourced, not executed:
#   ✅ source scripts/load-dev-secrets.sh
#   ❌ ./scripts/load-dev-secrets.sh
#
# After sourcing, secrets will be available as environment variables:
#   - DATABASE_PASSWORD
#   - JWT_SECRET
#   - REDIS_AUTH_TOKEN

# Check if being sourced
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    echo "❌ Error: This script must be sourced, not executed"
    echo ""
    echo "Usage:"
    echo "  source scripts/load-dev-secrets.sh"
    echo "  OR"
    echo "  . scripts/load-dev-secrets.sh"
    exit 1
fi

# Configuration
export AWS_PROFILE=lightwave-admin-new
ENVIRONMENT="non-prod"
REGION="us-east-1"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "========================================="
echo "Loading Development Secrets"
echo "========================================="
echo "Environment: ${ENVIRONMENT}"
echo "Region:      ${REGION}"
echo "AWS Profile: ${AWS_PROFILE}"
echo "========================================="
echo ""

# Verify AWS credentials
if ! aws sts get-caller-identity --profile "${AWS_PROFILE}" > /dev/null 2>&1; then
    echo -e "${RED}❌ Failed to authenticate with AWS profile: ${AWS_PROFILE}${NC}"
    echo "Please configure your AWS credentials."
    return 1
fi

# Function to load a secret
load_secret() {
    local var_name=$1
    local secret_id=$2
    
    echo -n "Loading ${var_name}... "
    
    local secret_value
    secret_value=$(aws secretsmanager get-secret-value \
        --secret-id "${secret_id}" \
        --profile "${AWS_PROFILE}" \
        --region "${REGION}" \
        --query SecretString \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "${secret_value}" ]; then
        export "${var_name}=${secret_value}"
        echo -e "${GREEN}✅${NC}"
        return 0
    else
        export "${var_name}=SECRET_NOT_SET"
        echo -e "${YELLOW}⚠️  Not found${NC}"
        return 1
    fi
}

# Load secrets
MISSING_SECRETS=0

load_secret "DATABASE_PASSWORD" "/${ENVIRONMENT}/backend/database_password" || MISSING_SECRETS=$((MISSING_SECRETS + 1))
load_secret "JWT_SECRET" "/${ENVIRONMENT}/backend/jwt_secret" || MISSING_SECRETS=$((MISSING_SECRETS + 1))
load_secret "REDIS_AUTH_TOKEN" "/${ENVIRONMENT}/redis/auth_token" || MISSING_SECRETS=$((MISSING_SECRETS + 1))

echo ""
echo "========================================="

if [ ${MISSING_SECRETS} -eq 0 ]; then
    echo -e "${GREEN}✅ All secrets loaded successfully${NC}"
else
    echo -e "${YELLOW}⚠️  ${MISSING_SECRETS} secret(s) not found${NC}"
    echo ""
    echo "Secrets showing 'SECRET_NOT_SET' need to be created in AWS Secrets Manager."
    echo "See: .agent/sops/SOP_SECRETS_MANAGEMENT.md"
fi

echo "========================================="
echo ""
echo "Secrets are now available as environment variables:"
echo "  \$DATABASE_PASSWORD"
echo "  \$JWT_SECRET"
echo "  \$REDIS_AUTH_TOKEN"
echo ""
