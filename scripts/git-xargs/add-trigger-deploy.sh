#!/bin/bash
# =============================================================================
# Add trigger-deploy.yml workflow to repository
# This script is executed by git-xargs in each target repository
# =============================================================================

set -e

# Use git-xargs provided env var (preferred) or fallback to git remote
# XARGS_REPO_NAME is set by git-xargs when executing scripts
if [ -n "$XARGS_REPO_NAME" ]; then
  REPO_NAME="$XARGS_REPO_NAME"
else
  # Fallback for local testing
  REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
  if [ -n "$REMOTE_URL" ]; then
    REPO_NAME=$(basename "$REMOTE_URL" .git)
  else
    REPO_NAME=$(basename "$(pwd)")
  fi
fi
echo "Processing repo: $REPO_NAME (XARGS_REPO_NAME=${XARGS_REPO_NAME:-not set})"

# Map repo names to their ECS/ECR configuration
# Format: APP_NAME|ECR_REPO|ECS_CLUSTER|ECS_SERVICE
case "$REPO_NAME" in
  cineos)
    APP_NAME="cineos"
    ECR_REPOSITORY="738605694078.dkr.ecr.us-east-1.amazonaws.com/cineos"
    ECS_CLUSTER="cineos-prod"
    ECS_SERVICE="cineos-prod"
    ;;
  photographos)
    APP_NAME="photographos"
    ECR_REPOSITORY="738605694078.dkr.ecr.us-east-1.amazonaws.com/photographos"
    ECS_CLUSTER="photographos-prod"
    ECS_SERVICE="photographos-prod"
    ;;
  createos)
    APP_NAME="createos"
    ECR_REPOSITORY="738605694078.dkr.ecr.us-east-1.amazonaws.com/createos"
    ECS_CLUSTER="createos-prod"
    ECS_SERVICE="createos-prod"
    ;;
  lightwave-backend)
    APP_NAME="lightwave-backend"
    ECR_REPOSITORY="738605694078.dkr.ecr.us-east-1.amazonaws.com/lightwave-backend"
    ECS_CLUSTER="lightwave-backend-prod"
    ECS_SERVICE="lightwave-backend-prod"
    ;;
  lightwave-media-site)
    APP_NAME="lightwave-media-site"
    # Note: This is a Cloudflare Pages site, not ECS
    # The workflow is set up for documentation but may need modification
    ECR_REPOSITORY="N/A"
    ECS_CLUSTER="N/A"
    ECS_SERVICE="N/A"
    ;;
  *)
    echo "Unknown repository: $REPO_NAME"
    exit 1
    ;;
esac

# Create .github/workflows directory if it doesn't exist
mkdir -p .github/workflows

# Create the trigger-deploy.yml workflow
cat > .github/workflows/trigger-deploy.yml << 'WORKFLOW_EOF'
name: Trigger Deployment

# =============================================================================
# App Repository Trigger Workflow
# =============================================================================
#
# This workflow triggers the centralized deployment pipeline.
# It runs tests locally and then dispatches to infrastructure-live.
#
# =============================================================================

on:
  push:
    branches:
      - main
  workflow_dispatch:
    inputs:
      environment:
        description: 'Target environment'
        required: true
        type: choice
        options:
          - prod
          - staging
          - dev
        default: 'prod'

env:
  # ========================================
  # APP CONFIGURATION
  # ========================================
WORKFLOW_EOF

# Append the environment variables (these get substituted)
cat >> .github/workflows/trigger-deploy.yml << EOF
  APP_NAME: ${APP_NAME}
  ECR_REPOSITORY: ${ECR_REPOSITORY}
  ECS_CLUSTER: ${ECS_CLUSTER}
  ECS_SERVICE: ${ECS_SERVICE}
EOF

# Append the rest of the workflow (literal, no substitution)
cat >> .github/workflows/trigger-deploy.yml << 'WORKFLOW_EOF'

jobs:
  test:
    name: Run Tests
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install dependencies
        run: |
          pip install uv
          uv pip install -r requirements.txt --system
        continue-on-error: true

      - name: Run tests
        run: |
          echo "Running tests..."
          if [ -f "Makefile" ] && grep -q "^test:" Makefile; then
            make test
          elif [ -f "pytest.ini" ] || [ -f "pyproject.toml" ]; then
            pytest
          else
            echo "No tests configured - skipping"
          fi
        continue-on-error: false

  trigger-deploy:
    name: Trigger Deployment
    needs: test
    runs-on: ubuntu-latest

    steps:
      - name: Trigger deployment in infrastructure-live
        uses: peter-evans/repository-dispatch@v3
        with:
          token: ${{ secrets.INFRASTRUCTURE_DISPATCH_TOKEN }}
          repository: lightwave-media/lightwave-infrastructure-live
          event-type: deploy-app
          client-payload: |
            {
              "app_name": "${{ env.APP_NAME }}",
              "git_ref": "${{ github.sha }}",
              "environment": "${{ inputs.environment || 'prod' }}",
              "task_type": "app_deployer",
              "ecr_repository": "${{ env.ECR_REPOSITORY }}",
              "ecs_cluster": "${{ env.ECS_CLUSTER }}",
              "ecs_service": "${{ env.ECS_SERVICE }}",
              "triggered_by": "${{ github.actor }}",
              "commit_message": "${{ github.event.head_commit.message }}"
            }

      - name: Deployment triggered
        run: |
          echo "Deployment triggered!"
          echo ""
          echo "App: ${{ env.APP_NAME }}"
          echo "Commit: ${{ github.sha }}"
          echo "Environment: ${{ inputs.environment || 'prod' }}"
          echo ""
          echo "View deployment progress at:"
          echo "https://github.com/lightwave-media/lightwave-infrastructure-live/actions"
WORKFLOW_EOF

echo "Created .github/workflows/trigger-deploy.yml for $APP_NAME"
