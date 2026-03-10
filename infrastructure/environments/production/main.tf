# =============================================================================
# LLMVault Production - Phase 0: Foundation
# Region: us-east-2
# Domain: llmvault.dev
# =============================================================================

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "llmvault"
      Environment = "production"
      ManagedBy   = "terraform"
    }
  }
}

# =============================================================================
# Phase 0: Foundation
# =============================================================================

module "vpc" {
  source = "../../modules/vpc"

  name               = "llmvault-prod"
  vpc_cidr           = "10.0.0.0/16"
  availability_zones = ["us-east-2a", "us-east-2b"]
  
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
  
  enable_nat_gateway = false  # Phase 3
  enable_vpn_gateway = false
}

module "ecr" {
  source = "../../modules/ecr"

  repositories = ["api", "web", "zitadel", "connect"]
  
  image_tag_mutability = "IMMUTABLE"
  scan_on_push         = true
}

module "iam" {
  source = "../../modules/iam"

  name_prefix = "llmvault-prod"
}

module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  name = "llmvault-prod"
  
  services = ["api", "web", "zitadel", "connect"]
  
  enable_container_insights = true
}

# =============================================================================
# Phase 1: Database Layer
# =============================================================================

module "rds" {
  source = "../../modules/rds"

  name       = "llmvault-prod"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
  
  # Allow ECS tasks to connect
  allowed_security_group_ids = [module.vpc.ecs_tasks_security_group_id]
  
  # Database configuration
  db_name             = "llmvault"
  db_username         = "llmvault"
  engine_version      = "17.4"
  instance_class      = "db.t4g.micro"
  allocated_storage   = 20
  max_allocated_storage = 100
  
  # Backup settings
  backup_retention_days = 7
  backup_window         = "03:00-04:00"
  maintenance_window    = "Mon:04:00-Mon:05:00"
  
  # Protection (disable for easier iteration)
  deletion_protection = false
  skip_final_snapshot = true
}

# =============================================================================
# Phase 2: Cache Layer
# =============================================================================

module "elasticache" {
  source = "../../modules/elasticache"

  name       = "llmvault-prod"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
  
  # Allow ECS tasks to connect
  allowed_security_group_ids = [module.vpc.ecs_tasks_security_group_id]
  
  # Cache configuration
  engine_version        = "7.1"
  node_type             = "cache.t4g.micro"
  snapshot_retention_days = 1
  snapshot_window       = "05:00-06:00"
  maintenance_window    = "sun:06:00-sun:07:00"
}

# =============================================================================
# Phase 3: Networking Layer (ALB, NAT Gateway, VPC Endpoints)
# =============================================================================
#
# ⚠️  IMPORTANT - TWO-PHASE DEPLOYMENT REQUIRED  ⚠️
#
# Due to Cloudflare DNS and ACM certificate validation requirements, this phase
# CANNOT be deployed in a single `terraform apply`. You MUST follow these steps:
#
# PHASE 3A - HTTP Only (Initial Deploy):
#   1. Set enable_https_listener = false (below)
#   2. Run: terraform apply
#   3. This creates:
#      - ALB with HTTP listener only (port 80)
#      - ACM certificate (PENDING_VALIDATION state)
#      - Outputs certificate validation DNS records
#
# PHASE 3B - Cloudflare DNS Setup (Manual):
#   4. Run: terraform output acm_certificate_validation_records
#   5. Add the CNAME records shown to Cloudflare DNS
#      Example:
#        Type:  CNAME
#        Name:  _ea984fc00f486736795ebfc520326565.llmvault.dev
#        Value: _f5b876404d042c8d3497a4a021afe3af.jkddzztszm.acm-validations.aws
#   6. Wait 2-5 minutes for ACM certificate status to become ISSUED
#   7. Verify: aws acm describe-certificate --certificate-arn <arn>
#
# PHASE 3C - Enable HTTPS:
#   8. Set enable_https_listener = true (below)
#   9. Run: terraform apply
#  10. This creates:
#      - HTTPS listener (port 443) with SSL certificate
#      - ALB listener rules for each subdomain
#      - HTTP → HTTPS redirect
#
# PHASE 3D - Application DNS (Cloudflare):
#  11. Run: terraform output alb_dns_name
#  12. Add CNAME records in Cloudflare for each subdomain:
#      - llmvault.dev → <alb-dns-name>
#      - auth.llmvault.dev → <alb-dns-name>
#      - api.llmvault.dev → <alb-dns-name>
#      - connect.llmvault.dev → <alb-dns-name>
#      - proxy.llmvault.dev → <alb-dns-name>
#
# FAILURE MODE:
# If you set enable_https_listener = true before certificate validation,
# terraform apply will FAIL with:
#   "UnsupportedCertificate: The certificate must have a fully-qualified domain name"
#
# WHY THIS COMPLEXITY?
# - ACM certificates require DNS validation
# - We use Cloudflare (external to AWS), not Route 53
# - Terraform cannot create Cloudflare DNS records
# - Manual DNS step is unavoidable
#
# =============================================================================

module "networking" {
  source = "../../modules/networking"

  name        = "llmvault-prod"
  vpc_id      = module.vpc.vpc_id
  aws_region  = var.aws_region
  domain_name = var.domain_name
  
  # ⚠️  STEP-BY-STEP:
  # 1. First deploy with false (HTTP only)
  # 2. Add Cloudflare DNS validation records
  # 3. Wait for certificate status = ISSUED
  # 4. Then set to true and re-apply (HTTPS + rules)
  enable_https_listener = true
  
  # Subnets
  public_subnet_ids  = module.vpc.public_subnet_ids
  private_subnet_ids = module.vpc.private_subnet_ids
  
  # Route tables
  public_route_table_ids  = [module.vpc.public_route_table_id]
  private_route_table_ids = module.vpc.private_route_table_ids
  
  # Other dependencies
  internet_gateway_id            = module.vpc.internet_gateway_id
  vpc_endpoint_security_group_id = module.vpc.vpc_endpoint_security_group_id
  
  services = ["api", "web", "zitadel", "connect"]
}

# =============================================================================
# Phase 4: ZITADEL Service (Identity & Auth)
# =============================================================================
# Deploys ZITADEL v4.12.1 with Login v2 enabled
# Login v2 is the default and required for new deployments
# =============================================================================

# Generate ZITADEL master key
resource "random_password" "zitadel_masterkey" {
  length  = 32
  special = false
}

# Generate ZITADEL admin credentials (random username for security)
resource "random_password" "zitadel_admin_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_string" "zitadel_admin_username" {
  length  = 12
  special = false
  upper   = true
  lower   = true
  numeric = true
}

# Store ZITADEL master key in Secrets Manager
resource "aws_secretsmanager_secret" "zitadel_masterkey" {
  name                    = "llmvault-prod/zitadel-masterkey"
  description             = "ZITADEL master key for llmvault-prod"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "zitadel_masterkey" {
  secret_id     = aws_secretsmanager_secret.zitadel_masterkey.id
  secret_string = random_password.zitadel_masterkey.result
}

# Store ZITADEL admin credentials in Secrets Manager
resource "aws_secretsmanager_secret" "zitadel_admin_username" {
  name                    = "llmvault-prod/zitadel-admin-username"
  description             = "ZITADEL admin username for llmvault-prod"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "zitadel_admin_username" {
  secret_id     = aws_secretsmanager_secret.zitadel_admin_username.id
  secret_string = random_string.zitadel_admin_username.result
}

resource "aws_secretsmanager_secret" "zitadel_admin_password" {
  name                    = "llmvault-prod/zitadel-admin-password"
  description             = "ZITADEL admin password for llmvault-prod"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "zitadel_admin_password" {
  secret_id     = aws_secretsmanager_secret.zitadel_admin_password.id
  secret_string = random_password.zitadel_admin_password.result
}

# Store ZITADEL database credentials
resource "aws_secretsmanager_secret" "zitadel_db_password" {
  name                    = "llmvault-prod/zitadel-db-password"
  description             = "ZITADEL database password for llmvault-prod"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "zitadel_db_password" {
  secret_id     = aws_secretsmanager_secret.zitadel_db_password.id
  secret_string = random_password.zitadel_masterkey.result  # Use masterkey as password
}

module "zitadel_service" {
  source = "../../modules/ecs-service"

  name         = "zitadel"
  cluster_id   = module.ecs_cluster.cluster_id
  cluster_name = module.ecs_cluster.cluster_name
  vpc_id       = module.vpc.vpc_id
  aws_region   = var.aws_region
  
  # Task resources - minimal for cost efficiency
  image             = "ghcr.io/zitadel/zitadel:v4.12.1"
  cpu               = "256"   # 0.25 vCPU
  memory            = "1024"  # 1 GB
  cpu_architecture  = "ARM64"
  
  # ZITADEL command - use 'start' after initialization is complete
  container_overrides = {
    command = ["start", "--masterkeyFromEnv"]
  }
  
  # Networking - private subnet with ALB access
  subnet_ids          = module.vpc.private_subnet_ids
  assign_public_ip    = false
  target_group_arn    = module.networking.target_group_arns["zitadel"]
  container_port      = 8080
  
  # Use shared ECS tasks security group (RDS allows this SG)
  create_security_group = false
  security_group_ids    = [module.vpc.ecs_tasks_security_group_id]
  
  # IAM roles
  execution_role_arn = module.iam.ecs_task_execution_role_arn
  task_role_arn      = module.iam.ecs_task_role_arn
  
  # Environment variables
  environment = [
    # Note: Login v2 is default in ZITADEL v4, no need to force it
    # {
    #   name  = "ZITADEL_DEFAULTINSTANCE_FEATURES_LOGINV2_REQUIRED"
    #   value = "true"
    # },
    # External domain configuration
    {
      name  = "ZITADEL_EXTERNALDOMAIN"
      value = "auth.${var.domain_name}"
    },
    {
      name  = "ZITADEL_EXTERNALPORT"
      value = "443"
    },
    {
      name  = "ZITADEL_EXTERNALSECURE"
      value = "true"
    },
    # TLS terminated at ALB
    {
      name  = "ZITADEL_TLS_ENABLED"
      value = "false"
    },
    # Database configuration
    {
      name  = "ZITADEL_DATABASE_POSTGRES_HOST"
      value = module.rds.endpoint
    },
    {
      name  = "ZITADEL_DATABASE_POSTGRES_PORT"
      value = "5432"
    },
    {
      name  = "ZITADEL_DATABASE_POSTGRES_DATABASE"
      value = "zitadel"
    },
    {
      name  = "ZITADEL_DATABASE_POSTGRES_USER_USERNAME"
      value = "zitadel"
    },
    {
      name  = "ZITADEL_DATABASE_POSTGRES_ADMIN_USERNAME"
      value = module.rds.username
    },
    {
      name  = "ZITADEL_DATABASE_POSTGRES_ADMIN_SSL_MODE"
      value = "require"
    },
    {
      name  = "ZITADEL_DATABASE_POSTGRES_USER_SSL_MODE"
      value = "require"
    },
    # First instance configuration
    {
      name  = "ZITADEL_FIRSTINSTANCE_ORG_HUMAN_PASSWORDCHANGEREQUIRED"
      value = "false"
    },
    # Bootstrap admin human user (random username + ops email for security)
    {
      name  = "ZITADEL_FIRSTINSTANCE_ORG_HUMAN_USERNAME"
      value = random_string.zitadel_admin_username.result
    },
    {
      name  = "ZITADEL_FIRSTINSTANCE_ORG_HUMAN_EMAIL"
      value = "ops@llmvault.dev"
    },
    {
      name  = "ZITADEL_FIRSTINSTANCE_ORG_HUMAN_PASSWORD"
      value = random_password.zitadel_admin_password.result
    },
    {
      name  = "ZITADEL_FIRSTINSTANCE_ORG_HUMAN_PASSWORDCHANGEREQUIRED"
      value = "false"
    },
    # Bootstrap admin machine user (for API access)
    {
      name  = "ZITADEL_FIRSTINSTANCE_ORG_MACHINE_MACHINE_USERNAME"
      value = "llmvault-admin"
    },
    {
      name  = "ZITADEL_FIRSTINSTANCE_ORG_MACHINE_MACHINE_NAME"
      value = "LLMVault Admin Service Account"
    },
    {
      name  = "ZITADEL_FIRSTINSTANCE_ORG_MACHINE_PAT_EXPIRATIONDATE"
      value = "2099-01-01T00:00:00Z"
    },
    {
      name  = "ZITADEL_FIRSTINSTANCE_PATPATH"
      value = "/tmp/admin.pat"
    }
  ]
  
  # Secrets from Secrets Manager
  secrets = [
    {
      name      = "ZITADEL_MASTERKEY"
      valueFrom = aws_secretsmanager_secret.zitadel_masterkey.arn
    },
    {
      name      = "ZITADEL_DATABASE_POSTGRES_USER_PASSWORD"
      valueFrom = aws_secretsmanager_secret.zitadel_db_password.arn
    },
    {
      name      = "ZITADEL_DATABASE_POSTGRES_ADMIN_PASSWORD"
      valueFrom = "${module.rds.secrets_manager_arn}:password::"
    }
  ]
  
  # Port mapping
  port_mappings = [
    {
      containerPort = 8080
      protocol      = "tcp"
    }
  ]
  
  # Health check
  health_check = {
    command     = ["/app/zitadel", "ready"]
    interval    = 30
    timeout     = 5
    retries     = 3
    startPeriod = 120
  }
  
  # Single instance for cost efficiency
  desired_count = 1
  
  # Auto-scaling disabled for now (can enable later)
  enable_autoscaling = false
  
  depends_on = [
    module.networking,
    module.rds,
    aws_secretsmanager_secret_version.zitadel_masterkey
  ]
}

# Security group rule for ZITADEL - allow ingress from ALB
resource "aws_security_group_rule" "zitadel_alb_ingress" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = module.networking.alb_security_group_id
  security_group_id        = module.vpc.ecs_tasks_security_group_id
  description              = "ZITADEL from ALB"
}
