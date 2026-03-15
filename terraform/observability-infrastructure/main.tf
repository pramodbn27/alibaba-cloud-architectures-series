# Topic 5: Observability Infrastructure - ARMS + SLS
# Complete monitoring, logging, and alerting setup

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
  default     = "observability"
}

variable "alert_email" {
  description = "Email for alerts"
  type        = string
  default     = "alerts@example.com"
}

# ==================== Log Service (SLS) ====================

# Create project
resource "alibabacloud_log_project" "app_logs" {
  name            = "${var.project_name}-project"
  description     = "Central logging for observability"
  region          = var.region
}

# Application logs
resource "alibabacloud_log_store" "app_logstore" {
  project             = alibabacloud_log_project.app_logs.name
  name                = "app-logs"
  retention_period    = 30
  shard_count         = 2
  auto_split          = true
  max_split_shard_count = 10
  append_meta         = true
  enable_web_tracking = true
}

# System/Infrastructure logs
resource "alibabacloud_log_store" "system_logstore" {
  project             = alibabacloud_log_project.app_logs.name
  name                = "system-logs"
  retention_period    = 30
  shard_count         = 1
  auto_split          = false
  append_meta         = true
}

# Security/Audit logs
resource "alibabacloud_log_store" "security_logstore" {
  project             = alibabacloud_log_project.app_logs.name
  name                = "security-logs"
  retention_period    = 90  # Longer retention for security
  shard_count         = 1
  auto_split          = false
  append_meta         = true
}

# ==================== Log Analysis - Machine Learning ====================

# Index configuration for app logs
resource "alibabacloud_log_store_index" "app_index" {
  project           = alibabacloud_log_project.app_logs.name
  logstore          = alibabacloud_log_store.app_logstore.name
  full_text_search  = "on"
  
  field_search {
    name = "trace_id"
    type = "text"
  }

  field_search {
    name = "user_id"
    type = "text"
  }

  field_search {
    name = "response_time_ms"
    type = "long"
  }

  field_search {
    name = "http_status"
    type = "long"
  }

  field_search {
    name = "error_message"
    type = "text"
  }
}

# Dashboard for application metrics
resource "alibabacloud_log_dashboard" "app_dashboard" {
  project      = alibabacloud_log_project.app_logs.name
  dashboard_name = "${var.project_name}-app-dashboard"
  dashboard_body = jsonencode({
    description = "Application performance dashboard"
    displayName = "App Metrics"
    version     = "1.0"
  })
}

# Alert rule - High error rate
resource "alibabacloud_log_alert" "high_error_rate" {
  project           = alibabacloud_log_project.app_logs.name
  alert_name        = "${var.project_name}-high-error-rate"
  alert_description = "Alert when error rate exceeds 5%"
  condition         = "alert_type=1 AND (error_count / total_requests) > 0.05"
  notify_threshold  = 1
  alert_status      = "enabled"

  schedule {
    type = "FixedRate"
    run_every = 5  # Every 5 minutes
  }

  alarm_notify_categories = ["enabled"]
  throttling              = 300  # 5 minute throttle
}

# Alert rule - High latency
resource "alibabacloud_log_alert" "high_latency" {
  project           = alibabacloud_log_project.app_logs.name
  alert_name        = "${var.project_name}-high-latency"
  alert_description = "Alert when p95 latency exceeds 1000ms"
  condition         = "response_time_ms > 1000"
  notify_threshold  = 5  # Trigger after 5 occurrences
  alert_status      = "enabled"

  schedule {
    type = "FixedRate"
    run_every = 10
  }

  alarm_notify_categories = ["enabled"]
  throttling              = 600  # 10 minute throttle
}

# Auto-remediation rule - Restart service
resource "alibabacloud_cms_monitor_group" "service_group" {
  monitor_group_name = "${var.project_name}-service-group"
}

# ==================== Application Real-time Monitoring Service (ARMS) ====================

# Note: ARMS is typically enabled at the application level via SDK
# This Terraform creates the monitoring namespace and policies

# Create namespace for application monitoring
resource "alibabacloud_arms_namespace" "production" {
  namespace_name        = "${var.project_name}-prod"
  cluster_short_name    = "prod"
  namespace_description = "Production monitoring namespace"
}

# Default alert notification channel (email)
resource "alibabacloud_cms_alarm_notify_recipient" "alert_recipient" {
  recipient_name = "${var.project_name}-alerts"
  recipient_email = var.alert_email
}

# ==================== CloudMonitor Dashboards ====================

# System performance dashboard
resource "alibabacloud_cms_group_metric_rule" "cpu_usage" {
  group_id            = alibabacloud_cms_monitor_group.service_group.id
  metric_name         = "CPUUtilization"
  namespace           = "acs:ecs"
  statistic           = "Average"
  period              = "300"
  comparison_operator = "GreaterThanThreshold"
  threshold           = "80"
  evaluation_count    = 2
  enabled             = "true"

  alarm_actions = []
}

resource "alibabacloud_cms_group_metric_rule" "memory_usage" {
  group_id            = alibabacloud_cms_monitor_group.service_group.id
  metric_name         = "MemoryUtilization"
  namespace           = "acs:ecs"
  statistic           = "Average"
  period              = "300"
  comparison_operator = "GreaterThanThreshold"
  threshold           = "90"
  evaluation_count    = 2
  enabled             = "true"

  alarm_actions = []
}

resource "alibabacloud_cms_group_metric_rule" "disk_usage" {
  group_id            = alibabacloud_cms_monitor_group.service_group.id
  metric_name         = "DiskUtilizationPercent"
  namespace           = "acs:ecs"
  statistic           = "Average"
  period              = "300"
  comparison_operator = "GreaterThanThreshold"
  threshold           = "85"
  evaluation_count    = 2
  enabled             = "true"

  alarm_actions = []
}

# Network monitoring
resource "alibabacloud_cms_group_metric_rule" "network_in" {
  group_id            = alibabacloud_cms_monitor_group.service_group.id
  metric_name         = "NetworkIn"
  namespace           = "acs:ecs"
  statistic           = "Sum"
  period              = "60"
  comparison_operator = "GreaterThanThreshold"
  threshold           = "1000000000"  # 1 GB/min
  evaluation_count    = 5
  enabled             = "true"

  alarm_actions = []
}

# ==================== Alerting Policies ====================

# Alert notification group
resource "alibabacloud_cms_alarm_contact_group" "ops_team" {
  alarm_contact_group_name = "${var.project_name}-ops-team"
}

# Add recipient to group
resource "alibabacloud_cms_alarm_contact_group_member" "ops_member" {
  alarm_contact_group_id = alibabacloud_cms_alarm_contact_group.ops_team.id
  alarm_contact_id       = alibabacloud_cms_alarm_notify_recipient.alert_recipient.id
}

# Composite alarm for critical issues
resource "alibabacloud_cms_alarm" "critical_alarm" {
  alarm_name              = "${var.project_name}-critical-alarm"
  alarm_description       = "Composite alarm for critical conditions"
  comparison_operator     = "GreaterThanOrEqualToThreshold"
  metric_name             = "CriticalEventCount"
  namespace               = "acs:businessalarm"
  period                  = "60"
  statistics              = "Sum"
  threshold               = "1"
  alarm_actions           = []
  treat_missing_data      = "breaching"
  enabled                 = true
}

# ==================== Log Anomaly Detection ====================

# Setup log auto-analysis
resource "alibabacloud_log_machine_group" "app_hosts" {
  project             = alibabacloud_log_project.app_logs.name
  group_name          = "${var.project_name}-app-hosts"
  group_type          = "ip"
  group_attribute     = "service=production&team=platform"
  arn                 = "acs:log:*:*:machinegroup/*"
  classification      = "service"

  os_type = "linux"
}

# ==================== Data Export ====================

# Export logs to OSS for long-term storage
resource "alibabacloud_oss_bucket" "log_archive" {
  bucket = "${var.project_name}-logs-archive-${data.alibabacloud_caller_identity.current.account_id}"
  acl    = "private"

  versioning {
    enabled = true
  }

  server_side_encryption_rule {
    sse_algorithm = "AES256"
  }

  lifecycle_rule {
    id      = "transition-to-cold"
    enabled = true

    transition {
      days          = 30
      storage_class = "IA"
    }

    transition {
      days          = 90
      storage_class = "Archive"
    }

    expiration {
      days = 2555  # 7 years for compliance
    }
  }
}

# Log delivery job (monthly)
resource "alibabacloud_log_export_job" "monthly_export" {
  project             = alibabacloud_log_project.app_logs.name
  export_name         = "${var.project_name}-monthly-export"
  from_time           = "1609459200"  # Example start time
  to_time             = "1640995200"  # Example end time
  logstore            = alibabacloud_log_store.app_logstore.name
  ossbucket           = alibabacloud_oss_bucket.log_archive.bucket
  ossprefix           = "logs/monthly/"
  ossrolearn          = alibabacloud_ram_role.logs_export_role.arn
}

# RAM role for log export
resource "alibabacloud_ram_role" "logs_export_role" {
  name       = "${var.project_name}-logs-export-role"
  assume_role_policy = jsonencode({
    Version = "1"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "log.aliyuncs.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "alibabacloud_ram_policy" "logs_export_policy" {
  policy_name = "${var.project_name}-logs-export-policy"
  policy_document = jsonencode({
    Version = "1"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "oss:PutObject",
          "oss:GetBucketLocation"
        ]
        Resource = [
          alibabacloud_oss_bucket.log_archive.arn,
          "${alibabacloud_oss_bucket.log_archive.arn}/*"
        ]
      }
    ]
  })
  policy_type = "Custom"
}

resource "alibabacloud_ram_role_policy_attachment" "export_attach" {
  role_name       = alibabacloud_ram_role.logs_export_role.name
  policy_name     = alibabacloud_ram_policy.logs_export_policy.policy_name
  policy_type     = "Custom"
}

# Data source for current account
data "alibabacloud_caller_identity" "current" {}

# Outputs
output "sls_project" {
  value       = alibabacloud_log_project.app_logs.name
  description = "Log Service project name"
}

output "logstore_names" {
  value = {
    application = alibabacloud_log_store.app_logstore.name
    system      = alibabacloud_log_store.system_logstore.name
    security    = alibabacloud_log_store.security_logstore.name
  }
  description = "Log store names"
}

output "arms_namespace" {
  value       = alibabacloud_arms_namespace.production.namespace_name
  description = "ARMS monitoring namespace"
}

output "monitor_group_id" {
  value       = alibabacloud_cms_monitor_group.service_group.id
  description = "CloudMonitor group ID"
}

output "setup_instructions" {
  value = <<-EOT
    Observability Setup Complete!
    
    1. Send logs to SLS:
       - Application logs to: ${alibabacloud_log_store.app_logstore.name}
       - System logs to: ${alibabacloud_log_store.system_logstore.name}
       
    2. View dashboards:
       - Alibaba Cloud Console > Log Service > ${alibabacloud_log_project.app_logs.name}
       - Look for pre-built templates for your framework
       
    3. Configure ARMS agents:
       - For Java: Add ARMS Java agent JAR
       - For Node.js: npm install apm-nodejs-agent
       - For Python: pip install aliyun-python-sdk-arms
       
    4. Alert recipients:
       - Email configured: ${var.alert_email}
       - Add more recipients in console or Terraform
       
    5. Log retention:
       - Application: 30 days
       - System: 30 days
       - Security: 90 days
       - Archive: 7 years in OSS
       
    6. Monthly costs:
       - SLS: ¥30-80 (depends on log volume)
       - ARMS: ¥100-300 (depends on application metrics)
       - Total: ¥130-380/month
  EOT
}

output "estimated_monthly_cost" {
  value = "¥130-380 (SLS + ARMS + archival storage)"
}
