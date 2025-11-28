#!/usr/bin/env bash
# List all secrets in AWS Secrets Manager
# Usage: ./list-secrets.sh [--filter PATTERN] [--format table|json|csv]
#
# Examples:
#   ./list-secrets.sh                           # List all secrets (table format)
#   ./list-secrets.sh --filter prod             # List only prod secrets
#   ./list-secrets.sh --format json             # Output as JSON
#   ./list-secrets.sh --filter backend --format csv  # Backend secrets as CSV

set -euo pipefail

# Default values
FILTER=""
FORMAT="table"
SHOW_ROTATION_STATUS=true
REGION="${AWS_REGION:-us-east-1}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --filter)
      FILTER="$2"
      shift 2
      ;;
    --format)
      FORMAT="$2"
      shift 2
      ;;
    --no-rotation)
      SHOW_ROTATION_STATUS=false
      shift
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "List all secrets in AWS Secrets Manager"
      echo ""
      echo "Options:"
      echo "  --filter PATTERN       Filter secrets by name pattern"
      echo "  --format FORMAT        Output format: table, json, csv (default: table)"
      echo "  --no-rotation          Skip rotation status check (faster)"
      echo "  --region REGION        AWS region (default: us-east-1)"
      echo "  --help                 Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0                                    # List all secrets"
      echo "  $0 --filter prod                      # List production secrets"
      echo "  $0 --format json                      # Output as JSON"
      echo "  $0 --filter backend --format csv      # Backend secrets as CSV"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Check AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    exit 1
fi

# Check AWS credentials are configured
if ! aws sts get-caller-identity --region "$REGION" &> /dev/null; then
    echo -e "${RED}Error: AWS credentials not configured or invalid${NC}"
    echo "Set AWS_PROFILE environment variable: export AWS_PROFILE=lightwave-admin-new"
    exit 1
fi

echo -e "${BLUE}Retrieving secrets from AWS Secrets Manager (region: $REGION)...${NC}" >&2

# Get list of secrets
SECRETS_JSON=$(aws secretsmanager list-secrets \
    --region "$REGION" \
    --output json)

# Apply filter if specified
if [[ -n "$FILTER" ]]; then
    SECRETS_JSON=$(echo "$SECRETS_JSON" | jq --arg filter "$FILTER" '.SecretList | map(select(.Name | contains($filter)))')
else
    SECRETS_JSON=$(echo "$SECRETS_JSON" | jq '.SecretList')
fi

# Get secret count
SECRET_COUNT=$(echo "$SECRETS_JSON" | jq 'length')

if [[ "$SECRET_COUNT" -eq 0 ]]; then
    echo -e "${YELLOW}No secrets found${NC}" >&2
    exit 0
fi

echo -e "${GREEN}Found $SECRET_COUNT secret(s)${NC}" >&2
echo "" >&2

# Function to get rotation status for a secret
get_rotation_status() {
    local secret_name="$1"
    local rotation_info

    rotation_info=$(aws secretsmanager describe-secret \
        --secret-id "$secret_name" \
        --region "$REGION" \
        --output json 2>/dev/null || echo '{}')

    local rotation_enabled=$(echo "$rotation_info" | jq -r '.RotationEnabled // false')
    local rotation_days=$(echo "$rotation_info" | jq -r '.RotationRules.AutomaticallyAfterDays // "N/A"')
    local last_rotated=$(echo "$rotation_info" | jq -r '.LastRotatedDate // "Never"')

    if [[ "$last_rotated" != "Never" ]]; then
        last_rotated=$(date -r $(echo "$last_rotated" | cut -d'.' -f1 | sed 's/T/ /') "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$last_rotated")
    fi

    echo "$rotation_enabled|$rotation_days|$last_rotated"
}

# Output based on format
case "$FORMAT" in
    json)
        # JSON format
        if [[ "$SHOW_ROTATION_STATUS" == true ]]; then
            # Add rotation info to JSON
            echo "$SECRETS_JSON" | jq -r '.[] | @json' | while read -r secret; do
                secret_name=$(echo "$secret" | jq -r '.Name')
                rotation_status=$(get_rotation_status "$secret_name")

                rotation_enabled=$(echo "$rotation_status" | cut -d'|' -f1)
                rotation_days=$(echo "$rotation_status" | cut -d'|' -f2)
                last_rotated=$(echo "$rotation_status" | cut -d'|' -f3)

                echo "$secret" | jq \
                    --arg rotation_enabled "$rotation_enabled" \
                    --arg rotation_days "$rotation_days" \
                    --arg last_rotated "$last_rotated" \
                    '. + {RotationEnabled: ($rotation_enabled == "true"), RotationDays: $rotation_days, LastRotated: $last_rotated}'
            done | jq -s '.'
        else
            echo "$SECRETS_JSON"
        fi
        ;;

    csv)
        # CSV format
        echo "Name,Description,LastChangedDate,Tags,RotationEnabled,RotationDays,LastRotated"

        echo "$SECRETS_JSON" | jq -r '.[] | @json' | while read -r secret; do
            secret_name=$(echo "$secret" | jq -r '.Name')
            description=$(echo "$secret" | jq -r '.Description // "N/A"')
            last_changed=$(echo "$secret" | jq -r '.LastChangedDate // "N/A"')
            tags=$(echo "$secret" | jq -r '[.Tags[]? | "\(.Key)=\(.Value)"] | join("; ")')

            if [[ "$SHOW_ROTATION_STATUS" == true ]]; then
                rotation_status=$(get_rotation_status "$secret_name")
                rotation_enabled=$(echo "$rotation_status" | cut -d'|' -f1)
                rotation_days=$(echo "$rotation_status" | cut -d'|' -f2)
                last_rotated=$(echo "$rotation_status" | cut -d'|' -f3)
            else
                rotation_enabled="N/A"
                rotation_days="N/A"
                last_rotated="N/A"
            fi

            echo "\"$secret_name\",\"$description\",\"$last_changed\",\"$tags\",\"$rotation_enabled\",\"$rotation_days\",\"$last_rotated\""
        done
        ;;

    table|*)
        # Table format (default)
        printf "${BLUE}%-60s %-40s %-12s %-10s${NC}\n" "NAME" "DESCRIPTION" "ROTATION" "LAST ROTATED"
        printf "${BLUE}%-60s %-40s %-12s %-10s${NC}\n" "----" "-----------" "--------" "------------"

        echo "$SECRETS_JSON" | jq -r '.[] | @json' | while read -r secret; do
            secret_name=$(echo "$secret" | jq -r '.Name')
            description=$(echo "$secret" | jq -r '.Description // "N/A"' | cut -c1-38)

            if [[ "$SHOW_ROTATION_STATUS" == true ]]; then
                rotation_status=$(get_rotation_status "$secret_name")
                rotation_enabled=$(echo "$rotation_status" | cut -d'|' -f1)
                rotation_days=$(echo "$rotation_status" | cut -d'|' -f2)
                last_rotated=$(echo "$rotation_status" | cut -d'|' -f3 | cut -c1-20)

                if [[ "$rotation_enabled" == "true" ]]; then
                    rotation_text="${GREEN}Yes (${rotation_days}d)${NC}"
                else
                    rotation_text="${RED}No${NC}"
                fi
            else
                rotation_text="N/A"
                last_rotated="N/A"
            fi

            printf "%-60s %-40s %-20s %-20s\n" "$secret_name" "$description" "$(echo -e "$rotation_text")" "$last_rotated"
        done

        echo ""
        echo -e "${BLUE}Total: $SECRET_COUNT secret(s)${NC}"
        ;;
esac
