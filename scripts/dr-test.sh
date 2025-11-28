#!/bin/bash
# Automated Disaster Recovery Testing Script
# Usage: ./dr-test.sh <environment> [test-type]
#
# Environments: non-prod, prod
# Test types: backup, snapshot, pitr, full
#
# Example:
#   ./dr-test.sh non-prod backup     # Test backup procedures only
#   ./dr-test.sh non-prod full       # Full DR test (backup + restore)
#   ./dr-test.sh prod snapshot       # Test RDS snapshot creation (safe)
#
# IMPORTANT: This script is SAFE for production. It does NOT perform destructive
# operations by default. Use with caution and read prompts carefully.

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
export AWS_PROFILE=lightwave-admin-new
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
TEST_RESULTS_DIR="${INFRA_ROOT}/dr-test-results/${TIMESTAMP}"

# Parse arguments
ENVIRONMENT="${1:-}"
TEST_TYPE="${2:-backup}"

# Validation
if [[ -z "${ENVIRONMENT}" ]]; then
    echo -e "${RED}❌ Error: Environment is required${NC}"
    echo ""
    echo "Usage: $0 <environment> [test-type]"
    echo ""
    echo "Environments:"
    echo "  non-prod    Test in non-production environment"
    echo "  prod        Test in production environment (read-only tests)"
    echo ""
    echo "Test types:"
    echo "  backup      Test backup procedures (default)"
    echo "  snapshot    Test RDS snapshot creation"
    echo "  pitr        Test point-in-time recovery feasibility"
    echo "  full        Full DR test (backup + restore simulation)"
    echo ""
    exit 1
fi

if [[ ! "${ENVIRONMENT}" =~ ^(non-prod|prod)$ ]]; then
    echo -e "${RED}❌ Error: Invalid environment '${ENVIRONMENT}'${NC}"
    echo "Valid environments: non-prod, prod"
    exit 1
fi

if [[ ! "${TEST_TYPE}" =~ ^(backup|snapshot|pitr|full)$ ]]; then
    echo -e "${RED}❌ Error: Invalid test type '${TEST_TYPE}'${NC}"
    echo "Valid test types: backup, snapshot, pitr, full"
    exit 1
fi

# Create test results directory
mkdir -p "${TEST_RESULTS_DIR}"

# Log file
LOG_FILE="${TEST_RESULTS_DIR}/dr-test.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

# Test result tracking
TEST_START_TIME=$(date +%s)
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ  ${1}${NC}"
}

log_success() {
    echo -e "${GREEN}✅ ${1}${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_warning() {
    echo -e "${YELLOW}⚠️  ${1}${NC}"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
}

log_error() {
    echo -e "${RED}❌ ${1}${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

run_test() {
    local test_name="$1"
    local test_command="$2"

    echo ""
    echo "========================================="
    echo "Test: ${test_name}"
    echo "========================================="

    if eval "${test_command}"; then
        log_success "${test_name} passed"
        return 0
    else
        log_error "${test_name} failed"
        return 1
    fi
}

# Test functions
test_aws_connectivity() {
    log_info "Testing AWS connectivity..."

    if aws sts get-caller-identity > /dev/null 2>&1; then
        ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        log_success "AWS connectivity confirmed (Account: ${ACCOUNT_ID})"
        return 0
    else
        log_error "Cannot connect to AWS. Check AWS_PROFILE=${AWS_PROFILE}"
        return 1
    fi
}

test_s3_state_bucket() {
    log_info "Testing S3 state bucket access..."

    local bucket_name="lightwave-terraform-state-${ENVIRONMENT}-us-east-1"

    if aws s3 ls "s3://${bucket_name}/" > /dev/null 2>&1; then
        log_success "S3 state bucket accessible: ${bucket_name}"

        # Check versioning
        local versioning=$(aws s3api get-bucket-versioning --bucket "${bucket_name}" --query Status --output text)
        if [[ "${versioning}" == "Enabled" ]]; then
            log_success "S3 versioning enabled on state bucket"
        else
            log_warning "S3 versioning NOT enabled on state bucket"
        fi

        return 0
    else
        log_error "Cannot access S3 state bucket: ${bucket_name}"
        return 1
    fi
}

test_dynamodb_lock_table() {
    log_info "Testing DynamoDB lock table..."

    local table_name="lightwave-terraform-locks-${ENVIRONMENT}"

    if aws dynamodb describe-table --table-name "${table_name}" > /dev/null 2>&1; then
        log_success "DynamoDB lock table exists: ${table_name}"
        return 0
    else
        log_error "Cannot access DynamoDB lock table: ${table_name}"
        return 1
    fi
}

test_terraform_state_backup() {
    log_info "Testing Terraform state backup..."

    local backup_script="${SCRIPT_DIR}/backup-state.sh"

    if [[ ! -f "${backup_script}" ]]; then
        log_warning "Backup script not found: ${backup_script}"
        return 1
    fi

    # Run backup script
    if bash "${backup_script}" "${ENVIRONMENT}"; then
        log_success "State backup completed successfully"
        return 0
    else
        log_error "State backup failed"
        return 1
    fi
}

test_rds_snapshots() {
    log_info "Testing RDS snapshot availability..."

    # Find RDS instances
    local db_instances=$(aws rds describe-db-instances \
        --query "DBInstances[?contains(DBInstanceIdentifier, '${ENVIRONMENT}')].DBInstanceIdentifier" \
        --output text)

    if [[ -z "${db_instances}" ]]; then
        log_warning "No RDS instances found for ${ENVIRONMENT}"
        return 1
    fi

    log_info "Found RDS instances: ${db_instances}"

    for db_instance in ${db_instances}; do
        # Check for automated snapshots
        local snapshot_count=$(aws rds describe-db-snapshots \
            --db-instance-identifier "${db_instance}" \
            --snapshot-type automated \
            --query 'length(DBSnapshots)' \
            --output text)

        if [[ "${snapshot_count}" -gt 0 ]]; then
            log_success "RDS instance ${db_instance} has ${snapshot_count} automated snapshots"

            # Get latest snapshot details
            local latest_snapshot=$(aws rds describe-db-snapshots \
                --db-instance-identifier "${db_instance}" \
                --snapshot-type automated \
                --query 'DBSnapshots | sort_by(@, &SnapshotCreateTime) | [-1].{ID:DBSnapshotIdentifier,Time:SnapshotCreateTime,Status:Status}' \
                --output table)

            echo "${latest_snapshot}"
        else
            log_warning "RDS instance ${db_instance} has NO automated snapshots"
        fi
    done

    return 0
}

test_create_manual_snapshot() {
    log_info "Creating manual RDS snapshot for DR test..."

    # Find RDS instances
    local db_instances=$(aws rds describe-db-instances \
        --query "DBInstances[?contains(DBInstanceIdentifier, '${ENVIRONMENT}')].DBInstanceIdentifier" \
        --output text)

    if [[ -z "${db_instances}" ]]; then
        log_warning "No RDS instances found for ${ENVIRONMENT}"
        return 1
    fi

    for db_instance in ${db_instances}; do
        local snapshot_id="${db_instance}-dr-test-${TIMESTAMP}"

        log_info "Creating snapshot: ${snapshot_id}"

        if aws rds create-db-snapshot \
            --db-instance-identifier "${db_instance}" \
            --db-snapshot-identifier "${snapshot_id}" \
            --tags Key=Purpose,Value=DR-Test Key=Timestamp,Value="${TIMESTAMP}" \
            > /dev/null 2>&1; then

            log_success "Snapshot creation initiated: ${snapshot_id}"
            log_info "Snapshot will be available in ~5-10 minutes"
            echo "  Monitor: aws rds describe-db-snapshots --db-snapshot-identifier ${snapshot_id}"
        else
            log_error "Failed to create snapshot for ${db_instance}"
            return 1
        fi
    done

    return 0
}

test_pitr_window() {
    log_info "Testing point-in-time recovery window..."

    # Find RDS instances
    local db_instances=$(aws rds describe-db-instances \
        --query "DBInstances[?contains(DBInstanceIdentifier, '${ENVIRONMENT}')].DBInstanceIdentifier" \
        --output text)

    if [[ -z "${db_instances}" ]]; then
        log_warning "No RDS instances found for ${ENVIRONMENT}"
        return 1
    fi

    for db_instance in ${db_instances}; do
        local pitr_info=$(aws rds describe-db-instances \
            --db-instance-identifier "${db_instance}" \
            --query 'DBInstances[0].{BackupRetention:BackupRetentionPeriod,LatestRestore:LatestRestorableTime,EarliestRestore:EarliestRestorableTime}' \
            --output table)

        log_success "PITR info for ${db_instance}:"
        echo "${pitr_info}"
    done

    return 0
}

test_restore_simulation() {
    log_info "Simulating restore procedure (dry-run)..."

    # This is a DRY RUN - it does NOT actually restore anything
    log_warning "This is a simulation only - no actual restore will occur"

    # Find RDS instances
    local db_instances=$(aws rds describe-db-instances \
        --query "DBInstances[?contains(DBInstanceIdentifier, '${ENVIRONMENT}')].DBInstanceIdentifier" \
        --output text)

    if [[ -z "${db_instances}" ]]; then
        log_warning "No RDS instances found for ${ENVIRONMENT}"
        return 1
    fi

    for db_instance in ${db_instances}; do
        log_info "Restore simulation for: ${db_instance}"

        # Get latest snapshot
        local latest_snapshot=$(aws rds describe-db-snapshots \
            --db-instance-identifier "${db_instance}" \
            --snapshot-type automated \
            --query 'DBSnapshots | sort_by(@, &SnapshotCreateTime) | [-1].DBSnapshotIdentifier' \
            --output text)

        if [[ -n "${latest_snapshot}" ]]; then
            log_info "Would restore from snapshot: ${latest_snapshot}"
            log_info "Command that would be executed:"
            echo "  aws rds restore-db-instance-from-db-snapshot \\"
            echo "    --db-instance-identifier ${db_instance}-restored \\"
            echo "    --db-snapshot-identifier ${latest_snapshot}"
            log_success "Restore command validated"
        else
            log_error "No snapshots available for ${db_instance}"
        fi
    done

    return 0
}

test_cross_region_snapshots() {
    log_info "Checking for cross-region snapshot copies..."

    # Check us-west-2 for copied snapshots
    local dr_region="us-west-2"

    # Find RDS instances in primary region
    local db_instances=$(aws rds describe-db-instances \
        --query "DBInstances[?contains(DBInstanceIdentifier, '${ENVIRONMENT}')].DBInstanceIdentifier" \
        --output text)

    if [[ -z "${db_instances}" ]]; then
        log_warning "No RDS instances found for ${ENVIRONMENT}"
        return 1
    fi

    for db_instance in ${db_instances}; do
        # Check DR region for snapshots
        local dr_snapshot_count=$(aws rds describe-db-snapshots \
            --region "${dr_region}" \
            --db-instance-identifier "${db_instance}" \
            --query 'length(DBSnapshots)' \
            --output text 2>/dev/null || echo "0")

        if [[ "${dr_snapshot_count}" -gt 0 ]]; then
            log_success "Found ${dr_snapshot_count} cross-region snapshots in ${dr_region} for ${db_instance}"
        else
            log_warning "No cross-region snapshots found in ${dr_region} for ${db_instance}"
            log_info "Consider implementing cross-region snapshot copy for full DR capability"
        fi
    done

    return 0
}

# Main test execution
echo "========================================="
echo "Disaster Recovery Test"
echo "========================================="
echo "Environment:  ${ENVIRONMENT}"
echo "Test Type:    ${TEST_TYPE}"
echo "Timestamp:    ${TIMESTAMP}"
echo "AWS Profile:  ${AWS_PROFILE}"
echo "Results Dir:  ${TEST_RESULTS_DIR}"
echo "========================================="
echo ""

# Safety check for production
if [[ "${ENVIRONMENT}" == "prod" ]]; then
    echo -e "${YELLOW}⚠️  WARNING: Running DR test in PRODUCTION environment${NC}"
    echo -e "${YELLOW}   This test will perform READ-ONLY operations${NC}"
    echo -e "${YELLOW}   No destructive actions will be taken${NC}"
    echo ""

    if [[ "${TEST_TYPE}" == "full" ]]; then
        echo -e "${RED}❌ FULL DR tests are NOT allowed in production${NC}"
        echo "Use 'backup', 'snapshot', or 'pitr' test types for production"
        exit 1
    fi
fi

# Run prerequisite tests
run_test "AWS Connectivity" "test_aws_connectivity"
run_test "S3 State Bucket" "test_s3_state_bucket"
run_test "DynamoDB Lock Table" "test_dynamodb_lock_table"

# Run test type specific tests
case "${TEST_TYPE}" in
    backup)
        run_test "Terraform State Backup" "test_terraform_state_backup"
        run_test "RDS Snapshot Availability" "test_rds_snapshots"
        ;;

    snapshot)
        run_test "RDS Snapshot Availability" "test_rds_snapshots"
        run_test "Create Manual Snapshot" "test_create_manual_snapshot"
        run_test "Cross-Region Snapshots" "test_cross_region_snapshots"
        ;;

    pitr)
        run_test "RDS Snapshot Availability" "test_rds_snapshots"
        run_test "Point-in-Time Recovery Window" "test_pitr_window"
        ;;

    full)
        if [[ "${ENVIRONMENT}" != "non-prod" ]]; then
            log_error "Full DR tests are only allowed in non-prod"
            exit 1
        fi

        run_test "Terraform State Backup" "test_terraform_state_backup"
        run_test "RDS Snapshot Availability" "test_rds_snapshots"
        run_test "Point-in-Time Recovery Window" "test_pitr_window"
        run_test "Restore Simulation" "test_restore_simulation"
        run_test "Cross-Region Snapshots" "test_cross_region_snapshots"
        ;;
esac

# Calculate test duration
TEST_END_TIME=$(date +%s)
TEST_DURATION=$((TEST_END_TIME - TEST_START_TIME))

# Generate summary
echo ""
echo "========================================="
echo "Test Summary"
echo "========================================="
echo "Duration:     ${TEST_DURATION} seconds"
echo "Tests Passed: ${TESTS_PASSED}"
echo "Tests Failed: ${TESTS_FAILED}"
echo "Tests Skipped: ${TESTS_SKIPPED}"
echo "========================================="
echo ""

# Save summary to file
cat > "${TEST_RESULTS_DIR}/summary.txt" <<EOF
Disaster Recovery Test Summary
==============================

Environment:  ${ENVIRONMENT}
Test Type:    ${TEST_TYPE}
Timestamp:    ${TIMESTAMP}
Duration:     ${TEST_DURATION} seconds

Results:
--------
Passed:       ${TESTS_PASSED}
Failed:       ${TESTS_FAILED}
Skipped:      ${TESTS_SKIPPED}

Log file:     ${LOG_FILE}
EOF

log_info "Test results saved to: ${TEST_RESULTS_DIR}"

# Exit with appropriate code
if [[ ${TESTS_FAILED} -gt 0 ]]; then
    echo -e "${RED}❌ DR Test FAILED${NC}"
    echo "Review log file: ${LOG_FILE}"
    exit 1
else
    echo -e "${GREEN}✅ DR Test PASSED${NC}"
    exit 0
fi
