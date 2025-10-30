#!/usr/bin/env bash
# ---------------------------------------------------------------------------------------------------------------------
# CHECK IDLE RESOURCES
# Identifies unused AWS resources that are generating costs
# ---------------------------------------------------------------------------------------------------------------------

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORTS_DIR="${PROJECT_ROOT}/.agent/cost-reports"
TODAY=$(date +%Y-%m-%d)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$REPORTS_DIR"

echo "=============================================="
echo "LightWave Media - Idle Resource Check"
echo "Report Date: $TODAY"
echo "=============================================="
echo ""

TOTAL_POTENTIAL_SAVINGS=0

# ---------------------------------------------------------------------------------------------------------------------
# Check for unattached EBS volumes
# ---------------------------------------------------------------------------------------------------------------------

check_unattached_volumes() {
    echo -e "${BLUE}Checking for unattached EBS volumes...${NC}"

    VOLUMES=$(aws ec2 describe-volumes \
        --filters Name=status,Values=available \
        --query 'Volumes[*].[VolumeId,Size,CreateTime,VolumeType]' \
        --output json)

    VOLUME_COUNT=$(echo "$VOLUMES" | jq '. | length')

    if [ "$VOLUME_COUNT" -eq 0 ]; then
        echo -e "${GREEN}✓ No unattached EBS volumes found${NC}"
    else
        echo -e "${YELLOW}⚠️  Found ${VOLUME_COUNT} unattached EBS volumes:${NC}"
        echo ""

        echo "$VOLUMES" | jq -r '.[] | @tsv' | \
        awk 'BEGIN {
            printf "%-22s %8s %20s %12s %8s\n", "Volume ID", "Size GB", "Created", "Type", "Cost/Mo";
            printf "%s\n", "--------------------------------------------------------------------------------";
            total = 0;
        }
        {
            # Cost per GB-month for different volume types
            cost_per_gb = 0.10  # gp3/gp2 default
            if ($4 == "io1" || $4 == "io2") cost_per_gb = 0.125
            if ($4 == "st1") cost_per_gb = 0.045
            if ($4 == "sc1") cost_per_gb = 0.015

            monthly_cost = $2 * cost_per_gb
            total += monthly_cost

            printf "%-22s %8d %20s %12s $%7.2f\n", $1, $2, $3, $4, monthly_cost
        }
        END {
            printf "%s\n", "--------------------------------------------------------------------------------";
            printf "%-22s %8s %20s %12s $%7.2f\n", "TOTAL", "", "", "", total;
        }' | tee -a "${REPORTS_DIR}/idle-resources-${TODAY}.txt"

        VOLUME_SAVINGS=$(echo "$VOLUMES" | jq -r '
            [.[] | (.[1] * 0.10)] | add
        ')
        TOTAL_POTENTIAL_SAVINGS=$(echo "$TOTAL_POTENTIAL_SAVINGS + $VOLUME_SAVINGS" | bc)

        echo ""
        echo "To delete unattached volumes:"
        echo "  aws ec2 delete-volume --volume-id <volume-id>"
    fi

    echo ""
}

# ---------------------------------------------------------------------------------------------------------------------
# Check for old EBS snapshots
# ---------------------------------------------------------------------------------------------------------------------

check_old_snapshots() {
    echo -e "${BLUE}Checking for old EBS snapshots (>90 days)...${NC}"

    NINETY_DAYS_AGO=$(date -v-90d +%Y-%m-%d 2>/dev/null || date -d '90 days ago' +%Y-%m-%d)

    SNAPSHOTS=$(aws ec2 describe-snapshots \
        --owner-ids self \
        --query "Snapshots[?StartTime<='${NINETY_DAYS_AGO}'].[SnapshotId,VolumeSize,StartTime,Description]" \
        --output json)

    SNAPSHOT_COUNT=$(echo "$SNAPSHOTS" | jq '. | length')

    if [ "$SNAPSHOT_COUNT" -eq 0 ]; then
        echo -e "${GREEN}✓ No old snapshots found (>90 days)${NC}"
    else
        echo -e "${YELLOW}⚠️  Found ${SNAPSHOT_COUNT} old snapshots (>90 days):${NC}"
        echo ""

        echo "$SNAPSHOTS" | jq -r '.[] | @tsv' | head -20 | \
        awk 'BEGIN {
            printf "%-24s %8s %20s %8s\n", "Snapshot ID", "Size GB", "Created", "Cost/Mo";
            printf "%s\n", "------------------------------------------------------------------------";
            total = 0;
        }
        {
            cost = $2 * 0.05
            total += cost
            desc = $4
            if (length(desc) > 30) desc = substr(desc, 1, 27) "..."

            printf "%-24s %8d %20s $%7.2f\n", $1, $2, $3, cost
        }
        END {
            printf "%s\n", "------------------------------------------------------------------------";
            printf "%-24s %8s %20s $%7.2f\n", "TOTAL (first 20)", "", "", total;
        }' | tee -a "${REPORTS_DIR}/idle-resources-${TODAY}.txt"

        SNAPSHOT_SAVINGS=$(echo "$SNAPSHOTS" | jq -r '[.[] | (.[1] * 0.05)] | add')
        TOTAL_POTENTIAL_SAVINGS=$(echo "$TOTAL_POTENTIAL_SAVINGS + $SNAPSHOT_SAVINGS" | bc)

        echo ""
        echo "Review and delete old snapshots manually after verification."
        echo "NOTE: Do not delete snapshots needed for disaster recovery!"
    fi

    echo ""
}

# ---------------------------------------------------------------------------------------------------------------------
# Check for unused Elastic IPs
# ---------------------------------------------------------------------------------------------------------------------

check_unused_elastic_ips() {
    echo -e "${BLUE}Checking for unassociated Elastic IPs...${NC}"

    EIPS=$(aws ec2 describe-addresses \
        --query 'Addresses[?AssociationId==`null`].[PublicIp,AllocationId]' \
        --output json)

    EIP_COUNT=$(echo "$EIPS" | jq '. | length')

    if [ "$EIP_COUNT" -eq 0 ]; then
        echo -e "${GREEN}✓ No unassociated Elastic IPs found${NC}"
    else
        echo -e "${YELLOW}⚠️  Found ${EIP_COUNT} unassociated Elastic IPs:${NC}"
        echo ""

        echo "$EIPS" | jq -r '.[] | @tsv' | \
        awk 'BEGIN {
            printf "%-18s %-26s %10s\n", "Public IP", "Allocation ID", "Cost/Mo";
            printf "%s\n", "------------------------------------------------------------";
        }
        {
            printf "%-18s %-26s %10s\n", $1, $2, "$3.60"
        }
        END {
            printf "%s\n", "------------------------------------------------------------";
            printf "%-18s %-26s $%9.2f\n", "TOTAL", "", NR * 3.60
        }' | tee -a "${REPORTS_DIR}/idle-resources-${TODAY}.txt"

        EIP_SAVINGS=$(echo "$EIP_COUNT * 3.60" | bc)
        TOTAL_POTENTIAL_SAVINGS=$(echo "$TOTAL_POTENTIAL_SAVINGS + $EIP_SAVINGS" | bc)

        echo ""
        echo "To release Elastic IPs:"
        echo "  aws ec2 release-address --allocation-id <allocation-id>"
    fi

    echo ""
}

# ---------------------------------------------------------------------------------------------------------------------
# Check for stopped RDS instances
# ---------------------------------------------------------------------------------------------------------------------

check_stopped_rds() {
    echo -e "${BLUE}Checking for stopped RDS instances...${NC}"

    STOPPED_DBS=$(aws rds describe-db-instances \
        --query 'DBInstances[?DBInstanceStatus==`stopped`].[DBInstanceIdentifier,DBInstanceClass,AllocatedStorage,Engine]' \
        --output json)

    DB_COUNT=$(echo "$STOPPED_DBS" | jq '. | length')

    if [ "$DB_COUNT" -eq 0 ]; then
        echo -e "${GREEN}✓ No stopped RDS instances found${NC}"
    else
        echo -e "${YELLOW}⚠️  Found ${DB_COUNT} stopped RDS instances:${NC}"
        echo "   NOTE: Stopped RDS instances still incur storage costs!"
        echo ""

        echo "$STOPPED_DBS" | jq -r '.[] | @tsv' | \
        awk 'BEGIN {
            printf "%-30s %-18s %10s %-10s %10s\n", "DB Instance", "Class", "Storage GB", "Engine", "Est Cost/Mo";
            printf "%s\n", "------------------------------------------------------------------------------------";
        }
        {
            # Rough storage cost estimate
            storage_cost = $3 * 0.115  # gp2 storage
            printf "%-30s %-18s %10d %-10s $%9.2f\n", $1, $2, $3, $4, storage_cost
        }' | tee -a "${REPORTS_DIR}/idle-resources-${TODAY}.txt"

        echo ""
        echo "Consider terminating stopped instances if not needed."
        echo "To start: aws rds start-db-instance --db-instance-identifier <id>"
        echo "To delete: aws rds delete-db-instance --db-instance-identifier <id>"
    fi

    echo ""
}

# ---------------------------------------------------------------------------------------------------------------------
# Check for idle Load Balancers
# ---------------------------------------------------------------------------------------------------------------------

check_idle_load_balancers() {
    echo -e "${BLUE}Checking for load balancers with no targets...${NC}"

    LBS=$(aws elbv2 describe-load-balancers \
        --query 'LoadBalancers[*].[LoadBalancerName,LoadBalancerArn,Type]' \
        --output json)

    IDLE_LBS=()

    echo "$LBS" | jq -c '.[]' | while IFS= read -r lb; do
        LB_NAME=$(echo "$lb" | jq -r '.[0]')
        LB_ARN=$(echo "$lb" | jq -r '.[1]')
        LB_TYPE=$(echo "$lb" | jq -r '.[2]')

        # Get target groups for this LB
        TGS=$(aws elbv2 describe-target-groups \
            --load-balancer-arn "$LB_ARN" \
            --query 'TargetGroups[*].TargetGroupArn' \
            --output json 2>/dev/null || echo "[]")

        # Check if any target group has healthy targets
        HAS_TARGETS=false
        echo "$TGS" | jq -r '.[]' | while read -r tg; do
            HEALTH=$(aws elbv2 describe-target-health \
                --target-group-arn "$tg" \
                --query 'TargetHealthDescriptions[*].TargetHealth.State' \
                --output json 2>/dev/null || echo "[]")

            if [ "$(echo "$HEALTH" | jq '. | length')" -gt 0 ]; then
                HAS_TARGETS=true
                break
            fi
        done

        if [ "$HAS_TARGETS" = false ]; then
            IDLE_LBS+=("$LB_NAME|$LB_TYPE")
        fi
    done

    if [ ${#IDLE_LBS[@]} -eq 0 ]; then
        echo -e "${GREEN}✓ All load balancers have targets${NC}"
    else
        echo -e "${YELLOW}⚠️  Found ${#IDLE_LBS[@]} load balancers with no targets:${NC}"
        echo ""

        printf "%-50s %-15s %10s\n" "Load Balancer" "Type" "Cost/Mo"
        printf "%s\n" "--------------------------------------------------------------------------------"

        for lb_info in "${IDLE_LBS[@]}"; do
            IFS='|' read -r name type <<< "$lb_info"
            cost=16.00
            if [ "$type" = "network" ]; then
                cost=22.00
            fi

            printf "%-50s %-15s $%9.2f\n" "$name" "$type" "$cost"
            TOTAL_POTENTIAL_SAVINGS=$(echo "$TOTAL_POTENTIAL_SAVINGS + $cost" | bc)
        done

        echo ""
        echo "To delete idle load balancers:"
        echo "  aws elbv2 delete-load-balancer --load-balancer-arn <arn>"
    fi

    echo ""
}

# ---------------------------------------------------------------------------------------------------------------------
# Check for underutilized RDS instances
# ---------------------------------------------------------------------------------------------------------------------

check_rds_utilization() {
    echo -e "${BLUE}Checking RDS CPU utilization (last 7 days)...${NC}"

    DBS=$(aws rds describe-db-instances \
        --query 'DBInstances[?DBInstanceStatus==`available`].DBInstanceIdentifier' \
        --output json)

    LOW_UTIL_COUNT=0

    echo "$DBS" | jq -r '.[]' | while read -r db; do
        # Get average CPU for last 7 days
        AVG_CPU=$(aws cloudwatch get-metric-statistics \
            --namespace AWS/RDS \
            --metric-name CPUUtilization \
            --dimensions Name=DBInstanceIdentifier,Value="$db" \
            --start-time "$(date -u -v-7d +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S)" \
            --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
            --period 86400 \
            --statistics Average \
            --query 'Datapoints[*].Average' \
            --output json 2>/dev/null | jq -r 'add / length // 0')

        if (( $(echo "$AVG_CPU < 20" | bc -l) )); then
            echo -e "${YELLOW}⚠️  $db: Average CPU ${AVG_CPU}% (consider downsizing)${NC}"
            LOW_UTIL_COUNT=$((LOW_UTIL_COUNT + 1))
        fi
    done

    if [ "$LOW_UTIL_COUNT" -eq 0 ]; then
        echo -e "${GREEN}✓ All RDS instances show normal utilization${NC}"
    else
        echo ""
        echo "Consider downsizing RDS instances with consistently low CPU (<20%)"
    fi

    echo ""
}

# ---------------------------------------------------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------------------------------------------------

display_summary() {
    echo "=============================================="
    echo "Idle Resource Summary"
    echo "=============================================="
    echo ""
    echo -e "Total Potential Monthly Savings: ${GREEN}\$$(printf "%.2f" "$TOTAL_POTENTIAL_SAVINGS")${NC}"
    echo ""
    echo "Next Steps:"
    echo "1. Review idle resources identified above"
    echo "2. Verify resources are truly unused (check with team)"
    echo "3. Delete or terminate unused resources"
    echo "4. Consider downsizing underutilized resources"
    echo "5. Set up CloudWatch alarms for idle resources"
    echo ""
    echo "Full report saved to: ${REPORTS_DIR}/idle-resources-${TODAY}.txt"
    echo ""
}

# ---------------------------------------------------------------------------------------------------------------------
# Main execution
# ---------------------------------------------------------------------------------------------------------------------

main() {
    check_unattached_volumes
    check_old_snapshots
    check_unused_elastic_ips
    check_stopped_rds
    check_idle_load_balancers
    check_rds_utilization
    display_summary

    echo "=============================================="
    echo -e "${GREEN}Idle resource check complete!${NC}"
    echo "=============================================="
}

main "$@"
