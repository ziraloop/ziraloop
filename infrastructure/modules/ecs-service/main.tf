# =============================================================================
# ECS Service Module - Reusable Fargate Service
# =============================================================================

locals {
  common_tags = {
    Module = "ecs-service"
  }
  
  # Container definition with defaults
  # Note: cpu and memory must be integers in the JSON
  container_definition = merge({
    name  = var.name
    image = var.image
    
    cpu    = tonumber(var.cpu)
    memory = tonumber(var.memory)
    
    essential = true
    
    environment = var.environment
    secrets     = var.secrets
    
    portMappings = var.port_mappings
    
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/${var.cluster_name}/${var.name}"
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = var.name
      }
    }
    
    healthCheck = var.health_check
    
    mountPoints  = var.mount_points
    volumesFrom  = []
    
    ulimits = []
  }, var.container_overrides)
}

# -----------------------------------------------------------------------------
# Security Group for Service
# -----------------------------------------------------------------------------
resource "aws_security_group" "service" {
  count = var.create_security_group ? 1 : 0
  
  name_prefix = "${var.cluster_name}-${var.name}-"
  description = "Security group for ${var.name} service"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      description     = ingress.value.description
      from_port       = ingress.value.from_port
      to_port         = ingress.value.to_port
      protocol        = ingress.value.protocol
      security_groups = lookup(ingress.value, "security_groups", [])
      cidr_blocks     = lookup(ingress.value, "cidr_blocks", [])
    }
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-${var.name}"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# -----------------------------------------------------------------------------
# ECS Task Definition
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "main" {
  family                   = "${var.cluster_name}-${var.name}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  
  cpu    = var.cpu
  memory = var.memory
  
  execution_role_arn = var.execution_role_arn
  task_role_arn      = var.task_role_arn
  
  container_definitions = jsonencode([local.container_definition])
  
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }
  
  tags = merge(local.common_tags, {
    Name = var.name
  })
}

# -----------------------------------------------------------------------------
# ECS Service
# -----------------------------------------------------------------------------
resource "aws_ecs_service" "main" {
  name            = var.name
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
  
  platform_version = "LATEST"
  
  # Deployment configuration
  deployment_maximum_percent         = var.deployment_max_percent
  deployment_minimum_healthy_percent = var.deployment_min_healthy_percent
  
  deployment_controller {
    type = "ECS"
  }
  
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  
  # Network configuration
  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.create_security_group ? [aws_security_group.service[0].id] : var.security_group_ids
    assign_public_ip = var.assign_public_ip
  }
  
  # Load balancer configuration (optional)
  dynamic "load_balancer" {
    for_each = var.target_group_arn != null ? [1] : []
    content {
      target_group_arn = var.target_group_arn
      container_name   = var.name
      container_port   = var.container_port
    }
  }
  
  # Service discovery (optional)
  dynamic "service_registries" {
    for_each = var.service_discovery_arn != null ? [1] : []
    content {
      registry_arn = var.service_discovery_arn
    }
  }
  
  # Don't replace tasks on every apply
  propagate_tags = "SERVICE"
  
  tags = merge(local.common_tags, {
    Name = var.name
  })
  
  depends_on = [aws_ecs_task_definition.main]
}

# -----------------------------------------------------------------------------
# Auto Scaling (Optional)
# -----------------------------------------------------------------------------
resource "aws_appautoscaling_target" "main" {
  count = var.enable_autoscaling ? 1 : 0
  
  max_capacity       = var.autoscaling_max
  min_capacity       = var.autoscaling_min
  resource_id        = "service/${var.cluster_name}/${var.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  count = var.enable_autoscaling ? 1 : 0
  
  name               = "${var.cluster_name}-${var.name}-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.main[0].resource_id
  scalable_dimension = aws_appautoscaling_target.main[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.main[0].service_namespace
  
  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.autoscaling_target_cpu
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms (Optional)
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  count = var.enable_monitoring ? 1 : 0
  
  alarm_name          = "${var.cluster_name}-${var.name}-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors CPU utilization for ${var.name}"
  
  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = var.name
  }
  
  alarm_actions = var.alarm_actions
}
