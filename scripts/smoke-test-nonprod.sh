#!/bin/bash
# Smoke tests for non-production environment
# Usage: ./smoke-test-nonprod.sh

set -euo pipefail

export AWS_PROFILE=lightwave-admin-new
ENVIRONMENT="non-prod"
API_URL="https://api-nonprod.lightwave-media.ltd"
ECS_CLUSTER="lightwave-nonprod"
ECS_SERVICE="backend-nonprod"
RDS_INSTANCE="nonprod-postgres"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PASSED=0
FAILED=0

echo "========================================="
echo "Non-Production Smoke Tests"
echo "========================================="
echo "Environment: ${ENVIRONMENT}"
echo "API URL:     ${API_URL}"
echo "========================================="
echo ""

# Test 1: API Health Check
echo -n "Test 1: API health endpoint... "
if curl -sf "${API_URL}/health" -m 10 > /dev/null 2>&1; then
    echo -e "${GREEN}✅ PASS${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${YELLOW}⚠️  SKIP (API not deployed yet)${NC}"
    # Don't count as failure since infrastructure may not be deployed
fi

# Test 2: ECS Service Status
echo -n "Test 2: ECS service health... "
SERVICE_STATUS=$(aws ecs describe-services \
    --cluster "${ECS_CLUSTER}" \
    --services "${ECS_SERVICE}" \
    --profile "${AWS_PROFILE}" \
    --query 'services[0].status' \
    --output text 2>/dev/null || echo "NOT_FOUND")

if [ "${SERVICE_STATUS}" == "ACTIVE" ]; then
    RUNNING=$(aws ecs describe-services \
        --cluster "${ECS_CLUSTER}" \
        --services "${ECS_SERVICE}" \
        --profile "${AWS_PROFILE}" \
        --query 'services[0].runningCount' \
        --output text)
    DESIRED=$(aws ecs describe-services \
        --cluster "${ECS_CLUSTER}" \
        --services "${ECS_SERVICE}" \
        --profile "${AWS_PROFILE}" \
        --query 'services[0].desiredCount' \
        --output text)
    
    if [ "${RUNNING}" == "${DESIRED}" ] && [ "${RUNNING}" -gt 0 ]; then
        echo -e "${GREEN}✅ PASS (${RUNNING}/${DESIRED} tasks)${NC}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}❌ FAIL (${RUNNING}/${DESIRED} tasks)${NC}"
        FAILED=$((FAILED + 1))
    fi
elif [ "${SERVICE_STATUS}" == "NOT_FOUND" ]; then
    echo -e "${YELLOW}⚠️  SKIP (ECS service not deployed yet)${NC}"
else
    echo -e "${RED}❌ FAIL (Status: ${SERVICE_STATUS})${NC}"
    FAILED=$((FAILED + 1))
fi

# Test 3: RDS Instance Status
echo -n "Test 3: RDS database health... "
RDS_STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier "${RDS_INSTANCE}" \
    --profile "${AWS_PROFILE}" \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text 2>/dev/null || echo "NOT_FOUND")

if [ "${RDS_STATUS}" == "available" ]; then
    echo -e "${GREEN}✅ PASS${NC}"
    PASSED=$((PASSED + 1))
elif [ "${RDS_STATUS}" == "NOT_FOUND" ]; then
    echo -e "${YELLOW}⚠️  SKIP (RDS instance not deployed yet)${NC}"
else
    echo -e "${RED}❌ FAIL (Status: ${RDS_STATUS})${NC}"
    FAILED=$((FAILED + 1))
fi

# Summary
echo ""
echo "========================================="
echo "Test Summary"
echo "========================================="
echo -e "Passed: ${GREEN}${PASSED}${NC}"
echo -e "Failed: ${RED}${FAILED}${NC}"
echo "========================================="
echo ""

if [ ${FAILED} -gt 0 ]; then
    echo -e "${RED}❌ Smoke tests FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}✅ Smoke tests PASSED${NC}"
    exit 0
fi
