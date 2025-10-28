.PHONY: setup plan-nonprod apply-nonprod plan-prod apply-prod cleanup help install-hooks

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

plan-nonprod: ## Run terragrunt plan on non-prod environment
	@echo "Planning non-prod infrastructure..."
	@cd non-prod/us-east-1 && terragrunt run-all plan --terragrunt-non-interactive

apply-nonprod: ## Apply changes to non-prod environment
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

apply-prod: ## Apply changes to production environment
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

clean: ## Clean up terraform state and cache files
	@echo "Cleaning up terraform artifacts..."
	@find . -type f -name "terraform.tfstate*" -delete
	@find . -type f -name ".terraform.lock.hcl" -delete
	@find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "provider.tf" -delete
	@find . -type f -name "backend.tf" -delete
	@echo "✅ Cleanup complete"

help: ## Show this help message
	@echo "LightWave Infrastructure Live - Make Commands"
	@echo ""
	@echo "Usage:"
	@echo "  make <target>"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-28s\033[0m %s\n", $$1, $$2}'
