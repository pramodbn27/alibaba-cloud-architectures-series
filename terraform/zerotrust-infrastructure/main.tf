# Topic 4: Zero Trust Architecture Infrastructure
# Implements principle of least privilege with network segmentation and IAM policies

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
  default     = "zerotrust-architecture"
}

variable "admin_cidr_blocks" {
  description = "CIDR blocks allowed for admin access (whitelist your IP)"
  type        = list(string)
  default     = ["203.0.113.0/24"]  # Replace with your actual IP
}

# VPC with restrictive foundation
resource "alibabacloud_vpc" "zerotrust_vpc" {
  vpc_name   = "${var.project_name}-vpc"
  cidr_block = "10.0.0.0/16"
  description = "Zero Trust architecture - default deny all"
}

# Public subnet (DMZ layer)
resource "alibabacloud_vswitch" "public_subnet" {
  vpc_id       = alibabacloud_vpc.zerotrust_vpc.id
  cidr_block   = "10.0.1.0/24"
  zone_id      = data.alibabacloud_zones.available.zones[0].id
  vswitch_name = "${var.project_name}-public"
}

# Private subnet (application layer)
resource "alibabacloud_vswitch" "private_subnet" {
  vpc_id       = alibabacloud_vpc.zerotrust_vpc.id
  cidr_block   = "10.0.2.0/24"
  zone_id      = data.alibabacloud_zones.available.zones[0].id
  vswitch_name = "${var.project_name}-private"
}

# Data layer subnet (database)
resource "alibabacloud_vswitch" "data_subnet" {
  vpc_id       = alibabacloud_vpc.zerotrust_vpc.id
  cidr_block   = "10.0.3.0/24"
  zone_id      = data.alibabacloud_zones.available.zones[1].id
  vswitch_name = "${var.project_name}-data"
}

# Data source for zones
data "alibabacloud_zones" "available" {
  available_resource_creation = "VSwitch"
}

# ==================== Security Groups - Default Deny All ====================

# DMZ Security Group - Only HTTP/HTTPS inbound
resource "alibabacloud_security_group" "dmz_sg" {
  name        = "${var.project_name}-dmz-sg"
  description = "DMZ layer - HTTP/HTTPS only"
  vpc_id      = alibabacloud_vpc.zerotrust_vpc.id
}

resource "alibabacloud_security_group_rule" "dmz_http" {
  type              = "ingress"
  ip_protocol       = "tcp"
  port_range        = "80/80"
  cidr_ip           = "0.0.0.0/0"
  security_group_id = alibabacloud_security_group.dmz_sg.id
  description       = "HTTP public access"
}

resource "alibabacloud_security_group_rule" "dmz_https" {
  type              = "ingress"
  ip_protocol       = "tcp"
  port_range        = "443/443"
  cidr_ip           = "0.0.0.0/0"
  security_group_id = alibabacloud_security_group.dmz_sg.id
  description       = "HTTPS public access"
}

resource "alibabacloud_security_group_rule" "dmz_to_app" {
  type                     = "egress"
  ip_protocol              = "tcp"
  port_range               = "8080/8080"
  destination_security_group_id = alibabacloud_security_group.app_sg.id
  security_group_id        = alibabacloud_security_group.dmz_sg.id
  description              = "To application layer"
}

# Application Security Group - Restricted internal access
resource "alibabacloud_security_group" "app_sg" {
  name        = "${var.project_name}-app-sg"
  description = "Application layer - restricted access"
  vpc_id      = alibabacloud_vpc.zerotrust_vpc.id
}

resource "alibabacloud_security_group_rule" "app_from_dmz" {
  type              = "ingress"
  ip_protocol       = "tcp"
  port_range        = "8080/8080"
  source_security_group_id = alibabacloud_security_group.dmz_sg.id
  security_group_id = alibabacloud_security_group.app_sg.id
  description       = "From DMZ only"
}

resource "alibabacloud_security_group_rule" "app_to_data" {
  type                     = "egress"
  ip_protocol              = "tcp"
  port_range               = "5432/5432"
  destination_security_group_id = alibabacloud_security_group.data_sg.id
  security_group_id        = alibabacloud_security_group.app_sg.id
  description              = "To database layer"
}

resource "alibabacloud_security_group_rule" "app_deny_all_else" {
  type              = "egress"
  ip_protocol       = "all"
  port_range        = "-1/-1"
  cidr_ip           = "0.0.0.0/0"
  security_group_id = alibabacloud_security_group.app_sg.id
  description       = "Default deny all"
}

# Database Security Group - Only from app layer
resource "alibabacloud_security_group" "data_sg" {
  name        = "${var.project_name}-data-sg"
  description = "Data layer - application access only"
  vpc_id      = alibabacloud_vpc.zerotrust_vpc.id
}

resource "alibabacloud_security_group_rule" "data_from_app" {
  type                     = "ingress"
  ip_protocol              = "tcp"
  port_range               = "5432/5432"
  source_security_group_id = alibabacloud_security_group.app_sg.id
  security_group_id        = alibabacloud_security_group.data_sg.id
  description              = "From application layer only"
}

# ==================== IAM - Least Privilege ====================

# Admin Role - Full access (requires MFA)
resource "alibabacloud_ram_role" "admin_role" {
  name       = "${var.project_name}-admin-role"
  description = "Administrator role - requires MFA"
  assume_role_policy = jsonencode({
    Version = "1"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          RAM = "arn:acs:ram::${data.alibabacloud_caller_identity.current.account_id}:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          Bool = {
            "aws:MultiFactorAuthPresent" = "true"
          }
        }
      }
    ]
  })
}

# Admin policy
resource "alibabacloud_ram_policy" "admin_policy" {
  policy_name = "${var.project_name}-admin-policy"
  policy_document = jsonencode({
    Version = "1"
    Statement = [
      {
        Effect = "Allow"
        Action = "*"
        Resource = "*"
      }
    ]
  })
  policy_type = "Custom"
}

resource "alibabacloud_ram_role_policy_attachment" "admin_attach" {
  role_name       = alibabacloud_ram_role.admin_role.name
  policy_name     = alibabacloud_ram_policy.admin_policy.policy_name
  policy_type     = "Custom"
}

# Developer Role - Limited to specific resources
resource "alibabacloud_ram_role" "developer_role" {
  name       = "${var.project_name}-developer-role"
  assume_role_policy = jsonencode({
    Version = "1"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          RAM = "arn:acs:ram::${data.alibabacloud_caller_identity.current.account_id}:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Developer policy - Read-only + limited write
resource "alibabacloud_ram_policy" "developer_policy" {
  policy_name = "${var.project_name}-developer-policy"
  policy_document = jsonencode({
    Version = "1"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:Describe*",
          "rds:Describe*",
          "vpc:Describe*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:Start*",
          "ecs:Stop*"
        ]
        Resource = "arn:acs:ecs:*:*:instance/i-*"
      },
      {
        Effect = "Allow"
        Action = [
          "actiontrail:LookupEvents"
        ]
        Resource = "*"
      }
    ]
  })
  policy_type = "Custom"
}

resource "alibabacloud_ram_role_policy_attachment" "developer_attach" {
  role_name       = alibabacloud_ram_role.developer_role.name
  policy_name     = alibabacloud_ram_policy.developer_policy.policy_name
  policy_type     = "Custom"
}

# Read-Only Viewer Role
resource "alibabacloud_ram_role" "viewer_role" {
  name       = "${var.project_name}-viewer-role"
  assume_role_policy = jsonencode({
    Version = "1"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          RAM = "arn:acs:ram::${data.alibabacloud_caller_identity.current.account_id}:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "alibabacloud_ram_policy" "viewer_policy" {
  policy_name = "${var.project_name}-viewer-policy"
  policy_document = jsonencode({
    Version = "1"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:Describe*",
          "rds:Describe*",
          "vpc:Describe*",
          "oss:GetBucketLocation",
          "oss:ListBucket"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudmonitor:QueryMetricData"
        ]
        Resource = "*"
      }
    ]
  })
  policy_type = "Custom"
}

resource "alibabacloud_ram_role_policy_attachment" "viewer_attach" {
  role_name       = alibabacloud_ram_role.viewer_role.name
  policy_name     = alibabacloud_ram_policy.viewer_policy.policy_name
  policy_type     = "Custom"
}

# Data source for current account
data "alibabacloud_caller_identity" "current" {}

# ==================== Monitoring & Audit ====================

# ActionTrail for audit logs
resource "alibabacloud_action_trail" "zerotrust_trail" {
  name           = "${var.project_name}-audit-trail"
  s3_bucket_name = alibabacloud_oss_bucket.audit_logs.bucket
  is_multi_region_trail = true
  include_global_service_events = true
  enable_log_file_validation = true
  status = "on"
}

# OSS bucket for audit logs
resource "alibabacloud_oss_bucket" "audit_logs" {
  bucket = "${var.project_name}-audit-logs-${data.alibabacloud_caller_identity.current.account_id}"
  acl    = "private"

  server_side_encryption_rule {
    sse_algorithm = "AES256"
  }

  versioning {
    enabled = true
  }

  lifecycle_rule {
    id      = "archive-old-logs"
    enabled = true
    prefix  = "logs/"

    transition {
      days          = 90
      storage_class = "Archive"
    }

    expiration {
      days = 365
    }
  }
}

# CloudMonitor Alarms for security
resource "alibabacloud_cms_alarm" "unauthorized_api_calls" {
  name                = "${var.project_name}-unauthorized-api-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  metric_name         = "UnauthorizedAPICallsEventCount"
  namespace           = "acs:actiontrail"
  period              = "300"
  statistics          = "Sum"
  threshold           = "1"
  alarm_actions       = []
}

# Outputs
output "vpc_id" {
  value       = alibabacloud_vpc.zerotrust_vpc.id
  description = "Zero Trust VPC ID"
}

output "security_groups" {
  value = {
    dmz  = alibabacloud_security_group.dmz_sg.id
    app  = alibabacloud_security_group.app_sg.id
    data = alibabacloud_security_group.data_sg.id
  }
  description = "Security group IDs by layer"
}

output "iam_roles" {
  value = {
    admin      = alibabacloud_ram_role.admin_role.arn
    developer  = alibabacloud_ram_role.developer_role.arn
    viewer     = alibabacloud_ram_role.viewer_role.arn
  }
  description = "IAM role ARNs for zero trust"
}

output "audit_bucket" {
  value       = alibabacloud_oss_bucket.audit_logs.bucket
  description = "Audit logs bucket"
}

output "implementation_cost" {
  value = "Minimal cost: ~¥20-50/month (mostly audit logs in OSS)"
}
