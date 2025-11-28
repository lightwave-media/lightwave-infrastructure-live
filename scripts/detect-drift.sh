#!/usr/bin/env bash
# ==============================================================================
# Drift Detection Script
# ==============================================================================
# Purpose: Detect configuration drift between Terraform state and live AWS resources
# Author: Platform Team
# Version: 1.0.0
#
# This script runs terragrunt plan to detect drift and analyzes the output
# to provide detailed resource-level drift information.
#
# Usage:
#   ./detect-drift.sh <environment> [region] [output-format]
#
# Arguments:
#   environment    - Target environment (non-prod, prod)
#   region        - AWS region (default: us-east-1)
#   output-format - Output format: json, markdown, or text (default: text)
#
# Environment Variables:
#   AWS_PROFILE         - AWS profile to use (default: lightwave-admin-new)
#   DRIFT_OUTPUT_DIR    - Directory to save drift reports (default: ./drift-reports)
#   SLACK_WEBHOOK_URL   - Optional: Slack webhook for notifications
#
# Exit Codes:
#   0 - No drift detected
#   1 - Error running detection
#   2 - Drift detected (acceptable drift)
#   3 - Critical drift detected (requires immediate attention)
# ==============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Parse arguments
ENVIRONMENT="${1:-}"
REGION="${2:-us-east-1}"
OUTPUT_FORMAT="${3:-text}"

# Set defaults
export AWS_PROFILE="${AWS_PROFILE:-lightwave-admin-new}"
DRIFT_OUTPUT_DIR="${DRIFT_OUTPUT_DIR:-${PROJECT_ROOT}/drift-reports}"
PLAN_OUTPUT_FILE="${DRIFT_OUTPUT_DIR}/${ENVIRONMENT}-${REGION}-plan-${TIMESTAMP}.txt"
DRIFT_REPORT_FILE="${DRIFT_OUTPUT_DIR}/${ENVIRONMENT}-${REGION}-drift-${TIMESTAMP}.${OUTPUT_FORMAT}"

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
Usage: $0 <environment> [region] [output-format]

Arguments:
  environment    Target environment (non-prod, prod)
  region        AWS region (default: us-east-1)
  output-format Output format: json, markdown, text (default: text)

Environment Variables:
  AWS_PROFILE         AWS profile (default: lightwave-admin-new)
  DRIFT_OUTPUT_DIR    Output directory (default: ./drift-reports)
  SLACK_WEBHOOK_URL   Slack webhook for notifications (optional)

Examples:
  $0 non-prod
  $0 prod us-east-1 json
  $0 non-prod us-east-1 markdown

Exit Codes:
  0 - No drift detected
  1 - Error running detection
  2 - Drift detected (acceptable)
  3 - Critical drift detected

EOF
    exit 1
}

# Validate arguments
validate_args() {
    if [[ -z "${ENVIRONMENT}" ]]; then
        log_error "Environment is required"
        usage
    fi

    if [[ ! "${ENVIRONMENT}" =~ ^(non-prod|prod)$ ]]; then
        log_error "Invalid environment: ${ENVIRONMENT}"
        log_error "Must be 'non-prod' or 'prod'"
        exit 1
    fi

    if [[ ! "${OUTPUT_FORMAT}" =~ ^(json|markdown|text)$ ]]; then
        log_error "Invalid output format: ${OUTPUT_FORMAT}"
        log_error "Must be 'json', 'markdown', or 'text'"
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check terragrunt
    if ! command -v terragrunt &> /dev/null; then
        log_error "terragrunt is not installed"
        exit 1
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity --profile "${AWS_PROFILE}" &> /dev/null; then
        log_error "AWS credentials not configured for profile: ${AWS_PROFILE}"
        exit 1
    fi

    # Check environment directory exists
    if [[ ! -d "${PROJECT_ROOT}/${ENVIRONMENT}/${REGION}" ]]; then
        log_error "Environment directory not found: ${PROJECT_ROOT}/${ENVIRONMENT}/${REGION}"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Create output directory
setup_output_dir() {
    mkdir -p "${DRIFT_OUTPUT_DIR}"
    log_info "Drift reports will be saved to: ${DRIFT_OUTPUT_DIR}"
}

# Run terragrunt plan to detect drift
run_drift_detection() {
    log_info "Running drift detection for ${ENVIRONMENT}/${REGION}..."

    cd "${PROJECT_ROOT}/${ENVIRONMENT}/${REGION}"

    # Run terragrunt plan and capture output
    set +e
    terragrunt run-all plan \
        --terragrunt-non-interactive \
        --detailed-exitcode \
        2>&1 | tee "${PLAN_OUTPUT_FILE}"

    PLAN_EXIT_CODE=$?
    set -e

    # terragrunt exit codes:
    # 0 = no changes
    # 1 = error
    # 2 = changes detected

    if [[ ${PLAN_EXIT_CODE} -eq 0 ]]; then
        log_success "No drift detected"
        return 0
    elif [[ ${PLAN_EXIT_CODE} -eq 1 ]]; then
        log_error "Error running terragrunt plan"
        return 1
    elif [[ ${PLAN_EXIT_CODE} -eq 2 ]]; then
        log_warning "Drift detected - changes found"
        return 2
    else
        log_error "Unexpected exit code: ${PLAN_EXIT_CODE}"
        return 1
    fi
}

# Parse plan output to extract drift details
parse_drift() {
    log_info "Analyzing drift..."

    # Extract resource changes
    RESOURCES_TO_ADD=$(grep -c "will be created" "${PLAN_OUTPUT_FILE}" 2>/dev/null || echo 0)
    RESOURCES_TO_CHANGE=$(grep -c "will be updated in-place" "${PLAN_OUTPUT_FILE}" 2>/dev/null || echo 0)
    RESOURCES_TO_DESTROY=$(grep -c "will be destroyed" "${PLAN_OUTPUT_FILE}" 2>/dev/null || echo 0)
    RESOURCES_TO_REPLACE=$(grep -c "must be replaced" "${PLAN_OUTPUT_FILE}" 2>/dev/null || echo 0)

    # Calculate total drift
    TOTAL_DRIFT=$((RESOURCES_TO_ADD + RESOURCES_TO_CHANGE + RESOURCES_TO_DESTROY + RESOURCES_TO_REPLACE))

    # Classify drift severity
    DRIFT_SEVERITY="none"
    if [[ ${TOTAL_DRIFT} -gt 0 ]]; then
        DRIFT_SEVERITY="acceptable"
    fi

    # Check for critical drift patterns
    if grep -q "aws_security_group\|aws_iam_role\|aws_iam_policy" "${PLAN_OUTPUT_FILE}" | grep -q "will be destroyed\|must be replaced"; then
        DRIFT_SEVERITY="critical"
        log_error "Critical drift detected: Security-related resources affected"
    fi

    if [[ ${RESOURCES_TO_DESTROY} -gt 0 ]] || [[ ${RESOURCES_TO_REPLACE} -gt 0 ]]; then
        if [[ ${DRIFT_SEVERITY} != "critical" ]]; then
            DRIFT_SEVERITY="high"
        fi
        log_warning "High severity drift: Resources will be destroyed or replaced"
    fi

    export RESOURCES_TO_ADD RESOURCES_TO_CHANGE RESOURCES_TO_DESTROY RESOURCES_TO_REPLACE
    export TOTAL_DRIFT DRIFT_SEVERITY
}

# Extract detailed drift information
extract_drift_details() {
    # Extract changed resources with context
    grep -B 2 -A 5 "will be created\|will be updated\|will be destroyed\|must be replaced" "${PLAN_OUTPUT_FILE}" > "${DRIFT_OUTPUT_DIR}/drift-details-${TIMESTAMP}.txt" 2>/dev/null || true
}

# Generate drift report in specified format
generate_report() {
    log_info "Generating drift report (${OUTPUT_FORMAT})..."

    case "${OUTPUT_FORMAT}" in
        json)
            generate_json_report
            ;;
        markdown)
            generate_markdown_report
            ;;
        text)
            generate_text_report
            ;;
    esac

    log_success "Report saved to: ${DRIFT_REPORT_FILE}"
}

# Generate JSON report
generate_json_report() {
    cat > "${DRIFT_REPORT_FILE}" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "environment": "${ENVIRONMENT}",
  "region": "${REGION}",
  "drift_detected": $([ ${TOTAL_DRIFT} -gt 0 ] && echo "true" || echo "false"),
  "drift_severity": "${DRIFT_SEVERITY}",
  "summary": {
    "resources_to_add": ${RESOURCES_TO_ADD},
    "resources_to_change": ${RESOURCES_TO_CHANGE},
    "resources_to_destroy": ${RESOURCES_TO_DESTROY},
    "resources_to_replace": ${RESOURCES_TO_REPLACE},
    "total_changes": ${TOTAL_DRIFT}
  },
  "plan_output_file": "${PLAN_OUTPUT_FILE}",
  "detected_by": "$(whoami)",
  "aws_account": "$(aws sts get-caller-identity --profile ${AWS_PROFILE} --query Account --output text 2>/dev/null || echo 'unknown')"
}
EOF
}

# Generate Markdown report
generate_markdown_report() {
    cat > "${DRIFT_REPORT_FILE}" << EOF
# Infrastructure Drift Report

## Summary

- **Environment:** ${ENVIRONMENT}
- **Region:** ${REGION}
- **Timestamp:** $(date -u +%Y-%m-%d\ %H:%M:%S\ UTC)
- **Drift Detected:** $([ ${TOTAL_DRIFT} -gt 0 ] && echo "Yes ⚠️" || echo "No ✅")
- **Severity:** ${DRIFT_SEVERITY^^}

## Resource Changes

| Change Type | Count |
|------------|-------|
| Resources to Add | ${RESOURCES_TO_ADD} |
| Resources to Update | ${RESOURCES_TO_CHANGE} |
| Resources to Destroy | ${RESOURCES_TO_DESTROY} |
| Resources to Replace | ${RESOURCES_TO_REPLACE} |
| **Total Changes** | **${TOTAL_DRIFT}** |

## Severity Classification

$(
if [[ "${DRIFT_SEVERITY}" == "critical" ]]; then
    echo "🚨 **CRITICAL** - Security-related resources affected. Immediate action required."
elif [[ "${DRIFT_SEVERITY}" == "high" ]]; then
    echo "⚠️ **HIGH** - Resources will be destroyed or replaced. Review carefully."
elif [[ "${DRIFT_SEVERITY}" == "acceptable" ]]; then
    echo "ℹ️ **ACCEPTABLE** - Minor configuration changes detected."
else
    echo "✅ **NONE** - No drift detected."
fi
)

## Recommended Actions

$(
if [[ ${TOTAL_DRIFT} -gt 0 ]]; then
    cat << ACTIONS
1. Review the detailed plan output: \`${PLAN_OUTPUT_FILE}\`
2. Investigate the source of changes (manual AWS console changes?)
3. Determine if drift is acceptable or needs remediation
4. Follow drift resolution procedures in SOP_DRIFT_DETECTION.md
ACTIONS
else
    echo "No action required - infrastructure is in sync with Terraform state."
fi
)

## Details

For full plan output, see: \`${PLAN_OUTPUT_FILE}\`

---

*Generated by drift detection automation*
*Detected by: $(whoami)*
*AWS Account: $(aws sts get-caller-identity --profile ${AWS_PROFILE} --query Account --output text 2>/dev/null || echo 'unknown')*
EOF
}

# Generate text report
generate_text_report() {
    cat > "${DRIFT_REPORT_FILE}" << EOF
================================================================================
INFRASTRUCTURE DRIFT REPORT
================================================================================

Environment:     ${ENVIRONMENT}
Region:          ${REGION}
Timestamp:       $(date -u +%Y-%m-%d\ %H:%M:%S\ UTC)
Drift Detected:  $([ ${TOTAL_DRIFT} -gt 0 ] && echo "Yes" || echo "No")
Severity:        ${DRIFT_SEVERITY^^}

================================================================================
RESOURCE CHANGES
================================================================================

Resources to Add:       ${RESOURCES_TO_ADD}
Resources to Update:    ${RESOURCES_TO_CHANGE}
Resources to Destroy:   ${RESOURCES_TO_DESTROY}
Resources to Replace:   ${RESOURCES_TO_REPLACE}
---
Total Changes:          ${TOTAL_DRIFT}

================================================================================
SEVERITY CLASSIFICATION
================================================================================

$(
if [[ "${DRIFT_SEVERITY}" == "critical" ]]; then
    echo "CRITICAL - Security-related resources affected. Immediate action required."
elif [[ "${DRIFT_SEVERITY}" == "high" ]]; then
    echo "HIGH - Resources will be destroyed or replaced. Review carefully."
elif [[ "${DRIFT_SEVERITY}" == "acceptable" ]]; then
    echo "ACCEPTABLE - Minor configuration changes detected."
else
    echo "NONE - No drift detected."
fi
)

================================================================================
RECOMMENDED ACTIONS
================================================================================

$(
if [[ ${TOTAL_DRIFT} -gt 0 ]]; then
    cat << ACTIONS
1. Review the detailed plan output: ${PLAN_OUTPUT_FILE}
2. Investigate the source of changes (manual AWS console changes?)
3. Determine if drift is acceptable or needs remediation
4. Follow drift resolution procedures in SOP_DRIFT_DETECTION.md
ACTIONS
else
    echo "No action required - infrastructure is in sync with Terraform state."
fi
)

================================================================================
DETAILS
================================================================================

Full plan output: ${PLAN_OUTPUT_FILE}
Detected by: $(whoami)
AWS Account: $(aws sts get-caller-identity --profile ${AWS_PROFILE} --query Account --output text 2>/dev/null || echo 'unknown')

================================================================================
EOF
}

# Send Slack notification if webhook is configured
send_slack_notification() {
    if [[ -z "${SLACK_WEBHOOK_URL:-}" ]]; then
        log_info "Skipping Slack notification (SLACK_WEBHOOK_URL not set)"
        return 0
    fi

    if [[ ${TOTAL_DRIFT} -eq 0 ]]; then
        # Don't spam Slack if no drift
        return 0
    fi

    log_info "Sending Slack notification..."

    local emoji="⚠️"
    local color="warning"

    if [[ "${DRIFT_SEVERITY}" == "critical" ]]; then
        emoji="🚨"
        color="danger"
    elif [[ "${DRIFT_SEVERITY}" == "high" ]]; then
        emoji="⚠️"
        color="warning"
    else
        emoji="ℹ️"
        color="good"
    fi

    local payload=$(cat << JSON
{
  "text": "${emoji} Infrastructure Drift Detected",
  "attachments": [
    {
      "color": "${color}",
      "fields": [
        {
          "title": "Environment",
          "value": "${ENVIRONMENT}",
          "short": true
        },
        {
          "title": "Severity",
          "value": "${DRIFT_SEVERITY^^}",
          "short": true
        },
        {
          "title": "Total Changes",
          "value": "${TOTAL_DRIFT}",
          "short": true
        },
        {
          "title": "Timestamp",
          "value": "$(date -u +%Y-%m-%d\ %H:%M:%S\ UTC)",
          "short": true
        }
      ],
      "footer": "Drift Detection | ${REGION}"
    }
  ]
}
JSON
)

    curl -X POST -H 'Content-type: application/json' \
        --data "${payload}" \
        "${SLACK_WEBHOOK_URL}" \
        2>/dev/null || log_warning "Failed to send Slack notification"
}

# Determine exit code based on drift severity
determine_exit_code() {
    case "${DRIFT_SEVERITY}" in
        none)
            return 0
            ;;
        acceptable)
            return 2
            ;;
        high)
            return 2
            ;;
        critical)
            return 3
            ;;
        *)
            return 1
            ;;
    esac
}

# ==============================================================================
# Main Execution
# ==============================================================================

main() {
    log_info "LightWave Infrastructure Drift Detection"
    log_info "========================================"
    echo

    validate_args
    check_prerequisites
    setup_output_dir

    # Run detection
    DRIFT_EXIT_CODE=0
    if ! run_drift_detection; then
        DRIFT_EXIT_CODE=$?
    fi

    # Only parse and report if plan ran successfully
    if [[ ${DRIFT_EXIT_CODE} -ne 1 ]]; then
        parse_drift
        extract_drift_details
        generate_report
        send_slack_notification

        # Print summary
        echo
        log_info "Drift Detection Summary:"
        log_info "  Environment: ${ENVIRONMENT}"
        log_info "  Total changes: ${TOTAL_DRIFT}"
        log_info "  Severity: ${DRIFT_SEVERITY^^}"
        echo

        if [[ ${TOTAL_DRIFT} -gt 0 ]]; then
            log_warning "Drift detected! Review the report: ${DRIFT_REPORT_FILE}"
        else
            log_success "No drift detected - infrastructure in sync"
        fi

        determine_exit_code
    else
        log_error "Drift detection failed"
        exit 1
    fi
}

# Run main function
main "$@"
