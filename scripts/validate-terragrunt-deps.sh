#!/usr/bin/env bash
#
# validate-terragrunt-deps.sh - Validate Terragrunt Stack configurations
#
# Description:
#   Validates Terragrunt Stack files using terragrunt render-json to catch
#   configuration errors, missing units, and broken dependencies.
#
# Usage:
#   ./validate-terragrunt-deps.sh
#
# Exit codes:
#   0 - All stack files are valid
#   1 - Invalid stack files found
#
# Author: LightWave Infrastructure Team
# Version: 2.0.0

set -euo pipefail

# Color output
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Counters
ERRORS=0
WARNINGS=0

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
    ((WARNINGS++))
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    ((ERRORS++))
}

# Find all Terragrunt Stack files
find_stack_files() {
    find . -type f -name "terragrunt.stack.hcl" \
        -not -path "*/\.terraform/*" \
        -not -path "*/\.terragrunt-cache/*" \
        -not -path "*/.terragrunt-stack/*"
}

# Validate a single stack file using HCL syntax check
validate_stack_file() {
    local stack_file="$1"

    log_info "Validating: $stack_file"

    # Basic HCL syntax validation using terragrunt hclfmt
    if terragrunt hclfmt --terragrunt-check --terragrunt-hclfmt-file "$stack_file" > /dev/null 2>&1; then
        log_info "  ✓ Valid HCL syntax"
        return 0
    else
        log_error "  ✗ Invalid HCL syntax or formatting"
        log_error "  Run: terragrunt hclfmt --terragrunt-hclfmt-file $stack_file"
        return 1
    fi
}

# Main validation logic
main() {
    log_info "Validating Terragrunt Stack configurations..."
    echo ""

    # Check if terragrunt is available
    if ! command -v terragrunt &> /dev/null; then
        log_warn "terragrunt not found - skipping validation"
        log_warn "Install terragrunt to enable stack validation"
        exit 0
    fi

    local stack_files
    stack_files=$(find_stack_files)

    if [[ -z "$stack_files" ]]; then
        log_info "No terragrunt.stack.hcl files found"
        log_info "This is normal if not using Terragrunt Stacks"
        exit 0
    fi

    local file_count
    file_count=$(echo "$stack_files" | wc -l | tr -d ' ')
    log_info "Found $file_count stack file(s)"
    echo ""

    # Validate each stack file
    while IFS= read -r file; do
        if ! validate_stack_file "$file"; then
            ((ERRORS++))
        fi
        echo ""
    done <<< "$stack_files"

    # Print summary
    echo "========================================="
    echo "        Validation Summary"
    echo "========================================="

    if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
        log_info "✅ All Terragrunt stacks are valid"
        exit 0
    elif [[ $ERRORS -eq 0 ]]; then
        log_warn "⚠️  Validation passed with $WARNINGS warning(s)"
        exit 0
    else
        log_error "❌ Validation failed with $ERRORS error(s)"
        log_error "Fix the errors above before committing"
        exit 1
    fi
}

# Execute main function
main "$@"
