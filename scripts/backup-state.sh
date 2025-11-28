#!/bin/bash
# Backs up Terraform state for any environment
# Usage: ./backup-state.sh <environment>
#
# Examples:
#   ./backup-state.sh non-prod
#   ./backup-state.sh prod
#
# Restore procedure:
#   1. cd to the module directory
#   2. terragrunt state push /path/to/backup/<module-name>.tfstate
#   3. terragrunt plan (verify state is correct)

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
export AWS_PROFILE=lightwave-admin-new
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Parse arguments
ENVIRONMENT="${1:-}"

# Validation
if [[ -z "${ENVIRONMENT}" ]]; then
    echo -e "${RED}❌ Error: Environment is required${NC}"
    echo ""
    echo "Usage: $0 <environment>"
    echo ""
    echo "Environments:"
    echo "  non-prod    Backup non-production environment"
    echo "  prod        Backup production environment"
    echo ""
    exit 1
fi

if [[ ! "${ENVIRONMENT}" =~ ^(non-prod|prod)$ ]]; then
    echo -e "${RED}❌ Error: Invalid environment '${ENVIRONMENT}'${NC}"
    echo "Valid environments: non-prod, prod"
    exit 1
fi

# Set backup directory
BACKUP_DIR="${INFRA_ROOT}/state-backups/${ENVIRONMENT}/${TIMESTAMP}"

# Display banner
echo "========================================="
echo "Terraform State Backup"
echo "========================================="
echo "Environment: ${ENVIRONMENT}"
echo "Timestamp:   ${TIMESTAMP}"
echo "Backup Dir:  ${BACKUP_DIR}"
echo "AWS Profile: ${AWS_PROFILE}"
echo "========================================="
echo ""

# Safety check for production
if [[ "${ENVIRONMENT}" == "prod" ]]; then
    echo -e "${YELLOW}⚠️  WARNING: Backing up PRODUCTION state${NC}"
    echo "This is a read-only operation and is safe."
    echo ""
fi

# Create backup directory
mkdir -p "${BACKUP_DIR}"

# Navigate to environment directory
ENV_DIR="${INFRA_ROOT}/${ENVIRONMENT}/us-east-1"

if [ ! -d "${ENV_DIR}" ]; then
    echo -e "${RED}❌ Environment directory not found: ${ENV_DIR}${NC}"
    exit 1
fi

cd "${ENV_DIR}" || exit 1

echo -e "${BLUE}ℹ  Scanning for Terragrunt modules...${NC}"
echo ""

# Find all terragrunt.hcl files and backup their state
MODULE_COUNT=0
SUCCESS_COUNT=0
SKIP_COUNT=0
FAILED_COUNT=0

while IFS= read -r hcl_file; do
    module_dir=$(dirname "$hcl_file")
    module_name=$(echo "${module_dir}" | tr '/' '_' | sed 's/^\._//')

    echo "Processing: ${module_dir}"

    # Navigate to module directory
    pushd "${module_dir}" > /dev/null || continue

    # Try to pull current state
    if terragrunt state pull > "${BACKUP_DIR}/${module_name}.tfstate" 2>/dev/null; then
        # Check if state file has content (not empty)
        if [ -s "${BACKUP_DIR}/${module_name}.tfstate" ]; then
            # Check if state contains resources (not just empty state structure)
            resource_count=$(jq '.resources | length' "${BACKUP_DIR}/${module_name}.tfstate" 2>/dev/null || echo "0")

            if [[ "${resource_count}" -gt 0 ]]; then
                file_size=$(du -h "${BACKUP_DIR}/${module_name}.tfstate" | cut -f1)
                echo -e "${GREEN}  ✅ Backed up: ${module_name}.tfstate (${file_size}, ${resource_count} resources)${NC}"
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            else
                echo -e "${YELLOW}  ⚠️  Empty state (no resources): ${module_dir}${NC}"
                rm "${BACKUP_DIR}/${module_name}.tfstate"
                SKIP_COUNT=$((SKIP_COUNT + 1))
            fi
        else
            echo -e "${YELLOW}  ⚠️  Empty state file: ${module_dir}${NC}"
            rm "${BACKUP_DIR}/${module_name}.tfstate}"
            SKIP_COUNT=$((SKIP_COUNT + 1))
        fi
    else
        echo -e "${RED}  ❌ Failed to pull state: ${module_dir}${NC}"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi

    MODULE_COUNT=$((MODULE_COUNT + 1))
    popd > /dev/null || exit

done < <(find . -name "terragrunt.hcl" -not -path "*/.terragrunt-cache/*" -not -path "*/.terragrunt-stack/*")

echo ""
echo "========================================="
echo "Backup Summary"
echo "========================================="
echo "Modules found:    ${MODULE_COUNT}"
echo "States backed up: ${SUCCESS_COUNT}"
echo "Skipped (empty):  ${SKIP_COUNT}"
echo "Failed:           ${FAILED_COUNT}"
echo "========================================="
echo ""

# Create backup metadata
cat > "${BACKUP_DIR}/metadata.json" <<EOF
{
  "environment": "${ENVIRONMENT}",
  "timestamp": "${TIMESTAMP}",
  "backup_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "aws_profile": "${AWS_PROFILE}",
  "aws_account": "$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo 'unknown')",
  "modules_total": ${MODULE_COUNT},
  "states_backed_up": ${SUCCESS_COUNT},
  "states_skipped": ${SKIP_COUNT},
  "states_failed": ${FAILED_COUNT}
}
EOF

if [ ${SUCCESS_COUNT} -gt 0 ]; then
    echo -e "${GREEN}✅ State backup complete: ${BACKUP_DIR}${NC}"
    echo ""
    echo "Backup files:"
    ls -lh "${BACKUP_DIR}" | grep -v "^total"
    echo ""
    echo "Metadata saved to: ${BACKUP_DIR}/metadata.json"
    echo ""
    echo -e "${BLUE}To restore a specific module:${NC}"
    echo "  1. cd <module-directory>"
    echo "  2. terragrunt state push ${BACKUP_DIR}/<module-name>.tfstate"
    echo "  3. terragrunt plan  # Verify state is correct"
    echo ""
    echo -e "${BLUE}To restore all modules:${NC}"
    echo "  ./scripts/restore-from-backup.sh ${BACKUP_DIR}"
    echo ""

    # Create symlink to latest backup
    LATEST_LINK="${INFRA_ROOT}/state-backups/${ENVIRONMENT}/latest"
    rm -f "${LATEST_LINK}"
    ln -s "${BACKUP_DIR}" "${LATEST_LINK}"
    echo -e "${BLUE}ℹ  Latest backup symlink created: ${LATEST_LINK}${NC}"
    echo ""

    exit 0
else
    echo -e "${RED}❌ No state files were backed up${NC}"

    if [[ ${FAILED_COUNT} -gt 0 ]]; then
        echo "Some modules failed to backup. Check the output above for errors."
        exit 1
    else
        echo "This may indicate that infrastructure hasn't been deployed yet."
        exit 1
    fi
fi
