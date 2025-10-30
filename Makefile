.PHONY: setup plan-nonprod apply-nonprod plan-prod apply-prod cleanup help install-hooks verify-state-nonprod verify-state-prod test-nonprod test-prod health-check-prod backup-state backup-state-nonprod backup-state-prod dr-test-nonprod dr-test-prod dr-test-full-nonprod restore-from-backup cost-report-daily cost-compare-monthly check-idle-resources create-cost-dashboard deploy-budgets activate-cost-tags

# Default target
.DEFAULT_GOAL := help

# Environment variables
export TG_BUCKET_PREFIX := lightwave-
export AWS_PROFILE := lightwave-admin-new
export AWS_REGION := us-east-1

setup: ## Install tools and configure pre-commit hooks
	@echo "Installing Gruntwork tools..."
	@./scripts/install-tools.sh
	@echo "Installing pre-commit hooks..."
	@$(HOME)/Library/Python/3.10/bin/pre-commit install
	@echo "✅ Setup complete!"

install-hooks: ## Install pre-commit hooks only
	@$(HOME)/Library/Python/3.10/bin/pre-commit install
	@echo "✅ Pre-commit hooks installed"

verify-state-nonprod: ## Verify remote state health for non-prod
	@echo "Verifying remote state health for non-prod..."
	@./scripts/verify-remote-state.sh non-prod us-east-1

verify-state-prod: ## Verify remote state health for production
	@echo "Verifying remote state health for production..."
	@./scripts/verify-remote-state.sh prod us-east-1

plan-nonprod: ## Run terragrunt plan on non-prod environment
	@echo "Planning non-prod infrastructure..."
	@cd non-prod/us-east-1 && terragrunt run-all plan --terragrunt-non-interactive

apply-nonprod: verify-state-nonprod ## Apply changes to non-prod environment (with pre-flight checks)
	@echo "⚠️  Applying changes to non-prod environment..."
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		cd non-prod/us-east-1 && terragrunt run-all apply --terragrunt-non-interactive; \
	else \
		echo "Cancelled."; \
	fi

destroy-nonprod: ## Destroy non-prod infrastructure
	@echo "⚠️  WARNING: This will DESTROY all non-prod infrastructure!"
	@read -p "Type 'DELETE' to confirm: " confirm; \
	if [ "$$confirm" = "DELETE" ]; then \
		cd non-prod/us-east-1 && terragrunt run-all destroy --terragrunt-non-interactive; \
	else \
		echo "Cancelled."; \
	fi

plan-prod: ## Run terragrunt plan on production environment
	@echo "Planning production infrastructure..."
	@cd prod/us-east-1 && terragrunt run-all plan --terragrunt-non-interactive

apply-prod: verify-state-prod ## Apply changes to production environment (with pre-flight checks)
	@echo "⚠️  PRODUCTION DEPLOYMENT - Applying changes to PRODUCTION environment..."
	@read -p "Are you ABSOLUTELY sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		cd prod/us-east-1 && terragrunt run-all apply --terragrunt-non-interactive; \
	else \
		echo "Cancelled."; \
	fi

destroy-prod: ## Destroy production infrastructure
	@echo "⚠️  DANGER: This will DESTROY all PRODUCTION infrastructure!"
	@read -p "Type 'DELETE-PRODUCTION' to confirm: " confirm; \
	if [ "$$confirm" = "DELETE-PRODUCTION" ]; then \
		cd prod/us-east-1 && terragrunt run-all destroy --terragrunt-non-interactive; \
	else \
		echo "Cancelled."; \
	fi

cleanup-test-resources: ## Run cloud-nuke to cleanup old test resources (dry-run)
	@echo "Running cloud-nuke (dry-run)..."
	@$(HOME)/bin/cloud-nuke aws \
		--region $(AWS_REGION) \
		--older-than 24h \
		--resource-type ec2,ecs,lambda,s3,rds,elb,ebs,ami,snapshot \
		--exclude-resource-type iam \
		--dry-run

cleanup-test-resources-force: ## Force cleanup of old test resources (DESTRUCTIVE)
	@echo "⚠️  WARNING: This will DELETE resources older than 24h!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		$(HOME)/bin/cloud-nuke aws \
			--region $(AWS_REGION) \
			--older-than 24h \
			--resource-type ec2,ecs,lambda,s3,rds,elb,ebs,ami,snapshot \
			--exclude-resource-type iam \
			--force; \
	else \
		echo "Cancelled."; \
	fi

catalog: ## Open terragrunt catalog browser
	@cd non-prod/us-east-1 && terragrunt catalog

fmt: ## Format all terragrunt files
	@echo "Formatting Terragrunt files..."
	@terragrunt hclfmt
	@echo "✅ Formatting complete"

validate: ## Validate terragrunt configuration
	@echo "Validating non-prod configuration..."
	@cd non-prod/us-east-1 && terragrunt run-all validate
	@echo "Validating prod configuration..."
	@cd prod/us-east-1 && terragrunt run-all validate
	@echo "✅ Validation complete"

test-nonprod: ## Run smoke tests against non-prod environment
	@echo "Running non-prod smoke tests..."
	@./scripts/smoke-test-nonprod.sh

test-prod: ## Run smoke tests against production environment
	@echo "Running production smoke tests..."
	@./scripts/smoke-test-prod.sh

health-check-prod: ## Detailed production health check
	@echo "Running detailed production health checks..."
	@echo ""
	@echo "ECS Service Status:"
	@aws ecs describe-services --cluster lightwave-prod --services backend-prod --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}' --output table || echo "⚠️  ECS service not found"
	@echo ""
	@echo "RDS Instance Status:"
	@aws rds describe-db-instances --db-instance-identifier prod-postgres --query 'DBInstances[0].{Status:DBInstanceStatus,Engine:Engine,MultiAZ:MultiAZ}' --output table 2>/dev/null || echo "⚠️  RDS instance not found"
	@echo ""
	@echo "✅ Health check complete"

backup-state: ## Backup production state (legacy - use backup-state-prod)
	@echo "Backing up production state..."
	@./scripts/backup-prod-state.sh

backup-state-nonprod: ## Backup non-prod Terraform state
	@echo "Backing up non-prod state..."
	@./scripts/backup-state.sh non-prod

backup-state-prod: ## Backup production Terraform state
	@echo "Backing up production state..."
	@./scripts/backup-state.sh prod

dr-test-nonprod: ## Run DR backup test for non-prod
	@echo "Running DR backup test for non-prod..."
	@./scripts/dr-test.sh non-prod backup

dr-test-prod: ## Run DR backup test for production (read-only)
	@echo "Running DR backup test for production..."
	@./scripts/dr-test.sh prod backup

dr-test-full-nonprod: ## Run full DR test for non-prod (includes restore simulation)
	@echo "Running full DR test for non-prod..."
	@./scripts/dr-test.sh non-prod full

restore-from-backup: ## Restore Terraform state from backup (requires BACKUP_DIR)
	@if [ -z "$(BACKUP_DIR)" ]; then \
		echo "❌ Error: BACKUP_DIR is required"; \
		echo ""; \
		echo "Usage: make restore-from-backup BACKUP_DIR=<path>"; \
		echo ""; \
		echo "Example:"; \
		echo "  make restore-from-backup BACKUP_DIR=state-backups/prod/latest"; \
		echo ""; \
		exit 1; \
	fi
	@echo "⚠️  WARNING: This will restore state from backup"
	@./scripts/restore-from-backup.sh $(BACKUP_DIR) --dry-run
	@echo ""
	@read -p "Review the dry-run output. Proceed with actual restore? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		./scripts/restore-from-backup.sh $(BACKUP_DIR); \
	else \
		echo "Cancelled."; \
	fi

detect-drift-nonprod: ## Detect infrastructure drift in non-prod
	@echo "Detecting drift in non-prod environment..."
	@./scripts/detect-drift.sh non-prod us-east-1 markdown

detect-drift-prod: ## Detect infrastructure drift in production
	@echo "Detecting drift in production environment..."
	@./scripts/detect-drift.sh prod us-east-1 markdown

detect-drift-all: ## Detect infrastructure drift in all environments
	@echo "Detecting drift in all environments..."
	@./scripts/detect-drift.sh non-prod us-east-1 markdown
	@echo ""
	@./scripts/detect-drift.sh prod us-east-1 markdown

suggest-remediation: ## Suggest remediation for latest drift report (requires DRIFT_REPORT)
	@if [ -z "$(DRIFT_REPORT)" ]; then \
		echo "❌ Error: DRIFT_REPORT is required"; \
		echo ""; \
		echo "Usage: make suggest-remediation DRIFT_REPORT=<path>"; \
		echo ""; \
		echo "Example:"; \
		echo "  make suggest-remediation DRIFT_REPORT=drift-reports/non-prod-us-east-1-drift-20251029_123456.json"; \
		echo ""; \
		exit 1; \
	fi
	@./scripts/suggest-drift-remediation.sh $(DRIFT_REPORT)

clean: ## Clean up terraform state and cache files
	@echo "Cleaning up terraform artifacts..."
	@find . -type f -name "terraform.tfstate*" -delete
	@find . -type f -name ".terraform.lock.hcl" -delete
	@find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "provider.tf" -delete
	@find . -type f -name "backend.tf" -delete
	@echo "✅ Cleanup complete"

# ---------------------------------------------------------------------------------------------------------------------
# COST MONITORING TARGETS
# ---------------------------------------------------------------------------------------------------------------------

cost-report-daily: ## Generate daily cost report with anomaly detection
	@echo "Generating daily cost report..."
	@./scripts/cost-report-daily.sh

cost-compare-monthly: ## Compare current month vs last month spending
	@echo "Generating monthly cost comparison..."
	@./scripts/cost-compare-monthly.sh

check-idle-resources: ## Identify unused AWS resources generating costs
	@echo "Checking for idle resources..."
	@./scripts/check-idle-resources.sh

create-cost-dashboard: ## Deploy CloudWatch dashboard for cost monitoring
	@echo "Creating CloudWatch cost dashboard..."
	@./scripts/create-cost-dashboard.sh

deploy-budgets: ## Deploy AWS Budgets for all environments
	@echo "Deploying budgets for production..."
	@cd prod/us-east-1/budget && terragrunt apply
	@echo ""
	@echo "Deploying budgets for non-production..."
	@cd non-prod/us-east-1/budget && terragrunt apply
	@echo "✅ Budgets deployed. Check email for SNS confirmation links."

activate-cost-tags: ## Activate cost allocation tags in AWS
	@echo "Activating cost allocation tags..."
	@aws ce update-cost-allocation-tags-status \
		--cost-allocation-tags-status \
		TagKey=Environment,Status=Active \
		TagKey=ManagedBy,Status=Active \
		TagKey=Owner,Status=Active \
		TagKey=CostCenter,Status=Active \
		TagKey=Project,Status=Active \
		TagKey=Service,Status=Active \
		TagKey=Component,Status=Active
	@echo "✅ Cost allocation tags activated (may take 24 hours to appear in Cost Explorer)"

cost-setup: activate-cost-tags create-cost-dashboard deploy-budgets ## Complete cost monitoring setup
	@echo ""
	@echo "✅ Cost monitoring setup complete!"
	@echo ""
	@echo "Next steps:"
	@echo "1. Confirm SNS email subscriptions (check your inbox)"
	@echo "2. Wait 24 hours for cost tags to activate"
	@echo "3. View CloudWatch dashboard at:"
	@echo "   https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=LightWave-Cost-Monitoring"
	@echo "4. Schedule daily cost reports: cron daily at 9am"
	@echo "5. Schedule monthly cost reviews: first Monday of each month"

# ---------------------------------------------------------------------------------------------------------------------

help: ## Show this help message
	@echo "LightWave Infrastructure Live - Make Commands"
	@echo ""
	@echo "Usage:"
	@echo "  make <target>"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-28s\033[0m %s\n", $$1, $$2}'
