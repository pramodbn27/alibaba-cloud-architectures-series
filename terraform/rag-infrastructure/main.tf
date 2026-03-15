# Topic 2: RAG Pipeline Infrastructure - Qwen + Hologres
# This module sets up the complete RAG pipeline with vector database and compute

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
  default     = "rag-pipeline"
}

variable "hologres_admin_username" {
  description = "Hologres admin username"
  type        = string
  default     = "admin"
}

variable "hologres_admin_password" {
  description = "Hologres admin password"
  type        = string
  sensitive   = true
}

# VPC for RAG infrastructure
resource "alibabacloud_vpc" "rag_vpc" {
  vpc_name   = "${var.project_name}-vpc"
  cidr_block = "172.16.0.0/16"
}

# VSwitches in multiple AZs
data "alibabacloud_zones" "available" {
  available_resource_creation = "Hologres"
}

resource "alibabacloud_vswitch" "rag_vswitch_1" {
  vpc_id       = alibabacloud_vpc.rag_vpc.id
  cidr_block   = "172.16.1.0/24"
  zone_id      = data.alibabacloud_zones.available.zones[0].id
  vswitch_name = "${var.project_name}-vs-1"
}

resource "alibabacloud_vswitch" "rag_vswitch_2" {
  vpc_id       = alibabacloud_vpc.rag_vpc.id
  cidr_block   = "172.16.2.0/24"
  zone_id      = data.alibabacloud_zones.available.zones[1].id
  vswitch_name = "${var.project_name}-vs-2"
}

# Security group for RAG services
resource "alibabacloud_security_group" "rag_sg" {
  name        = "${var.project_name}-sg"
  vpc_id      = alibabacloud_vpc.rag_vpc.id
  description = "Security group for RAG pipeline"
}

# Allow inbound PostgreSQL for Hologres
resource "alibabacloud_security_group_rule" "allow_hologres" {
  type              = "ingress"
  ip_protocol       = "tcp"
  port_range        = "5432/5432"
  cidr_ip           = "172.16.0.0/16"
  security_group_id = alibabacloud_security_group.rag_sg.id
}

# Allow outbound to Qwen API
resource "alibabacloud_security_group_rule" "allow_qwen_api" {
  type              = "egress"
  ip_protocol       = "tcp"
  port_range        = "443/443"
  cidr_ip           = "0.0.0.0/0"
  security_group_id = alibabacloud_security_group.rag_sg.id
}

# Hologres Instance - Vector Database
resource "alibabacloud_hologres_instance" "rag_hologres" {
  instance_name       = "${var.project_name}-hologres"
  zone_id             = data.alibabacloud_zones.available.zones[0].id
  instance_type       = "hs.2xlarge"  # 8 CPU, 64GB RAM - suitable for small-medium deployments
  vswitch_id          = alibabacloud_vswitch.rag_vswitch_1.id
  user_name           = var.hologres_admin_username
  user_password       = var.hologres_admin_password
  enable_ha           = true
  payment_type        = "PayAsYouGo"
  enable_storage_unit = true

  tags = {
    Environment = "production"
    Service     = "rag-pipeline"
  }
}

# Hologres Database
resource "alibabacloud_hologres_database" "rag_db" {
  instance_id = alibabacloud_hologres_instance.rag_hologres.id
  db_name     = "rag_database"
}

# ECS Instance for application (Python client)
resource "alibabacloud_instance" "rag_compute" {
  instance_name        = "${var.project_name}-compute"
  image_id             = data.alibabacloud_images.ubuntu.images[0].id
  instance_type        = "ecs.n7.xlarge"  # 4 vCPU, 16 GiB RAM
  vswitch_id           = alibabacloud_vswitch.rag_vswitch_1.id
  security_groups      = [alibabacloud_security_group.rag_sg.id]
  system_disk_category = "cloud_essd"
  system_disk_size     = 100

  internet_charge_type       = "PayByTraffic"
  internet_max_bandwidth_out = 5

  instance_charge_type = "PostPaid"

  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y python3-pip
    pip3 install psycopg2-binary dashscope numpy pandas
    echo "RAG Pipeline compute node ready"
  EOF
  )

  tags = {
    Name = "${var.project_name}-compute"
  }
}

# Data source for Ubuntu images
data "alibabacloud_images" "ubuntu" {
  owners      = "system"
  name_regex  = "ubuntu_22"
  most_recent = true
}

# OSS Bucket for document storage
resource "alibabacloud_oss_bucket" "rag_documents" {
  bucket = "${var.project_name}-documents-${data.alibabacloud_caller_identity.current.account_id}"
  acl    = "private"
  region = var.region

  versioning {
    enabled = true
  }

  server_side_encryption_rule {
    sse_algorithm = "AES256"
  }

  lifecycle_rule {
    id     = "archive-old-documents"
    prefix = "archive/"
    enabled = true

    transition {
      days          = 90
      storage_class = "Archive"
    }
  }

  tags = {
    Service = "rag-documents"
  }
}

# Data source for current account
data "alibabacloud_caller_identity" "current" {}

# RAM Role for RAG application
resource "alibabacloud_ram_role" "rag_role" {
  name       = "${var.project_name}-role"
  assume_role_policy = jsonencode({
    Version = "1"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs.aliyuncs.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Policy for Hologres access
resource "alibabacloud_ram_policy" "rag_hologres_policy" {
  policy_name = "${var.project_name}-hologres-policy"
  policy_document = jsonencode({
    Version = "1"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "hologres:Query",
          "hologres:Insert",
          "hologres:Update",
          "hologres:Delete"
        ]
        Resource = alibabacloud_hologres_instance.rag_hologres.arn
      },
      {
        Effect = "Allow"
        Action = [
          "oss:GetObject",
          "oss:ListBucket"
        ]
        Resource = [
          alibabacloud_oss_bucket.rag_documents.arn,
          "${alibabacloud_oss_bucket.rag_documents.arn}/*"
        ]
      }
    ]
  })
  policy_type = "Custom"
}

# Attach policy to role
resource "alibabacloud_ram_role_policy_attachment" "rag_hologres_attach" {
  role_name       = alibabacloud_ram_role.rag_role.name
  policy_name     = alibabacloud_ram_policy.rag_hologres_policy.policy_name
  policy_type     = "Custom"
}

# CloudMonitor Alarm for Hologres CPU
resource "alibabacloud_cms_alarm" "hologres_cpu" {
  name                = "${var.project_name}-hologres-cpu-alarm"
  comparison_operator = "GreaterThanThreshold"
  metric_name         = "CPU"
  namespace           = "acs:hologres"
  period              = "300"
  statistics          = "Average"
  threshold           = "80"
  alarm_actions       = []
}

# Outputs
output "hologres_connection_string" {
  value       = "postgresql://${var.hologres_admin_username}:${var.hologres_admin_password}@${alibabacloud_hologres_instance.rag_hologres.connection_string}:5432/rag_database"
  description = "Hologres connection string"
  sensitive   = true
}

output "hologres_public_endpoint" {
  value       = alibabacloud_hologres_instance.rag_hologres.public_connection_string
  description = "Hologres public endpoint (if available)"
}

output "compute_instance_id" {
  value       = alibabacloud_instance.rag_compute.id
  description = "ECS compute instance ID"
}

output "compute_private_ip" {
  value       = alibabacloud_instance.rag_compute.private_ip
  description = "ECS compute instance private IP"
}

output "document_bucket" {
  value       = alibabacloud_oss_bucket.rag_documents.bucket
  description = "OSS bucket for documents"
}

output "setup_cost_estimate" {
  value = "Monthly cost: ~¥800-1200 (Hologres: ¥600-800, ECS: ¥150-300, OSS: ¥50-100)"
}
