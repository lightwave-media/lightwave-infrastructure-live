# LightWave Infrastructure Live

Production infrastructure configurations for LightWave Media AWS environments.

## Structure

```
lightwave-infrastructure-live/
├── root.hcl              # Root Terragrunt config (backend, providers)
├── non-prod/             # Staging/dev environment
│   ├── account.hcl
│   └── us-east-1/
│       ├── region.hcl
│       └── budget/
└── prod/                 # Production environment
    ├── account.hcl
    └── us-east-1/
        ├── region.hcl
        └── cineos/       # CineOS Django backend stack
```

## Prerequisites

```bash
# Install tools via mise
mise install

# Or manually install:
# - Terragrunt: https://terragrunt.gruntwork.io/docs/getting-started/install/
# - OpenTofu: https://opentofu.org/docs/intro/install/
```

## Usage

```bash
# Set AWS profile
export AWS_PROFILE=lightwave-admin-new

# Plan changes
make plan-nonprod    # Non-prod environment
make plan-prod       # Production environment

# Apply changes (with confirmation)
make apply-nonprod
make apply-prod
```

## Available Commands

```bash
make help            # Show all commands
make plan-nonprod    # Plan non-prod changes
make plan-prod       # Plan production changes
make apply-nonprod   # Apply non-prod (with confirmation)
make apply-prod      # Apply production (requires confirmation)
make validate        # Validate all configurations
make fmt             # Format HCL files
make detect-drift-all # Check for infrastructure drift
make cost-report-daily # Generate cost report
```

## Current Stacks

### CineOS (`prod/us-east-1/cineos/`)

Django backend with:
- PostgreSQL RDS (Multi-AZ)
- Redis ElastiCache
- ECS Fargate service
- S3 media storage

## Adding New Infrastructure

1. Create stack directory: `prod/us-east-1/<service-name>/`
2. Create `terragrunt.stack.hcl` referencing modules from `lightwave-infrastructure-catalog`
3. Run `terragrunt stack generate` to create units
4. Plan and apply

## Related Repositories

- **lightwave-infrastructure-catalog**: Reusable Terraform modules
- **domains/**: Application code repositories
