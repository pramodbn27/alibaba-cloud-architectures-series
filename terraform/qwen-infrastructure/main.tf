# Topic 1: Qwen API Setup Infrastructure
# This module configures DashScope API access and integrations with other Alibaba Cloud services

terraform {
  required_version = ">= 1.0"
  required_providers {
    alibabacloud = {
      source  = "aliyun/alibabacloud"
      version = "~> 1.200"
    }
  }
}

provider "alibabacloud" {
  region = var.region
}

# Variables
variable "region" {
  description = "Alibaba Cloud region"
  type        = string
  default     = "cn-beijing"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "qwen-api-setup"
}

variable "dashscope_api_key" {
  description = "DashScope API Key (store in .tfvars)"
  type        = string
  sensitive   = true
}

# RAM Policy for DashScope API Access
resource "alibabacloud_ram_policy" "qwen_access" {
  policy_name     = "${var.project_name}-dashscope-access"
  policy_document = jsonencode({
    Version = "1"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dashscope:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "monitoring:PutMetricData",
          "actiontrail:LookupEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# RAM User for API Access
resource "alibabacloud_ram_user" "qwen_user" {
  name = "${var.project_name}-api-user"
}

# Attach policy to user
resource "alibabacloud_ram_user_policy_attachment" "qwen_user_policy" {
  policy_name = alibabacloud_ram_policy.qwen_access.policy_name
  user_name   = alibabacloud_ram_user.qwen_user.name
  policy_type = "Custom"
}

# Access Key for programmatic access
resource "alibabacloud_ram_access_key" "qwen_user_key" {
  user_name = alibabacloud_ram_user.qwen_user.name
}

# VPC for Qwen client applications (if needed)
resource "alibabacloud_vpc" "qwen_vpc" {
  vpc_name   = "${var.project_name}-vpc"
  cidr_block = "10.0.0.0/16"
}

# VSwitch in primary AZ
resource "alibabacloud_vswitch" "qwen_vswitch" {
  vpc_id       = alibabacloud_vpc.qwen_vpc.id
  cidr_block   = "10.0.1.0/24"
  zone_id      = data.alibabacloud_zones.available_zones.zones[0].id
  vswitch_name = "${var.project_name}-vswitch"
}

# Data source for available zones
data "alibabacloud_zones" "available_zones" {
  available_resource_creation = "VSwitch"
}

# Security Group for Qwen client services
resource "alibabacloud_security_group" "qwen_sg" {
  name        = "${var.project_name}-sg"
  description = "Security group for Qwen API client services"
  vpc_id      = alibabacloud_vpc.qwen_vpc.id
}

# Allow outbound HTTPS for API calls
resource "alibabacloud_security_group_rule" "allow_https_out" {
  type              = "egress"
  ip_protocol       = "tcp"
  port_range        = "443/443"
  cidr_ip           = "0.0.0.0/0"
  security_group_id = alibabacloud_security_group.qwen_sg.id
}

# CloudMonitor Alarm for API Rate Limits
resource "alibabacloud_cms_alarm" "qwen_api_limit_alarm" {
  name               = "${var.project_name}-rate-limit-alarm"
  comparison_operator = "GreaterThanThreshold"
  metric_name        = "HTTPStatusCode5xx"
  namespace          = "acs:dashscope"
  period             = "300"
  statistics         = "Average"
  threshold          = "10"
  alarm_actions      = []
  treat_missing_data = "NotBreaching"
}

# Outputs
output "vpc_id" {
  value       = alibabacloud_vpc.qwen_vpc.id
  description = "VPC ID for Qwen client services"
}

output "vswitch_id" {
  value       = alibabacloud_vswitch.qwen_vswitch.id
  description = "VSwitch ID"
}

output "security_group_id" {
  value       = alibabacloud_security_group.qwen_sg.id
  description = "Security Group ID for Qwen services"
}

output "ram_user_name" {
  value       = alibabacloud_ram_user.qwen_user.name
  description = "RAM User for DashScope API access"
}

output "access_key_id" {
  value       = alibabacloud_ram_access_key.qwen_user_key.id
  description = "Access Key ID for programmatic access"
  sensitive   = true
}

output "access_key_secret" {
  value       = alibabacloud_ram_access_key.qwen_user_key.secret
  description = "Access Key Secret - store securely"
  sensitive   = true
}

output "setup_instructions" {
  value = <<-EOT
    Qwen API Setup Complete!
    
    1. Configure DashScope API:
       - Add API key to environment: export DASHSCOPE_API_KEY='your-key'
       - Or add to Python: import os; os.environ['DASHSCOPE_API_KEY'] = 'your-key'
    
    2. Test connection with qwen_client.py:
       python3 -c "from code.qwen_client import QwenClient; qc = QwenClient(); print(qc.chat('Hello'))"
    
    3. Monitor API usage:
       - CloudMonitor: Alibaba Cloud Console > CloudMonitor
       - Set up budgets to track costs
    
    4. Cost tracking:
       - Qwen pricing: ¥0.0008-0.018 per 1K tokens
       - Setup cost alerts in CloudMonitor
  EOT
}
