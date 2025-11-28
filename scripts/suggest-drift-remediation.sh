#!/usr/bin/env bash
# ==============================================================================
# Drift Remediation Suggestion Script
# ==============================================================================
# Purpose: Analyze drift reports and suggest appropriate remediation actions
# Author: Platform Team
# Version: 1.0.0
#
# This script analyzes drift detection output and provides specific remediation
# recommendations based on the type of drift detected.
#
# Usage:
#   ./suggest-drift-remediation.sh <drift-report-file>
#
# Arguments:
#   drift-report-file - Path to drift report JSON file
#
# Exit Codes:
#   0 - Success
#   1 - Error
# ==============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DRIFT_REPORT_FILE="${1:-}"

# ==============================================================================
# Helper Functions
# ==============================================================================

log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*" >&2
}

usage() {
    cat << EOF
Usage: $0 <drift-report-file>

Arguments:
  drift-report-file  Path to drift report JSON file

Examples:
  $0 drift-reports/non-prod-us-east-1-drift-20251029_123456.json
  $0 drift-reports/prod-us-east-1-drift-20251029_123456.json

EOF
    exit 1
}

# ==============================================================================
# Drift Analysis Functions
# ==============================================================================

# Analyze drift patterns and suggest remediation
analyze_drift() {
    local plan_output_file="$1"

    if [[ ! -f "${plan_output_file}" ]]; then
        log_error "Plan output file not found: ${plan_output_file}"
        return 1
    fi

    echo
    echo "================================================================================"
    echo "DRIFT REMEDIATION SUGGESTIONS"
    echo "================================================================================"
    echo

    # Check for common drift patterns
    check_security_group_drift "${plan_output_file}"
    check_iam_drift "${plan_output_file}"
    check_rds_drift "${plan_output_file}"
    check_ecs_drift "${plan_output_file}"
    check_autoscaling_drift "${plan_output_file}"
    check_tag_drift "${plan_output_file}"

    # Provide general remediation guidance
    provide_general_guidance

    echo
    echo "================================================================================"
}

# Check for security group drift
check_security_group_drift() {
    local plan_file="$1"

    if grep -q "aws_security_group\|aws_security_group_rule" "${plan_file}"; then
        echo "🔐 Security Group Drift Detected"
        echo "───────────────────────────────────────────────────────────────────────────"
        echo

        if grep -q "aws_security_group.*will be destroyed\|aws_security_group.*must be replaced" "${plan_file}"; then
            log_error "CRITICAL: Security group will be destroyed/replaced"
            echo
            echo "Remediation:"
            echo "  1. Identify why the security group was changed"
            echo "  2. Check AWS CloudTrail for manual changes"
            echo "  3. Review security group configuration in code"
            echo "  4. If manual changes are correct:"
            echo "     - Update Terraform code to match"
            echo "     - Run: terragrunt apply"
            echo "  5. If Terraform is correct:"
            echo "     - Apply Terraform to revert manual changes"
            echo "     - Document and communicate with team"
            echo
        elif grep -q "ingress\|egress" "${plan_file}"; then
            log_warning "Security group rules have changed"
            echo
            echo "Remediation:"
            echo "  1. Review rule changes in plan output"
            echo "  2. Check if rules were added manually in AWS console"
            echo "  3. Determine if changes are intentional or accidental"
            echo "  4. Update Terraform code if manual changes should be kept"
            echo "  5. Apply Terraform to restore original rules if unwanted"
            echo
        fi

        echo
    fi
}

# Check for IAM drift
check_iam_drift() {
    local plan_file="$1"

    if grep -q "aws_iam_role\|aws_iam_policy\|aws_iam_role_policy" "${plan_file}"; then
        echo "🔑 IAM Drift Detected"
        echo "───────────────────────────────────────────────────────────────────────────"
        echo

        log_warning "IAM resources have changed - security impact possible"
        echo
        echo "Remediation:"
        echo "  1. Check CloudTrail for IAM changes:"
        echo "     aws cloudtrail lookup-events --lookup-attributes AttributeKey=ResourceType,AttributeValue=AWS::IAM::Role --max-items 20"
        echo
        echo "  2. Review changed IAM resources in plan output"
        echo
        echo "  3. If policies were manually updated:"
        echo "     - Export current policy: aws iam get-role-policy --role-name <name> --policy-name <name>"
        echo "     - Update Terraform code to match"
        echo "     - Apply changes: terragrunt apply"
        echo
        echo "  4. If roles were modified by AWS services (e.g., ECS, Lambda):"
        echo "     - This may be expected - review service console"
        echo "     - Update Terraform lifecycle rules to ignore specific attributes"
        echo
        echo "  5. Security Review Required:"
        echo "     - Ensure least privilege is maintained"
        echo "     - Check for privilege escalation"
        echo "     - Notify security team if suspicious"
        echo
        echo
    fi
}

# Check for RDS drift
check_rds_drift() {
    local plan_file="$1"

    if grep -q "aws_db_instance\|aws_db_parameter_group" "${plan_file}"; then
        echo "🗄️  RDS Drift Detected"
        echo "───────────────────────────────────────────────────────────────────────────"
        echo

        if grep -q "aws_db_instance.*must be replaced" "${plan_file}"; then
            log_error "CRITICAL: RDS instance will be replaced - DATA LOSS RISK"
            echo
            echo "Remediation:"
            echo "  1. DO NOT APPLY without creating backup"
            echo "  2. Create manual snapshot:"
            echo "     aws rds create-db-snapshot --db-instance-identifier <name> --db-snapshot-identifier pre-drift-fix-$(date +%Y%m%d)"
            echo
            echo "  3. Review what changed:"
            echo "     - Instance class change?"
            echo "     - Engine version change?"
            echo "     - Storage type change?"
            echo
            echo "  4. Determine if replacement is necessary:"
            echo "     - Some parameters can be changed without replacement"
            echo "     - Consider using apply_immediately = false for phased changes"
            echo
            echo "  5. Plan migration window:"
            echo "     - Schedule during low-traffic period"
            echo "     - Notify team and stakeholders"
            echo "     - Test restore procedure first"
            echo
        elif grep -q "parameter_group\|backup_retention_period\|multi_az" "${plan_file}"; then
            log_warning "RDS configuration has changed"
            echo
            echo "Remediation:"
            echo "  1. Check if changes were made in RDS console"
            echo "  2. Review parameter group modifications"
            echo "  3. If manual changes are correct:"
            echo "     - Update Terraform code"
            echo "     - Apply changes during maintenance window"
            echo "  4. If Terraform is correct:"
            echo "     - Schedule apply during low-traffic window"
            echo "     - Some changes may cause instance restart"
            echo
        fi

        echo
    fi
}

# Check for ECS drift
check_ecs_drift() {
    local plan_file="$1"

    if grep -q "aws_ecs_service\|aws_ecs_task_definition" "${plan_file}"; then
        echo "🐳 ECS Drift Detected"
        echo "───────────────────────────────────────────────────────────────────────────"
        echo

        if grep -q "desired_count" "${plan_file}"; then
            log_info "ECS desired count has changed"
            echo
            echo "Remediation:"
            echo "  1. Check if count was changed for operational reasons:"
            echo "     - Auto-scaling event?"
            echo "     - Manual scaling during incident?"
            echo
            echo "  2. If manual scaling was intentional:"
            echo "     - Update desired_count in Terraform"
            echo "     - Or: Add lifecycle rule to ignore desired_count"
            echo "       lifecycle {"
            echo "         ignore_changes = [desired_count]"
            echo "       }"
            echo
            echo "  3. If using auto-scaling:"
            echo "     - This drift is expected and acceptable"
            echo "     - Add lifecycle ignore rule (recommended)"
            echo
        fi

        if grep -q "task_definition" "${plan_file}"; then
            log_warning "ECS task definition has changed"
            echo
            echo "Remediation:"
            echo "  1. Check if new deployment occurred outside Terraform"
            echo "  2. Review task definition revision:"
            echo "     aws ecs describe-task-definition --task-definition <family>:latest"
            echo
            echo "  3. If manual deployment was necessary:"
            echo "     - Update Terraform code with new configuration"
            echo "     - Apply to sync state"
            echo
        fi

        echo
    fi
}

# Check for auto-scaling drift
check_autoscaling_drift() {
    local plan_file="$1"

    if grep -q "aws_appautoscaling_target\|aws_appautoscaling_policy" "${plan_file}"; then
        echo "📈 Auto-Scaling Drift Detected"
        echo "───────────────────────────────────────────────────────────────────────────"
        echo

        log_info "Auto-scaling configuration has changed"
        echo
        echo "Remediation:"
        echo "  1. This is often acceptable drift caused by auto-scaling events"
        echo
        echo "  2. Review if scaling policies were modified manually"
        echo
        echo "  3. Recommended approach:"
        echo "     - Add lifecycle ignore rules for dynamic values"
        echo "     - Only manage baseline auto-scaling config in Terraform"
        echo "     - Allow Application Auto Scaling to manage current values"
        echo
        echo "  4. Add to resource:"
        echo "     lifecycle {"
        echo "       ignore_changes = ["
        echo "         desired_count,"
        echo "         min_capacity,"
        echo "         max_capacity"
        echo "       ]"
        echo "     }"
        echo
        echo
    fi
}

# Check for tag drift
check_tag_drift() {
    local plan_file="$1"

    if grep -q "tags" "${plan_file}" | grep -q "will be updated"; then
        echo "🏷️  Tag Drift Detected"
        echo "───────────────────────────────────────────────────────────────────────────"
        echo

        log_info "Resource tags have changed"
        echo
        echo "Remediation:"
        echo "  1. Tags are often added/modified by:"
        echo "     - AWS Cost Explorer (cost allocation tags)"
        echo "     - AWS Config (compliance tags)"
        echo "     - Third-party tools (monitoring, security)"
        echo
        echo "  2. Determine if tag changes are acceptable:"
        echo "     - Review tag changes in plan output"
        echo "     - Check who/what added tags (CloudTrail)"
        echo
        echo "  3. If tags should be in Terraform:"
        echo "     - Add to resource tags block"
        echo "     - Apply to sync state"
        echo
        echo "  4. If tags are managed externally:"
        echo "     - Add lifecycle ignore rule:"
        echo "       lifecycle {"
        echo "         ignore_changes = [tags]"
        echo "       }"
        echo
        echo
    fi
}

# Provide general remediation guidance
provide_general_guidance() {
    echo "📋 General Drift Remediation Workflow"
    echo "───────────────────────────────────────────────────────────────────────────"
    echo
    echo "Step 1: Investigate Source"
    echo "  • Check AWS CloudTrail for manual changes"
    echo "  • Review recent deployments and incidents"
    echo "  • Determine if drift is intentional or accidental"
    echo
    echo "Step 2: Classify Drift"
    echo "  • Acceptable Drift: Auto-scaling, AWS-managed changes"
    echo "  • Intentional Changes: Manual fixes during incidents"
    echo "  • Unintended Changes: Console modifications, misconfigurations"
    echo "  • Critical Drift: Security resources, data stores"
    echo
    echo "Step 3: Choose Remediation Strategy"
    echo
    echo "  Strategy A: Update Terraform (manual changes were correct)"
    echo "    1. Update Terraform code to match current state"
    echo "    2. Run: terragrunt plan (verify no destructive changes)"
    echo "    3. Run: terragrunt apply"
    echo "    4. Document why manual change was necessary"
    echo
    echo "  Strategy B: Revert Changes (Terraform is correct)"
    echo "    1. Review plan to confirm revert is safe"
    echo "    2. Backup any data if needed"
    echo "    3. Run: terragrunt apply"
    echo "    4. Notify team about reverted changes"
    echo
    echo "  Strategy C: Ignore Drift (expected behavior)"
    echo "    1. Add lifecycle ignore rule to Terraform"
    echo "    2. Document why drift is acceptable"
    echo "    3. Update drift detection to skip this resource"
    echo
    echo "Step 4: Prevent Future Drift"
    echo "  • Document proper change procedures"
    echo "  • Use AWS Config rules to detect manual changes"
    echo "  • Enable CloudTrail alerts for critical resources"
    echo "  • Schedule regular drift detection runs"
    echo "  • Restrict AWS console access for managed resources"
    echo
    echo "================================================================================"
    echo
    echo "For detailed procedures, see:"
    echo "  ${PROJECT_ROOT}/docs/SOP_DRIFT_DETECTION.md"
    echo
    echo "To apply remediation:"
    echo "  cd ${PROJECT_ROOT}/<environment>/<region>"
    echo "  terragrunt run-all plan    # Review changes"
    echo "  terragrunt run-all apply   # Apply remediation"
    echo
}

# ==============================================================================
# Main Execution
# ==============================================================================

main() {
    if [[ -z "${DRIFT_REPORT_FILE}" ]]; then
        log_error "Drift report file is required"
        usage
    fi

    if [[ ! -f "${DRIFT_REPORT_FILE}" ]]; then
        log_error "File not found: ${DRIFT_REPORT_FILE}"
        exit 1
    fi

    log_info "Analyzing drift report: ${DRIFT_REPORT_FILE}"
    echo

    # Extract plan output file from report
    if [[ "${DRIFT_REPORT_FILE}" =~ \.json$ ]]; then
        # JSON report
        PLAN_OUTPUT=$(jq -r '.plan_output_file' "${DRIFT_REPORT_FILE}" 2>/dev/null || echo "")
    else
        # Text/Markdown report - extract from content
        PLAN_OUTPUT=$(grep -oP 'plan_output_file.*:\s*\K.*' "${DRIFT_REPORT_FILE}" 2>/dev/null | head -1 || echo "")
        if [[ -z "${PLAN_OUTPUT}" ]]; then
            PLAN_OUTPUT=$(grep -oP 'Full plan output:\s*\K.*' "${DRIFT_REPORT_FILE}" 2>/dev/null | head -1 || echo "")
        fi
    fi

    if [[ -z "${PLAN_OUTPUT}" ]] || [[ ! -f "${PLAN_OUTPUT}" ]]; then
        log_error "Could not find plan output file referenced in report"
        log_error "Expected: ${PLAN_OUTPUT}"
        exit 1
    fi

    analyze_drift "${PLAN_OUTPUT}"

    log_success "Remediation analysis complete"
}

main "$@"
