#!/usr/bin/env bash
# Rotate a secret in AWS Secrets Manager
# Usage: ./rotate-secret.sh SECRET_NAME [OPTIONS]
#
# Examples:
#   ./rotate-secret.sh /prod/backend/database_password --dry-run
#   ./rotate-secret.sh /prod/backend/jwt_secret --new-value "new-secret-value"
#   ./rotate-secret.sh /prod/backend/api_key --generate --length 32

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DRY_RUN=false
GENERATE_PASSWORD=false
PASSWORD_LENGTH=32
NEW_VALUE=""
REGION="${AWS_REGION:-us-east-1}"
FORCE_DEPLOYMENT=false
AUTO_UPDATE_SERVICES=true

# Parse command line arguments
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 SECRET_NAME [OPTIONS]"
    echo ""
    echo "Rotate a secret in AWS Secrets Manager"
    echo ""
    echo "Options:"
    echo "  --dry-run                  Show what would be done without making changes"
    echo "  --new-value VALUE          Use specific value for rotation (not recommended for passwords)"
    echo "  --generate                 Generate a new random password"
    echo "  --length N                 Length of generated password (default: 32)"
    echo "  --region REGION            AWS region (default: us-east-1)"
    echo "  --force-deployment         Force ECS service deployment after rotation"
    echo "  --no-auto-update           Don't automatically update services after rotation"
    echo "  --help                     Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 /prod/backend/database_password --dry-run"
    echo "  $0 /prod/backend/jwt_secret --generate"
    echo "  $0 /prod/backend/api_key --new-value 'new-api-key-value'"
    exit 1
fi

SECRET_NAME="$1"
shift

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --generate)
      GENERATE_PASSWORD=true
      shift
      ;;
    --length)
      PASSWORD_LENGTH="$2"
      shift 2
      ;;
    --new-value)
      NEW_VALUE="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --force-deployment)
      FORCE_DEPLOYMENT=true
      shift
      ;;
    --no-auto-update)
      AUTO_UPDATE_SERVICES=false
      shift
      ;;
    --help)
      echo "Usage: $0 SECRET_NAME [OPTIONS]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Validate inputs
if [[ "$GENERATE_PASSWORD" == true ]] && [[ -n "$NEW_VALUE" ]]; then
    echo -e "${RED}Error: Cannot specify both --generate and --new-value${NC}"
    exit 1
fi

if [[ "$GENERATE_PASSWORD" == false ]] && [[ -z "$NEW_VALUE" ]]; then
    echo -e "${RED}Error: Must specify either --generate or --new-value${NC}"
    exit 1
fi

# Check dependencies
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    exit 1
fi

if [[ "$GENERATE_PASSWORD" == true ]] && ! command -v openssl &> /dev/null; then
    echo -e "${RED}Error: openssl is required for password generation${NC}"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity --region "$REGION" &> /dev/null; then
    echo -e "${RED}Error: AWS credentials not configured or invalid${NC}"
    echo "Set AWS_PROFILE environment variable: export AWS_PROFILE=lightwave-admin-new"
    exit 1
fi

echo -e "${BLUE}=== Secret Rotation for: $SECRET_NAME ===${NC}"
echo ""

# Check if secret exists
echo -e "${BLUE}Checking if secret exists...${NC}"
if ! aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$REGION" &> /dev/null; then
    echo -e "${RED}Error: Secret '$SECRET_NAME' not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Secret exists${NC}"

# Get secret metadata
SECRET_INFO=$(aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$REGION" --output json)
SECRET_DESCRIPTION=$(echo "$SECRET_INFO" | jq -r '.Description // "N/A"')
ROTATION_ENABLED=$(echo "$SECRET_INFO" | jq -r '.RotationEnabled // false')
LAST_CHANGED=$(echo "$SECRET_INFO" | jq -r '.LastChangedDate // "N/A"')

echo ""
echo -e "${BLUE}Current Secret Information:${NC}"
echo "  Description: $SECRET_DESCRIPTION"
echo "  Last Changed: $LAST_CHANGED"
echo "  Rotation Enabled: $ROTATION_ENABLED"
echo ""

# Generate new value if requested
if [[ "$GENERATE_PASSWORD" == true ]]; then
    echo -e "${BLUE}Generating new random password (length: $PASSWORD_LENGTH)...${NC}"
    NEW_VALUE=$(openssl rand -base64 48 | tr -d "=+/" | cut -c1-${PASSWORD_LENGTH})
    echo -e "${GREEN}✓ Password generated${NC}"
fi

# Dry run mode
if [[ "$DRY_RUN" == true ]]; then
    echo ""
    echo -e "${YELLOW}=== DRY RUN MODE ===${NC}"
    echo "Would perform the following actions:"
    echo "  1. Update secret value in AWS Secrets Manager"
    echo "  2. Create new secret version"

    if [[ "$AUTO_UPDATE_SERVICES" == true ]]; then
        echo "  3. Detect services using this secret"
        echo "  4. Force new deployment for affected ECS services"
    fi

    echo ""
    echo -e "${YELLOW}No changes were made (dry run)${NC}"
    exit 0
fi

# Confirm rotation
echo ""
echo -e "${YELLOW}⚠️  WARNING: This will rotate the secret and may impact running services${NC}"
echo ""
read -p "Are you sure you want to rotate this secret? (yes/no): " -r
echo ""

if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
    echo -e "${YELLOW}Rotation cancelled${NC}"
    exit 0
fi

# Perform rotation
echo -e "${BLUE}Rotating secret...${NC}"

if aws secretsmanager update-secret \
    --secret-id "$SECRET_NAME" \
    --secret-string "$NEW_VALUE" \
    --region "$REGION" &> /dev/null; then

    echo -e "${GREEN}✓ Secret rotated successfully${NC}"

    # Get new version ID
    NEW_VERSION=$(aws secretsmanager describe-secret \
        --secret-id "$SECRET_NAME" \
        --region "$REGION" \
        --output json | jq -r '.VersionIdsToStages | to_entries[] | select(.value[] == "AWSCURRENT") | .key')

    echo "  New Version ID: $NEW_VERSION"
else
    echo -e "${RED}✗ Failed to rotate secret${NC}"
    exit 1
fi

# Update services if enabled
if [[ "$AUTO_UPDATE_SERVICES" == true ]]; then
    echo ""
    echo -e "${BLUE}Detecting services that use this secret...${NC}"

    # Parse environment and service from secret name
    # Pattern: /{environment}/{service}/{secret_type}
    if [[ "$SECRET_NAME" =~ ^/([^/]+)/([^/]+)/([^/]+)$ ]]; then
        ENVIRONMENT="${BASH_REMATCH[1]}"
        SERVICE="${BASH_REMATCH[2]}"

        echo "  Environment: $ENVIRONMENT"
        echo "  Service: $SERVICE"

        # Try to find ECS cluster and service
        CLUSTER_NAME="lightwave-${ENVIRONMENT}"
        SERVICE_NAME="${SERVICE}-${ENVIRONMENT}"

        echo ""
        echo -e "${BLUE}Checking for ECS service: $SERVICE_NAME in cluster: $CLUSTER_NAME${NC}"

        if aws ecs describe-services \
            --cluster "$CLUSTER_NAME" \
            --services "$SERVICE_NAME" \
            --region "$REGION" &> /dev/null; then

            echo -e "${GREEN}✓ Found ECS service${NC}"

            if [[ "$FORCE_DEPLOYMENT" == true ]]; then
                echo ""
                echo -e "${BLUE}Forcing new deployment for ECS service...${NC}"

                if aws ecs update-service \
                    --cluster "$CLUSTER_NAME" \
                    --service "$SERVICE_NAME" \
                    --force-new-deployment \
                    --region "$REGION" &> /dev/null; then

                    echo -e "${GREEN}✓ New deployment initiated${NC}"
                    echo "  Services will restart and fetch the new secret value"
                else
                    echo -e "${YELLOW}⚠️  Failed to force deployment${NC}"
                fi
            else
                echo ""
                echo -e "${YELLOW}⚠️  Note: ECS service found but --force-deployment not specified${NC}"
                echo "  Run with --force-deployment to automatically update the service"
                echo "  Or manually force deployment with:"
                echo ""
                echo "    aws ecs update-service \\"
                echo "      --cluster $CLUSTER_NAME \\"
                echo "      --service $SERVICE_NAME \\"
                echo "      --force-new-deployment \\"
                echo "      --region $REGION"
            fi
        else
            echo -e "${YELLOW}⚠️  No ECS service found${NC}"
            echo "  If this secret is used by services, manually restart them to pick up the new value"
        fi
    fi
fi

# Summary
echo ""
echo -e "${GREEN}=== Rotation Complete ===${NC}"
echo ""
echo "Next steps:"
echo "  1. Verify applications can still authenticate/connect"
echo "  2. Monitor application logs for errors"
echo "  3. Check health endpoints"
echo ""
echo "Rollback (if needed):"
echo "  List all versions: aws secretsmanager list-secret-version-ids --secret-id '$SECRET_NAME' --region $REGION"
echo "  Restore previous version: aws secretsmanager update-secret-version-stage --secret-id '$SECRET_NAME' --version-stage AWSCURRENT --move-to-version-id <old-version-id> --region $REGION"
echo ""
