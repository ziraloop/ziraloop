# =============================================================================
# Outputs - Production Environment (Phase 0)
# =============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = module.vpc.vpc_cidr
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "ecs_cluster_name" {
  description = "ECS Cluster name"
  value       = module.ecs_cluster.cluster_name
}

output "ecs_cluster_arn" {
  description = "ECS Cluster ARN"
  value       = module.ecs_cluster.cluster_arn
}

output "ecr_repository_urls" {
  description = "ECR Repository URLs"
  value       = module.ecr.repository_urls
}

output "ecs_task_execution_role_arn" {
  description = "ECS Task Execution Role ARN"
  value       = module.iam.ecs_task_execution_role_arn
}

output "ecs_task_role_arn" {
  description = "ECS Task Role ARN"
  value       = module.iam.ecs_task_role_arn
}

# =============================================================================
# Phase 1: Database Outputs
# =============================================================================

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = module.rds.endpoint
}

output "rds_port" {
  description = "RDS PostgreSQL port"
  value       = module.rds.port
}

output "rds_db_name" {
  description = "RDS database name"
  value       = module.rds.db_name
}

output "rds_username" {
  description = "RDS master username"
  value       = module.rds.username
}

output "rds_secrets_manager_arn" {
  description = "Secrets Manager ARN for database credentials"
  value       = module.rds.secrets_manager_arn
}

output "rds_security_group_id" {
  description = "RDS Security Group ID"
  value       = module.rds.security_group_id
}

# =============================================================================
# Phase 2: Cache Outputs
# =============================================================================

output "elasticache_endpoint" {
  description = "ElastiCache Redis endpoint"
  value       = module.elasticache.endpoint
}

output "elasticache_port" {
  description = "ElastiCache Redis port"
  value       = module.elasticache.port
}

output "elasticache_redis_url" {
  description = "Redis connection URL"
  value       = module.elasticache.redis_url
}

output "elasticache_security_group_id" {
  description = "ElastiCache Security Group ID"
  value       = module.elasticache.security_group_id
}

# =============================================================================
# Phase 3: Networking Outputs
# =============================================================================

output "alb_arn" {
  description = "Application Load Balancer ARN"
  value       = module.networking.alb_arn
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = module.networking.alb_dns_name
}

output "alb_zone_id" {
  description = "Application Load Balancer Zone ID"
  value       = module.networking.alb_zone_id
}

output "alb_security_group_id" {
  description = "ALB Security Group ID"
  value       = module.networking.alb_security_group_id
}

output "target_group_arns" {
  description = "Target Group ARNs by service"
  value       = module.networking.target_group_arns
}

output "nat_gateway_public_ip" {
  description = "NAT Gateway Public IP"
  value       = module.networking.nat_gateway_public_ip
}

output "acm_certificate_arn" {
  description = "ACM SSL Certificate ARN"
  value       = module.networking.acm_certificate_arn
}

output "acm_certificate_validation_records" {
  description = "DNS validation CNAME records to add in Cloudflare"
  value       = module.networking.acm_certificate_domain_validation_options
}

output "vpc_endpoint_ids" {
  description = "VPC Endpoint IDs"
  value       = module.networking.vpc_endpoint_ids
}

# =============================================================================
# Phase 4: ZITADEL Outputs
# =============================================================================

output "zitadel_service_name" {
  description = "ZITADEL ECS Service name"
  value       = module.zitadel_service.service_name
}

output "zitadel_masterkey_secret_arn" {
  description = "ZITADEL Master Key Secret ARN"
  value       = aws_secretsmanager_secret.zitadel_masterkey.arn
}

output "zitadel_db_password_secret_arn" {
  description = "ZITADEL DB Password Secret ARN"
  value       = aws_secretsmanager_secret.zitadel_db_password.arn
}

output "zitadel_admin_username_secret_arn" {
  description = "ZITADEL Admin Username Secret ARN"
  value       = aws_secretsmanager_secret.zitadel_admin_username.arn
}

output "zitadel_admin_password_secret_arn" {
  description = "ZITADEL Admin Password Secret ARN"
  value       = aws_secretsmanager_secret.zitadel_admin_password.arn
}

output "zitadel_admin_pat_path" {
  description = "Path where ZITADEL admin PAT is written"
  value       = "/tmp/admin.pat"
}

output "zitadel_setup_instructions" {
  description = "Post-deployment ZITADEL setup steps"
  value       = <<-EOF
    
    ============================================
    ZITADEL SETUP INSTRUCTIONS
    ============================================
    
    1. ZITADEL is deploying with Login v2 enabled
       URL: https://auth.llmvault.dev
    
    2. Wait for service to be healthy (~2-3 minutes):
       aws ecs describe-services --cluster llmvault-prod --services zitadel
    
    3. Access the admin PAT (Personal Access Token):
       kubectl exec -it <zitadel-pod> -- cat /zitadel-bootstrap/admin.pat
       OR check CloudWatch logs for bootstrap output
    
    4. Admin login credentials (retrieve from Secrets Manager):
       - Username: aws secretsmanager get-secret-value --secret-id llmvault-prod/zitadel-admin-username --query SecretString --output text
       - Email: ops@llmvault.dev
       - Password: aws secretsmanager get-secret-value --secret-id llmvault-prod/zitadel-admin-password --query SecretString --output text
    
    5. Configure your application in ZITADEL Console:
       - Create a new project
       - Add an application (OIDC)
       - Set redirect URLs to include:
         * https://llmvault.dev/api/auth/callback/zitadel
         * https://api.llmvault.dev/auth/callback
    
    6. IMPORTANT - OAuth Redirect URL Change for Login v2:
       Old (v1): https://auth.llmvault.dev/oauth/v2/callback
       New (v2): https://auth.llmvault.dev/idps/callback
       
       Update your OAuth apps (Google, GitHub, etc.) with the new URL!
    
    ============================================
  EOF
}

# =============================================================================
# Post-Deployment Cloudflare Configuration
# =============================================================================

output "cloudflare_setup_instructions" {
  description = "Manual steps required in Cloudflare"
  value       = <<-EOF
    
    ============================================
    CLOUDFLARE DNS CONFIGURATION REQUIRED
    ============================================
    
    1. Certificate Validation (CNAME records):
       Add these CNAME records in Cloudflare to validate the ACM certificate:
       (Run 'terraform output acm_certificate_validation_records' to get values)
    
    2. Application DNS (CNAME or ALIAS records):
       Add A/ALIAS or CNAME records pointing to the ALB:
       
       Type    Name              Target
       ─────────────────────────────────────────────────────────
       CNAME   llmvault.dev      ${module.networking.alb_dns_name}
       CNAME   auth              ${module.networking.alb_dns_name}
       CNAME   api               ${module.networking.alb_dns_name}
       CNAME   connect           ${module.networking.alb_dns_name}
       CNAME   proxy             ${module.networking.alb_dns_name}
       
       Or use ALIAS records (if Cloudflare supports it):
       ALIAS   llmvault.dev      ${module.networking.alb_dns_name}
       ALIAS   auth.llmvault.dev ${module.networking.alb_dns_name}
       ALIAS   api.llmvault.dev  ${module.networking.alb_dns_name}
       ALIAS   connect.llmvault.dev ${module.networking.alb_dns_name}
       ALIAS   proxy.llmvault.dev   ${module.networking.alb_dns_name}
    
    3. SSL/TLS Setting in Cloudflare:
       - Set SSL/TLS mode to "Full (strict)"
       - Enable "Always Use HTTPS"
    
    ============================================
  EOF
}
