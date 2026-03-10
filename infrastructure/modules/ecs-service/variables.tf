# =============================================================================
# ECS Service Module Variables
# =============================================================================

variable "name" {
  description = "Service name"
  type        = string
}

variable "cluster_id" {
  description = "ECS Cluster ID"
  type        = string
}

variable "cluster_name" {
  description = "ECS Cluster name (for CloudWatch logs)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for security group"
  type        = string
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-2"
}

# -----------------------------------------------------------------------------
# Task Definition
# -----------------------------------------------------------------------------
variable "image" {
  description = "Container image URL"
  type        = string
}

variable "cpu" {
  description = "CPU units (256 = 0.25 vCPU)"
  type        = string
  default     = "256"
}

variable "memory" {
  description = "Memory in MB (512 = 0.5 GB)"
  type        = string
  default     = "512"
}

variable "cpu_architecture" {
  description = "CPU architecture (X86_64 or ARM64)"
  type        = string
  default     = "ARM64"
}

variable "environment" {
  description = "Environment variables"
  type        = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "secrets" {
  description = "Secrets from Secrets Manager"
  type        = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "port_mappings" {
  description = "Container port mappings"
  type        = list(object({
    containerPort = number
    hostPort      = optional(number)
    protocol      = optional(string, "tcp")
  }))
  default = []
}

variable "health_check" {
  description = "Container health check"
  type        = object({
    command     = list(string)
    interval    = optional(number, 30)
    timeout     = optional(number, 5)
    retries     = optional(number, 3)
    startPeriod = optional(number, 60)
  })
  default = null
}

variable "mount_points" {
  description = "Container mount points"
  type        = list(any)
  default     = []
}

variable "container_overrides" {
  description = "Additional container definition overrides"
  type        = any
  default     = {}
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------
variable "subnet_ids" {
  description = "Subnet IDs for service placement"
  type        = list(string)
}

variable "create_security_group" {
  description = "Create a security group for this service"
  type        = bool
  default     = true
}

variable "security_group_ids" {
  description = "Existing security group IDs (if not creating)"
  type        = list(string)
  default     = []
}

variable "ingress_rules" {
  description = "Ingress rules for security group"
  type        = list(object({
    description     = string
    from_port       = number
    to_port         = number
    protocol        = string
    security_groups = optional(list(string), [])
    cidr_blocks     = optional(list(string), [])
  }))
  default = []
}

variable "assign_public_ip" {
  description = "Assign public IP to tasks"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Service Configuration
# -----------------------------------------------------------------------------
variable "desired_count" {
  description = "Number of tasks to run"
  type        = number
  default     = 1
}

variable "deployment_max_percent" {
  description = "Maximum percent of tasks during deployment"
  type        = number
  default     = 200
}

variable "deployment_min_healthy_percent" {
  description = "Minimum healthy percent during deployment"
  type        = number
  default     = 100
}

# -----------------------------------------------------------------------------
# Load Balancer
# -----------------------------------------------------------------------------
variable "target_group_arn" {
  description = "Target group ARN for ALB attachment"
  type        = string
  default     = null
}

variable "container_port" {
  description = "Container port for ALB target group"
  type        = number
  default     = 8080
}

# -----------------------------------------------------------------------------
# IAM
# -----------------------------------------------------------------------------
variable "execution_role_arn" {
  description = "ECS Task Execution Role ARN"
  type        = string
}

variable "task_role_arn" {
  description = "ECS Task Role ARN"
  type        = string
}

# -----------------------------------------------------------------------------
# Service Discovery
# -----------------------------------------------------------------------------
variable "service_discovery_arn" {
  description = "Service Discovery registry ARN"
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Auto Scaling
# -----------------------------------------------------------------------------
variable "enable_autoscaling" {
  description = "Enable auto scaling"
  type        = bool
  default     = false
}

variable "autoscaling_min" {
  description = "Minimum task count"
  type        = number
  default     = 1
}

variable "autoscaling_max" {
  description = "Maximum task count"
  type        = number
  default     = 2
}

variable "autoscaling_target_cpu" {
  description = "Target CPU utilization for scaling"
  type        = number
  default     = 70
}

# -----------------------------------------------------------------------------
# Monitoring
# -----------------------------------------------------------------------------
variable "enable_monitoring" {
  description = "Enable CloudWatch alarms"
  type        = bool
  default     = false
}

variable "alarm_actions" {
  description = "SNS topics for alarms"
  type        = list(string)
  default     = []
}
