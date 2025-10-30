#!/usr/bin/env bash
# ---------------------------------------------------------------------------------------------------------------------
# CREATE COST DASHBOARD
# Deploys CloudWatch dashboard for cost monitoring and resource utilization
# ---------------------------------------------------------------------------------------------------------------------

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DASHBOARD_JSON="${PROJECT_ROOT}/docs/cloudwatch-cost-dashboard.json"
DASHBOARD_NAME="LightWave-Cost-Monitoring"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=============================================="
echo "Creating CloudWatch Cost Dashboard"
echo "=============================================="
echo ""

# Check if dashboard JSON exists
if [ ! -f "$DASHBOARD_JSON" ]; then
    echo "ERROR: Dashboard JSON not found at $DASHBOARD_JSON"
    exit 1
fi

echo -e "${BLUE}Deploying dashboard: ${DASHBOARD_NAME}${NC}"
echo ""

# Create or update dashboard
aws cloudwatch put-dashboard \
    --dashboard-name "$DASHBOARD_NAME" \
    --dashboard-body "file://${DASHBOARD_JSON}"

echo ""
echo -e "${GREEN}✓ Dashboard created successfully!${NC}"
echo ""
echo "Access your dashboard at:"
echo "https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=${DASHBOARD_NAME}"
echo ""
echo "Dashboard features:"
echo "  - Total estimated monthly charges"
echo "  - Budget threshold annotations"
echo "  - RDS, ECS, ElastiCache utilization"
echo "  - S3 storage by tier"
echo "  - Load balancer usage"
echo "  - Data transfer metrics"
echo ""
