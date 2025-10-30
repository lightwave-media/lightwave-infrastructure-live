#!/bin/bash
# Backs up production Terraform state before deployments
# Usage: ./backup-prod-state.sh
#
# Restore procedure:
#   1. cd to the module directory
#   2. terragrunt state push /path/to/backup/<module-name>.tfstate
#   3. terragrunt plan (verify state is correct)

set -euo pipefail

export AWS_PROFILE=lightwave-admin-new
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKUP_DIR="${INFRA_ROOT}/state-backups/${TIMESTAMP}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "========================================="
echo "Production State Backup"
echo "========================================="
echo "Timestamp:   ${TIMESTAMP}"
echo "Backup Dir:  ${BACKUP_DIR}"
echo "AWS Profile: ${AWS_PROFILE}"
echo "========================================="
echo ""

# Create backup directory
mkdir -p "${BACKUP_DIR}"

# Navigate to prod directory
PROD_DIR="${INFRA_ROOT}/prod/us-east-1"

if [ ! -d "${PROD_DIR}" ]; then
    echo -e "${RED}❌ Production directory not found: ${PROD_DIR}${NC}"
    exit 1
fi

cd "${PROD_DIR}" || exit 1

echo "Scanning for Terragrunt modules..."
echo ""

# Find all terragrunt.hcl files and backup their state
MODULE_COUNT=0
SUCCESS_COUNT=0
SKIP_COUNT=0

while IFS= read -r hcl_file; do
    module_dir=$(dirname "$hcl_file")
    module_name=$(echo "${module_dir}" | tr '/' '_' | sed 's/^\._//')
    
    echo "Processing: ${module_dir}"
    
    # Navigate to module directory
    pushd "${module_dir}" > /dev/null || continue
    
    # Try to pull current state
    if terragrunt state pull > "${BACKUP_DIR}/${module_name}.tfstate" 2>/dev/null; then
        # Check if state file has content
        if [ -s "${BACKUP_DIR}/${module_name}.tfstate" ]; then
            echo -e "${GREEN}  ✅ Backed up: ${module_name}.tfstate${NC}"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            echo -e "${YELLOW}  ⚠️  Empty state: ${module_dir}${NC}"
            rm "${BACKUP_DIR}/${module_name}.tfstate"
            SKIP_COUNT=$((SKIP_COUNT + 1))
        fi
    else
        echo -e "${YELLOW}  ⚠️  No state found: ${module_dir}${NC}"
        SKIP_COUNT=$((SKIP_COUNT + 1))
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
echo "========================================="
echo ""

if [ ${SUCCESS_COUNT} -gt 0 ]; then
    echo -e "${GREEN}✅ State backup complete: ${BACKUP_DIR}${NC}"
    echo ""
    echo "Backup files:"
    ls -lh "${BACKUP_DIR}"
    echo ""
    echo "To restore a specific module:"
    echo "  1. cd <module-directory>"
    echo "  2. terragrunt state push ${BACKUP_DIR}/<module-name>.tfstate"
    echo "  3. terragrunt plan  # Verify state is correct"
    echo ""
    exit 0
else
    echo -e "${RED}❌ No state files were backed up${NC}"
    echo "This may indicate that infrastructure hasn't been deployed yet."
    exit 1
fi
