#!/usr/bin/env bash
# ---------------------------------------------------------------------------------------------------------------------
# COST REPORT - DAILY
# Generates daily cost report by service and environment
# ---------------------------------------------------------------------------------------------------------------------

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORTS_DIR="${PROJECT_ROOT}/.agent/cost-reports"
TODAY=$(date +%Y-%m-%d)
YESTERDAY=$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d '1 day ago' +%Y-%m-%d)
LAST_30_DAYS=$(date -v-30d +%Y-%m-%d 2>/dev/null || date -d '30 days ago' +%Y-%m-%d)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create reports directory
mkdir -p "$REPORTS_DIR"

echo "=============================================="
echo "LightWave Media - Daily Cost Report"
echo "Report Date: $TODAY"
echo "=============================================="
echo ""

# ---------------------------------------------------------------------------------------------------------------------
# Check AWS CLI and permissions
# ---------------------------------------------------------------------------------------------------------------------

check_aws_access() {
    echo -e "${BLUE}Checking AWS access...${NC}"

    if ! aws sts get-caller-identity &>/dev/null; then
        echo -e "${RED}ERROR: Unable to access AWS. Please ensure AWS_PROFILE is set correctly.${NC}"
        echo "Expected profile: lightwave-admin-new"
        exit 1
    fi

    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    echo -e "${GREEN}Connected to AWS Account: ${ACCOUNT_ID}${NC}"
    echo ""
}

# ---------------------------------------------------------------------------------------------------------------------
# Get yesterday's costs by service
# ---------------------------------------------------------------------------------------------------------------------

get_daily_costs() {
    echo -e "${BLUE}Fetching costs for ${YESTERDAY}...${NC}"

    aws ce get-cost-and-usage \
        --time-period Start="${YESTERDAY}",End="${TODAY}" \
        --granularity DAILY \
        --metrics BlendedCost UnblendedCost \
        --group-by Type=SERVICE \
        --output json > "${REPORTS_DIR}/daily-cost-${TODAY}.json"

    echo -e "${GREEN}Daily cost data saved to: ${REPORTS_DIR}/daily-cost-${TODAY}.json${NC}"
    echo ""
}

# ---------------------------------------------------------------------------------------------------------------------
# Get costs by environment (using tags)
# ---------------------------------------------------------------------------------------------------------------------

get_costs_by_environment() {
    echo -e "${BLUE}Fetching costs by environment...${NC}"

    aws ce get-cost-and-usage \
        --time-period Start="${YESTERDAY}",End="${TODAY}" \
        --granularity DAILY \
        --metrics BlendedCost \
        --group-by Type=TAG,Key=Environment \
        --output json > "${REPORTS_DIR}/daily-cost-by-env-${TODAY}.json"

    echo -e "${GREEN}Environment cost data saved to: ${REPORTS_DIR}/daily-cost-by-env-${TODAY}.json${NC}"
    echo ""
}

# ---------------------------------------------------------------------------------------------------------------------
# Parse and display top cost drivers
# ---------------------------------------------------------------------------------------------------------------------

display_top_services() {
    echo "=============================================="
    echo "Top 10 Cost Drivers - ${YESTERDAY}"
    echo "=============================================="

    # Extract and sort services by cost
    jq -r '
        .ResultsByTime[0].Groups[] |
        select(.Metrics.BlendedCost.Amount | tonumber > 0.01) |
        "\(.Keys[0])|\(.Metrics.BlendedCost.Amount)|\(.Metrics.BlendedCost.Unit)"
    ' "${REPORTS_DIR}/daily-cost-${TODAY}.json" | \
    sort -t'|' -k2 -rn | \
    head -10 | \
    awk -F'|' 'BEGIN {
        printf "%-40s %10s %s\n", "Service", "Cost", "Currency";
        printf "%s\n", "--------------------------------------------------------------------------------";
    }
    {
        printf "%-40s %10.2f %s\n", $1, $2, $3;
    }'

    echo ""
}

# ---------------------------------------------------------------------------------------------------------------------
# Display costs by environment
# ---------------------------------------------------------------------------------------------------------------------

display_environment_costs() {
    echo "=============================================="
    echo "Costs by Environment - ${YESTERDAY}"
    echo "=============================================="

    # Extract environment costs
    jq -r '
        .ResultsByTime[0].Groups[] |
        select(.Metrics.BlendedCost.Amount | tonumber > 0.01) |
        "\(.Keys[0])|\(.Metrics.BlendedCost.Amount)|\(.Metrics.BlendedCost.Unit)"
    ' "${REPORTS_DIR}/daily-cost-by-env-${TODAY}.json" | \
    sort -t'|' -k2 -rn | \
    awk -F'|' 'BEGIN {
        printf "%-20s %10s %s\n", "Environment", "Cost", "Currency";
        printf "%s\n", "------------------------------------------------";
    }
    {
        env = $1;
        # Extract environment value from tag
        gsub(/.*\$/, "", env);
        printf "%-20s %10.2f %s\n", env, $2, $3;
    }'

    echo ""
}

# ---------------------------------------------------------------------------------------------------------------------
# Calculate total daily cost
# ---------------------------------------------------------------------------------------------------------------------

display_daily_total() {
    TOTAL=$(jq -r '.ResultsByTime[0].Total.BlendedCost.Amount' "${REPORTS_DIR}/daily-cost-${TODAY}.json")
    CURRENCY=$(jq -r '.ResultsByTime[0].Total.BlendedCost.Unit' "${REPORTS_DIR}/daily-cost-${TODAY}.json")

    echo "=============================================="
    echo -e "Total Cost for ${YELLOW}${YESTERDAY}${NC}: ${GREEN}\$${TOTAL} ${CURRENCY}${NC}"
    echo "=============================================="
    echo ""

    # Calculate monthly projection
    MONTHLY_PROJECTION=$(echo "$TOTAL * 30" | bc)
    echo -e "Projected Monthly Cost: ${YELLOW}\$${MONTHLY_PROJECTION} ${CURRENCY}${NC}"
    echo ""
}

# ---------------------------------------------------------------------------------------------------------------------
# Get last 30 days trend
# ---------------------------------------------------------------------------------------------------------------------

get_30_day_trend() {
    echo -e "${BLUE}Fetching 30-day cost trend...${NC}"

    aws ce get-cost-and-usage \
        --time-period Start="${LAST_30_DAYS}",End="${TODAY}" \
        --granularity DAILY \
        --metrics BlendedCost \
        --output json > "${REPORTS_DIR}/30-day-trend-${TODAY}.json"

    echo ""
    echo "=============================================="
    echo "Last 30 Days Cost Trend"
    echo "=============================================="

    # Display simple trend
    jq -r '.ResultsByTime[] | "\(.TimePeriod.Start)|\(.Total.BlendedCost.Amount)"' \
        "${REPORTS_DIR}/30-day-trend-${TODAY}.json" | \
        tail -10 | \
        awk -F'|' 'BEGIN {
            printf "%-12s %10s\n", "Date", "Cost ($)";
            printf "%s\n", "------------------------";
        }
        {
            printf "%-12s %10.2f\n", $1, $2;
        }'

    echo ""
}

# ---------------------------------------------------------------------------------------------------------------------
# Check for cost anomalies
# ---------------------------------------------------------------------------------------------------------------------

check_anomalies() {
    echo -e "${BLUE}Checking for cost anomalies...${NC}"
    echo ""

    # Get average daily cost for last 7 days
    LAST_7_DAYS=$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d '7 days ago' +%Y-%m-%d)

    aws ce get-cost-and-usage \
        --time-period Start="${LAST_7_DAYS}",End="${YESTERDAY}" \
        --granularity DAILY \
        --metrics BlendedCost \
        --output json > "${REPORTS_DIR}/7-day-comparison.json"

    # Calculate 7-day average (excluding today)
    AVG_7_DAY=$(jq -r '[.ResultsByTime[].Total.BlendedCost.Amount | tonumber] | add / length' \
        "${REPORTS_DIR}/7-day-comparison.json")

    YESTERDAY_COST=$(jq -r '.ResultsByTime[0].Total.BlendedCost.Amount | tonumber' \
        "${REPORTS_DIR}/daily-cost-${TODAY}.json")

    # Check if yesterday's cost is >20% higher than 7-day average
    THRESHOLD=$(echo "$AVG_7_DAY * 1.2" | bc)

    if (( $(echo "$YESTERDAY_COST > $THRESHOLD" | bc -l) )); then
        INCREASE_PCT=$(echo "scale=1; ($YESTERDAY_COST - $AVG_7_DAY) / $AVG_7_DAY * 100" | bc)
        echo -e "${YELLOW}⚠️  ANOMALY DETECTED${NC}"
        echo -e "Yesterday's cost (\$${YESTERDAY_COST}) is ${INCREASE_PCT}% higher than 7-day average (\$${AVG_7_DAY})"
        echo ""
        echo "Action Required:"
        echo "1. Review top cost drivers above"
        echo "2. Check AWS Cost Explorer for service-level anomalies"
        echo "3. Verify no unauthorized resources were created"
        echo "4. Consider running: ./scripts/check-idle-resources.sh"
    else
        echo -e "${GREEN}✓ No cost anomalies detected${NC}"
        echo "Yesterday's cost is within normal range (7-day average: \$${AVG_7_DAY})"
    fi

    echo ""
}

# ---------------------------------------------------------------------------------------------------------------------
# Generate summary report file
# ---------------------------------------------------------------------------------------------------------------------

generate_summary_report() {
    REPORT_FILE="${REPORTS_DIR}/summary-${TODAY}.md"

    cat > "$REPORT_FILE" <<EOF
# Daily Cost Report - ${TODAY}

**Report Generated:** $(date)
**Data for Date:** ${YESTERDAY}
**AWS Account:** $(aws sts get-caller-identity --query Account --output text)

---

## Summary

**Total Daily Cost:** \$$(jq -r '.ResultsByTime[0].Total.BlendedCost.Amount' "${REPORTS_DIR}/daily-cost-${TODAY}.json")

**Projected Monthly:** \$$(echo "$(jq -r '.ResultsByTime[0].Total.BlendedCost.Amount' "${REPORTS_DIR}/daily-cost-${TODAY}.json") * 30" | bc)

---

## Top 10 Services by Cost

$(jq -r '.ResultsByTime[0].Groups[] |
    select(.Metrics.BlendedCost.Amount | tonumber > 0.01) |
    "| \(.Keys[0]) | \$\(.Metrics.BlendedCost.Amount | tonumber | floor * 100 / 100) |"
' "${REPORTS_DIR}/daily-cost-${TODAY}.json" | sort -t'|' -k3 -rn | head -10 | \
awk 'BEGIN {print "| Service | Cost |"; print "|---------|------|"} {print}')

---

## Costs by Environment

$(jq -r '.ResultsByTime[0].Groups[] |
    select(.Metrics.BlendedCost.Amount | tonumber > 0.01) |
    "| \(.Keys[0] | gsub(".*\\$"; "")) | \$\(.Metrics.BlendedCost.Amount | tonumber | floor * 100 / 100) |"
' "${REPORTS_DIR}/daily-cost-by-env-${TODAY}.json" | sort -t'|' -k3 -rn | \
awk 'BEGIN {print "| Environment | Cost |"; print "|-------------|------|"} {print}')

---

## Next Steps

- Review services with unexpected increases
- Check for idle or unused resources
- Consider cost optimization opportunities
- Run monthly cost review if it's the first of the month

---

**Full data available in:**
- \`${REPORTS_DIR}/daily-cost-${TODAY}.json\`
- \`${REPORTS_DIR}/daily-cost-by-env-${TODAY}.json\`
- \`${REPORTS_DIR}/30-day-trend-${TODAY}.json\`
EOF

    echo -e "${GREEN}Summary report saved to: ${REPORT_FILE}${NC}"
    echo ""
}

# ---------------------------------------------------------------------------------------------------------------------
# Main execution
# ---------------------------------------------------------------------------------------------------------------------

main() {
    check_aws_access
    get_daily_costs
    get_costs_by_environment
    echo ""
    display_top_services
    display_environment_costs
    display_daily_total
    get_30_day_trend
    check_anomalies
    generate_summary_report

    echo "=============================================="
    echo -e "${GREEN}Daily cost report complete!${NC}"
    echo "=============================================="
}

main "$@"
