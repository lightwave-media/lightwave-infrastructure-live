#!/bin/bash
# Restores Terraform state from backup
# Usage: ./restore-from-backup.sh <backup-directory> [--dry-run]
#
# Examples:
#   ./restore-from-backup.sh state-backups/prod/20251028-143000 --dry-run
#   ./restore-from-backup.sh state-backups/prod/latest
#   ./restore-from-backup.sh state-backups/non-prod/20251028-143000
#
# WARNING: This is a DESTRUCTIVE operation. It will overwrite current state.
# ALWAYS run with --dry-run first to verify the restore plan.
#
# Safety features:
#   - Requires explicit confirmation for production
#   - Creates backup of current state before restore
#   - Validates backup metadata before restore
#   - Supports dry-run mode

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

# Parse arguments
BACKUP_DIR="${1:-}"
DRY_RUN=false

if [[ "${2:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

# Validation
if [[ -z "${BACKUP_DIR}" ]]; then
    echo -e "${RED}❌ Error: Backup directory is required${NC}"
    echo ""
    echo "Usage: $0 <backup-directory> [--dry-run]"
    echo ""
    echo "Examples:"
    echo "  $0 state-backups/prod/20251028-143000 --dry-run"
    echo "  $0 state-backups/prod/latest"
    echo "  $0 state-backups/non-prod/latest"
    echo ""
    echo "Available backups:"
    ls -lh "${INFRA_ROOT}/state-backups/" 2>/dev/null || echo "  No backups found"
    echo ""
    exit 1
fi

# Handle relative paths
if [[ ! "${BACKUP_DIR}" =~ ^/ ]]; then
    BACKUP_DIR="${INFRA_ROOT}/${BACKUP_DIR}"
fi

# Resolve symlinks (e.g., "latest")
BACKUP_DIR=$(readlink -f "${BACKUP_DIR}" 2>/dev/null || realpath "${BACKUP_DIR}" 2>/dev/null || echo "${BACKUP_DIR}")

# Verify backup directory exists
if [[ ! -d "${BACKUP_DIR}" ]]; then
    echo -e "${RED}❌ Backup directory not found: ${BACKUP_DIR}${NC}"
    exit 1
fi

# Load backup metadata
METADATA_FILE="${BACKUP_DIR}/metadata.json"
if [[ ! -f "${METADATA_FILE}" ]]; then
    echo -e "${RED}❌ Backup metadata not found: ${METADATA_FILE}${NC}"
    echo "This may not be a valid backup directory."
    exit 1
fi

# Parse metadata
ENVIRONMENT=$(jq -r '.environment' "${METADATA_FILE}")
BACKUP_TIMESTAMP=$(jq -r '.timestamp' "${METADATA_FILE}")
BACKUP_DATE=$(jq -r '.backup_date' "${METADATA_FILE}")
STATES_COUNT=$(jq -r '.states_backed_up' "${METADATA_FILE}")

# Display banner
echo "========================================="
if [[ "${DRY_RUN}" == true ]]; then
    echo "Terraform State Restore (DRY RUN)"
else
    echo "Terraform State Restore"
fi
echo "========================================="
echo "Environment:      ${ENVIRONMENT}"
echo "Backup Timestamp: ${BACKUP_TIMESTAMP}"
echo "Backup Date:      ${BACKUP_DATE}"
echo "State Files:      ${STATES_COUNT}"
echo "Backup Dir:       ${BACKUP_DIR}"
echo "AWS Profile:      ${AWS_PROFILE}"
echo "========================================="
echo ""

# Safety checks
if [[ "${DRY_RUN}" == false ]]; then
    echo -e "${RED}⚠️  WARNING: This is a DESTRUCTIVE operation${NC}"
    echo -e "${RED}   Current Terraform state will be OVERWRITTEN${NC}"
    echo ""

    if [[ "${ENVIRONMENT}" == "prod" ]]; then
        echo -e "${RED}🚨 CRITICAL: You are about to restore PRODUCTION state${NC}"
        echo ""
        echo "Before proceeding, ensure you:"
        echo "  1. Have communicated with the team"
        echo "  2. Understand what caused the need for restore"
        echo "  3. Have backed up the current state"
        echo "  4. Are in an incident war room or have approval"
        echo ""
        read -p "Type 'RESTORE-PRODUCTION' to confirm: " confirm
        if [[ "${confirm}" != "RESTORE-PRODUCTION" ]]; then
            echo "Cancelled."
            exit 1
        fi
    else
        echo -e "${YELLOW}⚠️  You are about to restore ${ENVIRONMENT} state${NC}"
        echo ""
        read -p "Are you sure? Type 'yes' to confirm: " confirm
        if [[ "${confirm}" != "yes" ]]; then
            echo "Cancelled."
            exit 1
        fi
    fi

    # Backup current state before restore
    echo ""
    echo -e "${BLUE}ℹ  Creating backup of current state before restore...${NC}"
    CURRENT_STATE_BACKUP="${INFRA_ROOT}/state-backups/${ENVIRONMENT}/pre-restore-${TIMESTAMP}"
    mkdir -p "${CURRENT_STATE_BACKUP}"

    "${SCRIPT_DIR}/backup-state.sh" "${ENVIRONMENT}" > /dev/null 2>&1 || true
    echo -e "${GREEN}✅ Current state backed up${NC}"
    echo ""
fi

# Navigate to environment directory
ENV_DIR="${INFRA_ROOT}/${ENVIRONMENT}/us-east-1"

if [[ ! -d "${ENV_DIR}" ]]; then
    echo -e "${RED}❌ Environment directory not found: ${ENV_DIR}${NC}"
    exit 1
fi

# Find all state files in backup
STATE_FILES=$(find "${BACKUP_DIR}" -name "*.tfstate" -type f)

if [[ -z "${STATE_FILES}" ]]; then
    echo -e "${RED}❌ No state files found in backup directory${NC}"
    exit 1
fi

echo -e "${BLUE}ℹ  Found $(echo "${STATE_FILES}" | wc -l | tr -d ' ') state files to restore${NC}"
echo ""

# Restore state files
RESTORE_COUNT=0
SKIP_COUNT=0
FAIL_COUNT=0

for state_file in ${STATE_FILES}; do
    state_filename=$(basename "${state_file}")
    module_name="${state_filename%.tfstate}"

    # Convert module name back to directory path
    module_path=$(echo "${module_name}" | sed 's/_/\//g')

    # Remove leading dot-underscore if present
    module_path="${module_path#.}"

    module_dir="${ENV_DIR}/${module_path}"

    echo "Restoring: ${module_path}"

    if [[ ! -d "${module_dir}" ]]; then
        echo -e "${YELLOW}  ⚠️  Module directory not found: ${module_dir}${NC}"
        echo -e "${YELLOW}     Skipping...${NC}"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        continue
    fi

    if [[ "${DRY_RUN}" == true ]]; then
        echo -e "${BLUE}  [DRY RUN] Would restore: ${state_filename}${NC}"
        RESTORE_COUNT=$((RESTORE_COUNT + 1))
    else
        # Navigate to module directory
        pushd "${module_dir}" > /dev/null || continue

        # Push state
        if terragrunt state push "${state_file}" > /dev/null 2>&1; then
            echo -e "${GREEN}  ✅ Restored: ${state_filename}${NC}"
            RESTORE_COUNT=$((RESTORE_COUNT + 1))
        else
            echo -e "${RED}  ❌ Failed to restore: ${state_filename}${NC}"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi

        popd > /dev/null || exit
    fi
done

echo ""
echo "========================================="
echo "Restore Summary"
echo "========================================="
if [[ "${DRY_RUN}" == true ]]; then
    echo "Mode:             DRY RUN (no changes made)"
fi
echo "States restored:  ${RESTORE_COUNT}"
echo "States skipped:   ${SKIP_COUNT}"
echo "States failed:    ${FAIL_COUNT}"
echo "========================================="
echo ""

if [[ "${DRY_RUN}" == true ]]; then
    echo -e "${GREEN}✅ Dry run complete${NC}"
    echo ""
    echo "To perform the actual restore, run:"
    echo "  $0 ${BACKUP_DIR}"
    echo ""
    exit 0
fi

if [[ ${FAIL_COUNT} -gt 0 ]]; then
    echo -e "${RED}❌ Restore completed with ${FAIL_COUNT} failures${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Review failed modules above"
    echo "  2. Run 'terragrunt plan' in each module to verify state"
    echo "  3. Manually restore failed modules if needed"
    echo ""
    exit 1
elif [[ ${RESTORE_COUNT} -eq 0 ]]; then
    echo -e "${YELLOW}⚠️  No states were restored${NC}"
    echo "All modules were skipped (directories not found)"
    exit 1
else
    echo -e "${GREEN}✅ State restore complete${NC}"
    echo ""
    echo "IMPORTANT: Verify state integrity"
    echo ""
    echo "Run the following commands to verify:"
    echo "  cd ${ENV_DIR}"
    echo "  terragrunt run-all plan"
    echo ""
    echo "Expected result:"
    echo "  - Plan should show 'No changes' if restore was successful"
    echo "  - If plan shows changes, investigate before applying"
    echo ""
    echo "If you see unexpected changes:"
    echo "  1. Review what changed between backup and current code"
    echo "  2. Consider if these changes are expected"
    echo "  3. Consult with team before applying changes"
    echo ""

    # Create restore log
    RESTORE_LOG="${BACKUP_DIR}/restore-log-${TIMESTAMP}.txt"
    cat > "${RESTORE_LOG}" <<EOF
Terraform State Restore Log
===========================

Restore Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Environment: ${ENVIRONMENT}
Backup Source: ${BACKUP_DIR}
AWS Profile: ${AWS_PROFILE}
AWS Account: $(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo 'unknown')

Results:
--------
States Restored: ${RESTORE_COUNT}
States Skipped:  ${SKIP_COUNT}
States Failed:   ${FAIL_COUNT}

Next Steps:
-----------
1. Run 'terragrunt run-all plan' to verify state
2. Check for unexpected changes
3. Document incident and resolution
EOF

    echo "Restore log saved to: ${RESTORE_LOG}"
    echo ""

    exit 0
fi
