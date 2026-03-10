# =============================================================================
# Networking Module Outputs
# =============================================================================

output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.main.arn
}

output "alb_dns_name" {
  description = "ALB DNS name (for Cloudflare CNAME)"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "ALB Zone ID (for Cloudflare ALIAS)"
  value       = aws_lb.main.zone_id
}

output "alb_security_group_id" {
  description = "ALB Security Group ID"
  value       = aws_security_group.alb.id
}

output "https_listener_arn" {
  description = "HTTPS Listener ARN (null if not enabled)"
  value       = var.enable_https_listener ? aws_lb_listener.https[0].arn : null
}

output "target_group_arns" {
  description = "Map of service name to target group ARN"
  value       = { for name, tg in aws_lb_target_group.services : name => tg.arn }
}

output "nat_gateway_id" {
  description = "NAT Gateway ID"
  value       = aws_nat_gateway.main.id
}

output "nat_gateway_public_ip" {
  description = "NAT Gateway Elastic IP"
  value       = aws_eip.nat.public_ip
}

output "acm_certificate_arn" {
  description = "ACM Certificate ARN"
  value       = aws_acm_certificate.main.arn
}

output "acm_certificate_domain_validation_options" {
  description = "DNS validation records to add in Cloudflare"
  value       = aws_acm_certificate.main.domain_validation_options
}

output "vpc_endpoint_ids" {
  description = "Map of VPC Endpoint IDs"
  value = {
    ecr_api         = aws_vpc_endpoint.ecr_api.id
    ecr_dkr         = aws_vpc_endpoint.ecr_dkr.id
    cloudwatch_logs = aws_vpc_endpoint.cloudwatch_logs.id
    secretsmanager  = aws_vpc_endpoint.secretsmanager.id
    s3              = aws_vpc_endpoint.s3.id
  }
}
