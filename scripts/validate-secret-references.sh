#!/usr/bin/env bash
# Validate secret references in Terragrunt files
# Usage: ./validate-secret-references.sh [DIRECTORY]
#
# This script:
# 1. Scans Terragrunt files for secret references
# 2. Validates secret naming conventions
# 3. Checks if referenced secrets exist in AWS Secrets Manager
# 4. Reports unused secrets and missing references

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
SEARCH_DIR="${1:-.}"
REGION="${AWS_REGION:-us-east-1}"
CHECK_AWS=true
STRICT_MODE=false

# Parse additional arguments
shift || true
while [[ $# -gt 0 ]]; do
  case $1 in
    --no-aws-check)
      CHECK_AWS=false
      shift
      ;;
    --strict)
      STRICT_MODE=true
      shift
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [DIRECTORY] [OPTIONS]"
      echo ""
      echo "Validate secret references in Terragrunt files"
      echo ""
      echo "Options:"
      echo "  --no-aws-check    Skip validation against AWS Secrets Manager"
      echo "  --strict          Fail on any warning (exit code 1)"
      echo "  --region REGION   AWS region (default: us-east-1)"
      echo "  --help            Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0                                    # Validate current directory"
      echo "  $0 prod/us-east-1                     # Validate specific directory"
      echo "  $0 . --strict                         # Strict mode (fail on warnings)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Counters for summary
TOTAL_FILES=0
TOTAL_REFERENCES=0
VALID_REFERENCES=0
INVALID_NAMES=0
MISSING_SECRETS=0
WARNINGS=0

echo -e "${BLUE}=== Validating Secret References ===${NC}"
echo "Search Directory: $SEARCH_DIR"
echo "AWS Region: $REGION"
echo "AWS Check: $CHECK_AWS"
echo ""

# Check dependencies
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed${NC}"
    exit 1
fi

# Get list of existing secrets from AWS if check is enabled
EXISTING_SECRETS=()
if [[ "$CHECK_AWS" == true ]]; then
    if ! command -v aws &> /dev/null; then
        echo -e "${YELLOW}Warning: AWS CLI not installed, skipping AWS validation${NC}"
        CHECK_AWS=false
    elif ! aws sts get-caller-identity --region "$REGION" &> /dev/null; then
        echo -e "${YELLOW}Warning: AWS credentials not configured, skipping AWS validation${NC}"
        CHECK_AWS=false
    else
        echo -e "${BLUE}Fetching existing secrets from AWS Secrets Manager...${NC}"
        mapfile -t EXISTING_SECRETS < <(aws secretsmanager list-secrets \
            --region "$REGION" \
            --output json | jq -r '.SecretList[].Name')
        echo -e "${GREEN}✓ Found ${#EXISTING_SECRETS[@]} secret(s) in AWS${NC}"
        echo ""
    fi
fi

# Function to validate secret name format
validate_secret_name() {
    local secret_name="$1"

    # Pattern: /{environment}/{service}/{secret_type}
    if [[ "$secret_name" =~ ^/[a-z0-9-]+/[a-z0-9-]+/[a-z_]+$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to check if secret exists in AWS
secret_exists_in_aws() {
    local secret_name="$1"

    for existing_secret in "${EXISTING_SECRETS[@]}"; do
        if [[ "$existing_secret" == "$secret_name" ]]; then
            return 0
        fi
    done

    return 1
}

# Find all Terragrunt files
echo -e "${BLUE}Scanning Terragrunt files...${NC}"
mapfile -t HCL_FILES < <(find "$SEARCH_DIR" -name "*.hcl" -type f ! -path "*/.terragrunt-cache/*" ! -path "*/.terraform/*")

if [[ ${#HCL_FILES[@]} -eq 0 ]]; then
    echo -e "${YELLOW}No Terragrunt files found in $SEARCH_DIR${NC}"
    exit 0
fi

echo -e "${GREEN}Found ${#HCL_FILES[@]} Terragrunt file(s)${NC}"
echo ""

# Array to store all referenced secrets
declare -A REFERENCED_SECRETS

# Scan each file for secret references
for file in "${HCL_FILES[@]}"; do
    ((TOTAL_FILES++))

    # Look for common secret reference patterns:
    # 1. secret_name = "/prod/backend/database_password"
    # 2. secret_id = "/prod/backend/jwt_secret"
    # 3. dependency.secrets.outputs.xxx
    # 4. data.aws_secretsmanager_secret_version

    # Extract direct secret name references
    while IFS= read -r secret_name; do
        if [[ -n "$secret_name" ]]; then
            ((TOTAL_REFERENCES++))

            # Track this reference
            if [[ -z "${REFERENCED_SECRETS[$secret_name]:-}" ]]; then
                REFERENCED_SECRETS[$secret_name]="$file"
            else
                REFERENCED_SECRETS[$secret_name]="${REFERENCED_SECRETS[$secret_name]},$file"
            fi

            # Validate naming convention
            if ! validate_secret_name "$secret_name"; then
                ((INVALID_NAMES++))
                echo -e "${RED}✗ Invalid secret name format: $secret_name${NC}"
                echo "  File: $file"
                echo "  Expected pattern: /{environment}/{service}/{secret_type}"
                echo "  Example: /prod/backend/database_password"
                echo ""
            else
                ((VALID_REFERENCES++))

                # Check if exists in AWS
                if [[ "$CHECK_AWS" == true ]]; then
                    if ! secret_exists_in_aws "$secret_name"; then
                        ((MISSING_SECRETS++))
                        echo -e "${YELLOW}⚠️  Secret not found in AWS: $secret_name${NC}"
                        echo "  File: $file"
                        echo "  Create with: aws secretsmanager create-secret --name '$secret_name' --secret-string 'value'"
                        echo ""
                    fi
                fi
            fi
        fi
    done < <(grep -oP '(?<=secret_name|secret_id)\s*=\s*"\K/[^"]+' "$file" 2>/dev/null || true)
done

# Check for unused secrets in AWS
if [[ "$CHECK_AWS" == true ]] && [[ ${#EXISTING_SECRETS[@]} -gt 0 ]]; then
    echo -e "${BLUE}Checking for unused secrets in AWS...${NC}"

    UNUSED_COUNT=0
    for secret in "${EXISTING_SECRETS[@]}"; do
        if [[ -z "${REFERENCED_SECRETS[$secret]:-}" ]]; then
            ((UNUSED_COUNT++))
            ((WARNINGS++))
            echo -e "${YELLOW}⚠️  Unused secret (not referenced in any Terragrunt file): $secret${NC}"
        fi
    done

    if [[ $UNUSED_COUNT -eq 0 ]]; then
        echo -e "${GREEN}✓ No unused secrets found${NC}"
    fi
    echo ""
fi

# Summary
echo -e "${BLUE}=== Validation Summary ===${NC}"
echo ""
echo "Files Scanned: $TOTAL_FILES"
echo "Total References: $TOTAL_REFERENCES"
echo ""

if [[ $VALID_REFERENCES -gt 0 ]]; then
    echo -e "${GREEN}✓ Valid References: $VALID_REFERENCES${NC}"
fi

if [[ $INVALID_NAMES -gt 0 ]]; then
    echo -e "${RED}✗ Invalid Names: $INVALID_NAMES${NC}"
fi

if [[ $MISSING_SECRETS -gt 0 ]]; then
    echo -e "${YELLOW}⚠️  Missing in AWS: $MISSING_SECRETS${NC}"
fi

if [[ $WARNINGS -gt 0 ]]; then
    echo -e "${YELLOW}⚠️  Warnings: $WARNINGS${NC}"
fi

echo ""

# Exit code logic
EXIT_CODE=0

if [[ $INVALID_NAMES -gt 0 ]]; then
    echo -e "${RED}Validation failed: Invalid secret naming conventions detected${NC}"
    EXIT_CODE=1
fi

if [[ $MISSING_SECRETS -gt 0 ]]; then
    echo -e "${YELLOW}Validation warning: Some referenced secrets don't exist in AWS${NC}"
    if [[ "$STRICT_MODE" == true ]]; then
        EXIT_CODE=1
    fi
fi

if [[ $EXIT_CODE -eq 0 ]]; then
    echo -e "${GREEN}✓ Validation passed${NC}"
else
    echo -e "${RED}✗ Validation failed${NC}"
fi

exit $EXIT_CODE
