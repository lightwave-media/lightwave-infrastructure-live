#!/usr/bin/env bash
# ---------------------------------------------------------------------------------------------------------------------
# COST COMPARISON - MONTHLY
# Compares current month vs last month spending with detailed breakdown
# ---------------------------------------------------------------------------------------------------------------------

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORTS_DIR="${PROJECT_ROOT}/.agent/cost-reports"

# Date calculations
CURRENT_MONTH_START=$(date +%Y-%m-01)
CURRENT_DATE=$(date +%Y-%m-%d)
LAST_MONTH_START=$(date -v-1m +%Y-%m-01 2>/dev/null || date -d "$(date +%Y-%m-01) -1 month" +%Y-%m-01)
LAST_MONTH_END=$(date -v-1d -v-0m +%Y-%m-%d 2>/dev/null || date -d "$(date +%Y-%m-01) -1 day" +%Y-%m-%d)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$REPORTS_DIR"

echo "=============================================="
echo "LightWave Media - Monthly Cost Comparison"
echo "Report Date: $CURRENT_DATE"
echo "=============================================="
echo ""
echo "Comparing:"
echo "  Current Month: $CURRENT_MONTH_START to $CURRENT_DATE (month-to-date)"
echo "  Last Month: $LAST_MONTH_START to $LAST_MONTH_END (full month)"
echo ""

# ---------------------------------------------------------------------------------------------------------------------
# Get current month costs
# ---------------------------------------------------------------------------------------------------------------------

get_current_month_costs() {
    echo -e "${BLUE}Fetching current month costs...${NC}"

    aws ce get-cost-and-usage \
        --time-period Start="${CURRENT_MONTH_START}",End="${CURRENT_DATE}" \
        --granularity MONTHLY \
        --metrics BlendedCost UnblendedCost \
        --group-by Type=SERVICE \
        --output json > "${REPORTS_DIR}/current-month-${CURRENT_DATE}.json"

    echo -e "${GREEN}Current month data saved${NC}"
}

# ---------------------------------------------------------------------------------------------------------------------
# Get last month costs
# ---------------------------------------------------------------------------------------------------------------------

get_last_month_costs() {
    echo -e "${BLUE}Fetching last month costs...${NC}"

    aws ce get-cost-and-usage \
        --time-period Start="${LAST_MONTH_START}",End="${LAST_MONTH_END}" \
        --granularity MONTHLY \
        --metrics BlendedCost UnblendedCost \
        --group-by Type=SERVICE \
        --output json > "${REPORTS_DIR}/last-month-${CURRENT_DATE}.json"

    echo -e "${GREEN}Last month data saved${NC}"
    echo ""
}

# ---------------------------------------------------------------------------------------------------------------------
# Compare service-level costs
# ---------------------------------------------------------------------------------------------------------------------

compare_service_costs() {
    echo "=============================================="
    echo "Service-Level Cost Comparison"
    echo "=============================================="
    echo ""

    # Create temporary files with service costs
    CURRENT_SERVICES=$(mktemp)
    LAST_SERVICES=$(mktemp)

    # Extract current month services
    jq -r '.ResultsByTime[0].Groups[] | "\(.Keys[0])|\(.Metrics.BlendedCost.Amount)"' \
        "${REPORTS_DIR}/current-month-${CURRENT_DATE}.json" > "$CURRENT_SERVICES"

    # Extract last month services
    jq -r '.ResultsByTime[0].Groups[] | "\(.Keys[0])|\(.Metrics.BlendedCost.Amount)"' \
        "${REPORTS_DIR}/last-month-${CURRENT_DATE}.json" > "$LAST_SERVICES"

    # Create comparison report
    {
        echo "Service|Current Month|Last Month|Change $|Change %"
        echo "-------|-------------|----------|--------|--------"

        # Join and compare
        join -t'|' -a 1 -a 2 -e "0" -o auto <(sort "$CURRENT_SERVICES") <(sort "$LAST_SERVICES") | \
        awk -F'|' '{
            service = $1
            current = ($2 != "" && $2 != "0") ? $2 : 0
            last = ($3 != "" && $3 != "0") ? $3 : 0
            change_dollar = current - last
            change_pct = (last > 0) ? ((current - last) / last * 100) : 0

            # Only show services with >$1 in either month
            if (current > 1 || last > 1) {
                printf "%s|%.2f|%.2f|%.2f|%.1f%%\n", service, current, last, change_dollar, change_pct
            }
        }' | sort -t'|' -k4 -rn
    } | column -t -s'|'

    rm "$CURRENT_SERVICES" "$LAST_SERVICES"
    echo ""
}

# ---------------------------------------------------------------------------------------------------------------------
# Compare environment costs
# ---------------------------------------------------------------------------------------------------------------------

compare_environment_costs() {
    echo "=============================================="
    echo "Environment Cost Comparison"
    echo "=============================================="
    echo ""

    # Get current month by environment
    aws ce get-cost-and-usage \
        --time-period Start="${CURRENT_MONTH_START}",End="${CURRENT_DATE}" \
        --granularity MONTHLY \
        --metrics BlendedCost \
        --group-by Type=TAG,Key=Environment \
        --output json > "${REPORTS_DIR}/current-month-env-${CURRENT_DATE}.json"

    # Get last month by environment
    aws ce get-cost-and-usage \
        --time-period Start="${LAST_MONTH_START}",End="${LAST_MONTH_END}" \
        --granularity MONTHLY \
        --metrics BlendedCost \
        --group-by Type=TAG,Key=Environment \
        --output json > "${REPORTS_DIR}/last-month-env-${CURRENT_DATE}.json"

    CURRENT_ENV=$(mktemp)
    LAST_ENV=$(mktemp)

    # Extract environment costs
    jq -r '.ResultsByTime[0].Groups[] | "\(.Keys[0] | gsub(".*\\$"; ""))|\(.Metrics.BlendedCost.Amount)"' \
        "${REPORTS_DIR}/current-month-env-${CURRENT_DATE}.json" > "$CURRENT_ENV"

    jq -r '.ResultsByTime[0].Groups[] | "\(.Keys[0] | gsub(".*\\$"; ""))|\(.Metrics.BlendedCost.Amount)"' \
        "${REPORTS_DIR}/last-month-env-${CURRENT_DATE}.json" > "$LAST_ENV"

    {
        echo "Environment|Current Month|Last Month|Change $|Change %|Budget|Status"
        echo "-----------|-------------|----------|--------|--------|------|------"

        # Define budget thresholds
        join -t'|' -a 1 -a 2 -e "0" -o auto <(sort "$CURRENT_ENV") <(sort "$LAST_ENV") | \
        awk -F'|' '{
            env = $1
            current = ($2 != "" && $2 != "0") ? $2 : 0
            last = ($3 != "" && $3 != "0") ? $3 : 0
            change_dollar = current - last
            change_pct = (last > 0) ? ((current - last) / last * 100) : 0

            # Determine budget based on environment
            budget = 0
            if (env ~ /prod/) budget = 500
            else if (env ~ /staging/) budget = 100
            else if (env ~ /dev/) budget = 50

            # Calculate status
            status = "✓ OK"
            if (budget > 0) {
                pct_of_budget = (current / budget) * 100
                if (pct_of_budget > 100) status = "✗ OVER"
                else if (pct_of_budget > 80) status = "⚠ HIGH"
            }

            if (current > 0 || last > 0) {
                printf "%s|%.2f|%.2f|%.2f|%.1f%%|%.0f|%s\n", env, current, last, change_dollar, change_pct, budget, status
            }
        }'
    } | column -t -s'|'

    rm "$CURRENT_ENV" "$LAST_ENV"
    echo ""
}

# ---------------------------------------------------------------------------------------------------------------------
# Display total comparison
# ---------------------------------------------------------------------------------------------------------------------

display_total_comparison() {
    echo "=============================================="
    echo "Total Cost Summary"
    echo "=============================================="

    CURRENT_TOTAL=$(jq -r '.ResultsByTime[0].Total.BlendedCost.Amount | tonumber' \
        "${REPORTS_DIR}/current-month-${CURRENT_DATE}.json")
    LAST_TOTAL=$(jq -r '.ResultsByTime[0].Total.BlendedCost.Amount | tonumber' \
        "${REPORTS_DIR}/last-month-${CURRENT_DATE}.json")

    CHANGE_DOLLAR=$(echo "$CURRENT_TOTAL - $LAST_TOTAL" | bc)
    CHANGE_PCT=$(echo "scale=1; ($CHANGE_DOLLAR / $LAST_TOTAL) * 100" | bc)

    echo ""
    echo "Current Month (MTD): \$${CURRENT_TOTAL}"
    echo "Last Month (Full):   \$${LAST_TOTAL}"
    echo "Change:              \$${CHANGE_DOLLAR} (${CHANGE_PCT}%)"
    echo ""

    # Projection
    CURRENT_DAY=$(date +%d | sed 's/^0//')
    DAYS_IN_MONTH=$(date -v1m -v-1d +%d 2>/dev/null || date -d "$(date +%Y-%m-01) +1 month -1 day" +%d)
    PROJECTED=$(echo "scale=2; $CURRENT_TOTAL * $DAYS_IN_MONTH / $CURRENT_DAY" | bc)

    echo "Days Elapsed:        $CURRENT_DAY / $DAYS_IN_MONTH"
    echo "Projected Month:     \$${PROJECTED}"
    echo ""

    # Alert if projection exceeds last month by >20%
    PROJECTION_INCREASE=$(echo "scale=1; ($PROJECTED - $LAST_TOTAL) / $LAST_TOTAL * 100" | bc)

    if (( $(echo "$PROJECTION_INCREASE > 20" | bc -l) )); then
        echo -e "${RED}⚠️  WARNING: Projected monthly cost is ${PROJECTION_INCREASE}% higher than last month${NC}"
        echo "Action Required: Review service-level increases above"
    elif (( $(echo "$PROJECTION_INCREASE > 10" | bc -l) )); then
        echo -e "${YELLOW}⚠️  CAUTION: Projected monthly cost is ${PROJECTION_INCREASE}% higher than last month${NC}"
    else
        echo -e "${GREEN}✓ Projected monthly cost is within normal range${NC}"
    fi

    echo ""
}

# ---------------------------------------------------------------------------------------------------------------------
# Identify top cost increases
# ---------------------------------------------------------------------------------------------------------------------

identify_top_increases() {
    echo "=============================================="
    echo "Top 5 Cost Increases (by service)"
    echo "=============================================="
    echo ""

    CURRENT_SERVICES=$(mktemp)
    LAST_SERVICES=$(mktemp)

    jq -r '.ResultsByTime[0].Groups[] | "\(.Keys[0])|\(.Metrics.BlendedCost.Amount)"' \
        "${REPORTS_DIR}/current-month-${CURRENT_DATE}.json" > "$CURRENT_SERVICES"

    jq -r '.ResultsByTime[0].Groups[] | "\(.Keys[0])|\(.Metrics.BlendedCost.Amount)"' \
        "${REPORTS_DIR}/last-month-${CURRENT_DATE}.json" > "$LAST_SERVICES"

    join -t'|' -a 1 -a 2 -e "0" -o auto <(sort "$CURRENT_SERVICES") <(sort "$LAST_SERVICES") | \
    awk -F'|' '{
        service = $1
        current = ($2 != "" && $2 != "0") ? $2 : 0
        last = ($3 != "" && $3 != "0") ? $3 : 0
        change_dollar = current - last

        if (change_dollar > 1) {
            printf "%s|%.2f|%.2f|%.2f\n", service, current, last, change_dollar
        }
    }' | sort -t'|' -k4 -rn | head -5 | \
    awk -F'|' 'BEGIN {
        printf "%-40s %12s %12s %12s\n", "Service", "Current", "Last", "Increase";
        printf "%s\n", "--------------------------------------------------------------------------------";
    }
    {
        printf "%-40s %12.2f %12.2f %12.2f\n", $1, $2, $3, $4;
    }'

    rm "$CURRENT_SERVICES" "$LAST_SERVICES"
    echo ""
}

# ---------------------------------------------------------------------------------------------------------------------
# Generate recommendations
# ---------------------------------------------------------------------------------------------------------------------

generate_recommendations() {
    echo "=============================================="
    echo "Cost Optimization Recommendations"
    echo "=============================================="
    echo ""

    CURRENT_TOTAL=$(jq -r '.ResultsByTime[0].Total.BlendedCost.Amount | tonumber' \
        "${REPORTS_DIR}/current-month-${CURRENT_DATE}.json")

    # Check RDS costs
    RDS_COST=$(jq -r '.ResultsByTime[0].Groups[] | select(.Keys[0] | contains("RDS")) | .Metrics.BlendedCost.Amount | tonumber' \
        "${REPORTS_DIR}/current-month-${CURRENT_DATE}.json" 2>/dev/null || echo "0")

    if (( $(echo "$RDS_COST > 100" | bc -l) )); then
        echo "📊 RDS Optimization:"
        echo "   - Current RDS cost: \$${RDS_COST}"
        echo "   - Consider purchasing Reserved Instances (save up to 40%)"
        echo "   - Estimated savings: \$$(echo "$RDS_COST * 0.4" | bc) per month"
        echo ""
    fi

    # Check ECS/Fargate costs
    ECS_COST=$(jq -r '.ResultsByTime[0].Groups[] | select(.Keys[0] | contains("ECS") or contains("Fargate")) | .Metrics.BlendedCost.Amount | tonumber' \
        "${REPORTS_DIR}/current-month-${CURRENT_DATE}.json" 2>/dev/null || echo "0")

    if (( $(echo "$ECS_COST > 150" | bc -l) )); then
        echo "🚀 ECS/Fargate Optimization:"
        echo "   - Current ECS cost: \$${ECS_COST}"
        echo "   - Consider Compute Savings Plans (save up to 50%)"
        echo "   - Estimated savings: \$$(echo "$ECS_COST * 0.5" | bc) per month"
        echo ""
    fi

    # Check data transfer costs
    TRANSFER_COST=$(jq -r '.ResultsByTime[0].Groups[] | select(.Keys[0] | contains("Data Transfer") or contains("CloudFront")) | .Metrics.BlendedCost.Amount | tonumber' \
        "${REPORTS_DIR}/current-month-${CURRENT_DATE}.json" 2>/dev/null || echo "0")

    if (( $(echo "$TRANSFER_COST > 50" | bc -l) )); then
        echo "🌐 Data Transfer Optimization:"
        echo "   - Current transfer cost: \$${TRANSFER_COST}"
        echo "   - Consider enabling CloudFront caching"
        echo "   - Review S3 lifecycle policies"
        echo ""
    fi

    # General recommendations
    echo "💡 General Recommendations:"
    echo "   - Run idle resource cleanup: ./scripts/check-idle-resources.sh"
    echo "   - Review Reserved Instance coverage in Cost Explorer"
    echo "   - Enable S3 Intelligent Tiering for media storage"
    echo "   - Consider spot instances for non-prod ECS tasks"
    echo ""
}

# ---------------------------------------------------------------------------------------------------------------------
# Generate markdown report
# ---------------------------------------------------------------------------------------------------------------------

generate_markdown_report() {
    REPORT_FILE="${REPORTS_DIR}/monthly-comparison-${CURRENT_DATE}.md"

    CURRENT_TOTAL=$(jq -r '.ResultsByTime[0].Total.BlendedCost.Amount | tonumber' \
        "${REPORTS_DIR}/current-month-${CURRENT_DATE}.json")
    LAST_TOTAL=$(jq -r '.ResultsByTime[0].Total.BlendedCost.Amount | tonumber' \
        "${REPORTS_DIR}/last-month-${CURRENT_DATE}.json")

    CHANGE_DOLLAR=$(echo "$CURRENT_TOTAL - $LAST_TOTAL" | bc)
    CHANGE_PCT=$(echo "scale=1; ($CHANGE_DOLLAR / $LAST_TOTAL) * 100" | bc)

    cat > "$REPORT_FILE" <<EOF
# Monthly Cost Comparison Report

**Generated:** $(date)
**Current Month:** ${CURRENT_MONTH_START} to ${CURRENT_DATE} (MTD)
**Last Month:** ${LAST_MONTH_START} to ${LAST_MONTH_END} (Full)

---

## Executive Summary

| Metric | Amount |
|--------|--------|
| Current Month (MTD) | \$${CURRENT_TOTAL} |
| Last Month (Full) | \$${LAST_TOTAL} |
| Change | \$${CHANGE_DOLLAR} (${CHANGE_PCT}%) |

---

## Top Services by Cost

### Current Month
$(jq -r '.ResultsByTime[0].Groups[] | select(.Metrics.BlendedCost.Amount | tonumber > 1) |
"| \(.Keys[0]) | \$\(.Metrics.BlendedCost.Amount | tonumber | . * 100 | floor / 100) |"' \
"${REPORTS_DIR}/current-month-${CURRENT_DATE}.json" | sort -t'$' -k2 -rn | head -10 | \
awk 'BEGIN {print "| Service | Cost |"; print "|---------|------|"} {print}')

---

## Environment Breakdown

$(jq -r '.ResultsByTime[0].Groups[] |
"| \(.Keys[0] | gsub(".*\\$"; "")) | \$\(.Metrics.BlendedCost.Amount | tonumber | . * 100 | floor / 100) |"' \
"${REPORTS_DIR}/current-month-env-${CURRENT_DATE}.json" | \
awk 'BEGIN {print "| Environment | Current Month Cost |"; print "|-------------|-------------------|"} {print}')

---

## Recommendations

See full recommendations in the cost optimization section above.

---

**Next Steps:**
1. Review services with >20% increase
2. Check for idle or unused resources
3. Consider Reserved Instances or Savings Plans
4. Run monthly cost review meeting

EOF

    echo -e "${GREEN}Markdown report saved to: ${REPORT_FILE}${NC}"
    echo ""
}

# ---------------------------------------------------------------------------------------------------------------------
# Main execution
# ---------------------------------------------------------------------------------------------------------------------

main() {
    get_current_month_costs
    get_last_month_costs
    echo ""
    compare_service_costs
    compare_environment_costs
    display_total_comparison
    identify_top_increases
    generate_recommendations
    generate_markdown_report

    echo "=============================================="
    echo -e "${GREEN}Monthly cost comparison complete!${NC}"
    echo "=============================================="
}

main "$@"
