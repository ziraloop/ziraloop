# =============================================================================
# Networking Module - ALB, NAT Gateway, VPC Endpoints
# =============================================================================

locals {
  common_tags = {
    Module = "networking"
  }
}

# =============================================================================
# NAT Gateway (for private subnet internet access)
# =============================================================================

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.name}-nat-eip"
  })

  depends_on = [var.internet_gateway_id]
}

# NAT Gateway (single AZ to save cost, can add second for HA)
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = var.public_subnet_ids[0]  # Place in first public subnet

  tags = merge(local.common_tags, {
    Name = "${var.name}-nat"
  })

  depends_on = [var.internet_gateway_id]
}

# Update private route tables to use NAT Gateway
resource "aws_route" "private_nat" {
  count = length(var.private_route_table_ids)

  route_table_id         = var.private_route_table_ids[count.index]
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

# =============================================================================
# Application Load Balancer
# =============================================================================

# Security Group for ALB
resource "aws_security_group" "alb" {
  name_prefix = "${var.name}-alb-"
  description = "Security group for ${var.name} ALB"
  vpc_id      = var.vpc_id

  # HTTP - redirect to HTTPS
  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS
  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound to ECS tasks
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.name}-alb"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false
  enable_http2               = true

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    prefix  = "alb-logs"
    enabled = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.name}-alb"
  })
}

# S3 Bucket for ALB Access Logs
resource "aws_s3_bucket" "alb_logs" {
  bucket_prefix = "${var.name}-alb-logs-"

  tags = local.common_tags
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowALBAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::033677994240:root"  # ELB account for us-east-2
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs.arn}/alb-logs/*"
      },
      {
        Sid    = "AllowALBRootAccess"
        Effect = "Allow"
        Principal = {
          Service = "logdelivery.elasticloadbalancing.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_logs.arn}/alb-logs/*"
      }
    ]
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {
      prefix = "alb-logs/"
    }

    expiration {
      days = 7  # Short retention to save cost
    }
  }
}

# =============================================================================
# Target Groups (one per service)
# =============================================================================

resource "aws_lb_target_group" "services" {
  for_each = toset(var.services)

  name        = "${var.name}-${each.value}"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"  # Fargate uses IP targets

  # Health check
  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/healthz"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
  }

  deregistration_delay = 30  # Fast deregistration for quicker deploys

  tags = merge(local.common_tags, {
    Name = "${var.name}-${each.value}"
    Service = each.value
  })
}

# =============================================================================
# HTTPS Listener (ACM Certificate)
# =============================================================================

# ACM Certificate - DNS validation (manual via Cloudflare)
# Explicit subdomains only - NO wildcard for flexibility
resource "aws_acm_certificate" "main" {
  domain_name = var.domain_name
  subject_alternative_names = [
    var.domain_name,              # Root domain (llmvault.dev)
    "auth.${var.domain_name}",
    "api.${var.domain_name}",
    "connect.${var.domain_name}",
    "proxy.${var.domain_name}"
  ]
  validation_method = "DNS"

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

# Output the DNS validation records for Cloudflare
# User must manually add these CNAME records in Cloudflare
# Certificate validation will happen automatically once DNS propagates

# =============================================================================
# HTTPS Listener (Created after certificate validation)
# =============================================================================

# HTTPS Listener - Will fail until certificate is validated via Cloudflare DNS
# You can comment this out initially and apply after adding DNS records
resource "aws_lb_listener" "https" {
  count = var.enable_https_listener ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.main.arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "OK"
      status_code  = "200"
    }
  }
}

# HTTP Listener (fallback when HTTPS is not yet available)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  # If HTTPS is enabled, redirect to it. Otherwise, return OK.
  default_action {
    type = var.enable_https_listener ? "redirect" : "fixed-response"
    
    dynamic "redirect" {
      for_each = var.enable_https_listener ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
    
    dynamic "fixed_response" {
      for_each = var.enable_https_listener ? [] : [1]
      content {
        content_type = "text/plain"
        message_body = "OK - HTTP mode (HTTPS pending certificate validation)"
        status_code  = "200"
      }
    }
  }
}

# =============================================================================
# Host-based Routing Rules
# =============================================================================

# =============================================================================
# HTTPS Listener Rules (Only created when HTTPS is enabled)
# =============================================================================

locals {
  # Use HTTPS listener if enabled, otherwise HTTP
  listener_arn = var.enable_https_listener ? aws_lb_listener.https[0].arn : aws_lb_listener.http.arn
}

# auth.llmvault.dev -> ZITADEL
resource "aws_lb_listener_rule" "zitadel" {
  count = var.enable_https_listener ? 1 : 0

  listener_arn = local.listener_arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.services["zitadel"].arn
  }

  condition {
    host_header {
      values = ["auth.${var.domain_name}"]
    }
  }
}

# api.llmvault.dev -> API
resource "aws_lb_listener_rule" "api" {
  count = var.enable_https_listener ? 1 : 0

  listener_arn = local.listener_arn
  priority     = 110

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.services["api"].arn
  }

  condition {
    host_header {
      values = ["api.${var.domain_name}"]
    }
  }
}

# proxy.llmvault.dev -> API (for LLM proxy endpoint)
resource "aws_lb_listener_rule" "proxy" {
  count = var.enable_https_listener ? 1 : 0

  listener_arn = local.listener_arn
  priority     = 115

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.services["api"].arn
  }

  condition {
    host_header {
      values = ["proxy.${var.domain_name}"]
    }
  }
}

# connect.llmvault.dev -> Connect
resource "aws_lb_listener_rule" "connect" {
  count = var.enable_https_listener ? 1 : 0

  listener_arn = local.listener_arn
  priority     = 120

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.services["connect"].arn
  }

  condition {
    host_header {
      values = ["connect.${var.domain_name}"]
    }
  }
}

# llmvault.dev (root) -> Web
# NOTE: If you want www.llmvault.dev, add it to the certificate SANs above
resource "aws_lb_listener_rule" "web" {
  count = var.enable_https_listener ? 1 : 0

  listener_arn = local.listener_arn
  priority     = 130

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.services["web"].arn
  }

  condition {
    host_header {
      values = [var.domain_name]
    }
  }
}

# =============================================================================
# VPC Endpoints (reduce NAT Gateway data transfer costs)
# =============================================================================

# ECR API Endpoint
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [var.vpc_endpoint_security_group_id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.name}-ecr-api"
  })
}

# ECR DKR Endpoint (for Docker image pulls)
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [var.vpc_endpoint_security_group_id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.name}-ecr-dkr"
  })
}

# CloudWatch Logs Endpoint
resource "aws_vpc_endpoint" "cloudwatch_logs" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [var.vpc_endpoint_security_group_id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.name}-cloudwatch-logs"
  })
}

# Secrets Manager Endpoint
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [var.vpc_endpoint_security_group_id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.name}-secretsmanager"
  })
}

# S3 Gateway Endpoint (for ALB logs, free)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat(var.public_route_table_ids, var.private_route_table_ids)

  tags = merge(local.common_tags, {
    Name = "${var.name}-s3"
  })
}
