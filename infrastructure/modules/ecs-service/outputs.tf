# =============================================================================
# ECS Service Module Outputs
# =============================================================================

output "service_name" {
  description = "ECS Service name"
  value       = aws_ecs_service.main.name
}

output "service_arn" {
  description = "ECS Service ARN"
  value       = aws_ecs_service.main.id
}

output "task_definition_arn" {
  description = "Task Definition ARN"
  value       = aws_ecs_task_definition.main.arn
}

output "task_definition_family" {
  description = "Task Definition family"
  value       = aws_ecs_task_definition.main.family
}

output "security_group_id" {
  description = "Security Group ID (if created)"
  value       = var.create_security_group ? aws_security_group.service[0].id : null
}

output "autoscaling_target_id" {
  description = "Auto Scaling target ID (if enabled)"
  value       = var.enable_autoscaling ? aws_appautoscaling_target.main[0].id : null
}
