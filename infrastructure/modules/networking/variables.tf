# =============================================================================
# Networking Module Variables
# =============================================================================

variable "name" {
  description = "Name prefix for resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-2"
}

variable "domain_name" {
  description = "Primary domain name"
  type        = string
}

variable "enable_https_listener" {
  description = "Enable HTTPS listener (requires valid ACM certificate)"
  type        = bool
  default     = false  # Set to true after Cloudflare DNS validation
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for ALB"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for VPC Endpoints"
  type        = list(string)
}

variable "public_route_table_ids" {
  description = "Public route table IDs (for S3 endpoint)"
  type        = list(string)
}

variable "private_route_table_ids" {
  description = "Private route table IDs (for NAT Gateway and S3 endpoint)"
  type        = list(string)
}

variable "internet_gateway_id" {
  description = "Internet Gateway ID (for NAT Gateway dependency)"
  type        = string
}

variable "vpc_endpoint_security_group_id" {
  description = "Security group ID for VPC Endpoints"
  type        = string
}

variable "services" {
  description = "List of service names for target groups"
  type        = list(string)
  default     = ["api", "web", "zitadel", "connect"]
}
