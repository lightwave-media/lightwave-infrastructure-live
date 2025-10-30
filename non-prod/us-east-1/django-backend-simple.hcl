# Simple Django deployment using default VPC - PROOF OF CONCEPT
terraform {
  source = "git::git@github.com:lightwave-media/lightwave-infrastructure-catalog.git//modules/postgresql?ref=main"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "account" {
  path = find_in_parent_folders("account.hcl")
}

include "region" {
  path = find_in_parent_folders("region.hcl")
}

inputs = {
  name              = "lightwave-django-dev"
  instance_class    = "db.t4g.micro"
  allocated_storage = 20
  
  # Test credentials - NOT FOR PRODUCTION
  master_username = "django_admin"
  master_password = "ChangeMe123456!" # TODO: Move to Secrets Manager
  
  # Use default VPC
  vpc_id = "vpc-017c0258df97dbc01"
  subnet_ids = [
    "subnet-0733093924db0de82",  # us-east-1a
    "subnet-04e323d1e20654c42",  # us-east-1b
    "subnet-0e19cf5fa5e5f73c2"   # us-east-1c
  ]
  
  # Dev settings - fast iteration
  environment             = "dev"
  multi_az                = false
  backup_retention_period = 1
  deletion_protection     = false
  skip_final_snapshot     = true
  
  storage_encrypted = false  # Faster for dev
  
  tags = {
    Environment = "dev"
    ManagedBy   = "Terragrunt"
    Purpose     = "Django Backend POC"
  }
}
