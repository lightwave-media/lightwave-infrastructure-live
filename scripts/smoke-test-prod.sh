#!/bin/bash
# Smoke tests for production environment
# Usage: ./smoke-test-prod.sh

set -euo pipefail

export AWS_PROFILE=lightwave-admin-new
ENVIRONMENT="prod"
API_URL="https://api.lightwave-media.ltd"
ECS_CLUSTER="lightwave-prod"
ECS_SERVICE="backend-prod"
RDS_INSTANCE="prod-postgres"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PASSED=0
FAILED=0

echo "========================================="
echo "Production Smoke Tests"
echo "========================================="
echo "Environment: ${ENVIRONMENT}"
echo "API URL:     ${API_URL}"
echo "========================================="
echo ""

# Test 1: API Health Check
echo -n "Test 1: API health endpoint... "
HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" "${API_URL}/health" -m 10 2>/dev/null || echo "000")

if [ "${HTTP_CODE}" == "200" ]; then
    echo -e "${GREEN}✅ PASS (HTTP ${HTTP_CODE})${NC}"
    PASSED=$((PASSED + 1))
elif [ "${HTTP_CODE}" == "000" ]; then
    echo -e "${RED}❌ FAIL (Connection failed)${NC}"
    FAILED=$((FAILED + 1))
else
    echo -e "${RED}❌ FAIL (HTTP ${HTTP_CODE})${NC}"
    FAILED=$((FAILED + 1))
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
    echo -e "${RED}❌ FAIL (ECS service not found)${NC}"
    FAILED=$((FAILED + 1))
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
    echo -e "${RED}❌ FAIL (RDS instance not found)${NC}"
    FAILED=$((FAILED + 1))
else
    echo -e "${RED}❌ FAIL (Status: ${RDS_STATUS})${NC}"
    FAILED=$((FAILED + 1))
fi

# Test 4: Check for Recent Errors
echo -n "Test 4: Recent error rate... "
END_TIME=$(date -u +%s)
START_TIME=$((END_TIME - 300))  # Last 5 minutes

ERROR_COUNT=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/ECS \
    --metric-name HTTPCode_Target_5XX_Count \
    --dimensions Name=ServiceName,Value="${ECS_SERVICE}" \
    --start-time "$(date -u -d @${START_TIME} +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u -d @${END_TIME} +%Y-%m-%dT%H:%M:%S)" \
    --period 300 \
    --statistics Sum \
    --profile "${AWS_PROFILE}" \
    --query 'Datapoints[0].Sum' \
    --output text 2>/dev/null || echo "0")

if [ "${ERROR_COUNT}" == "None" ] || [ "${ERROR_COUNT}" == "0" ] || [ -z "${ERROR_COUNT}" ]; then
    echo -e "${GREEN}✅ PASS (No errors)${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${YELLOW}⚠️  WARN (${ERROR_COUNT} errors in last 5 min)${NC}"
    # Not counted as failure - just a warning
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
    echo "Production deployment may have issues. Investigate immediately."
    exit 1
else
    echo -e "${GREEN}✅ Smoke tests PASSED${NC}"
    exit 0
fi
