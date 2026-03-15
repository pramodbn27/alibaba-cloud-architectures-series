# Terraform: Serverless Event-Driven Pipeline

terraform {
  required_providers {
    alibabacloud = {
      source  = "aliyun/alibabacloud"
      version = "~> 1.205"
    }
  }
}

provider "alibabacloud" {
  region = var.region
}

variable "region" {
  default = "cn-beijing"
}

# IAM Role for Function Compute
resource "alibabacloud_ram_role" "fc_role" {
  name               = "fc-pipeline-role"
  assume_role_policy = jsonencode({
    Version = "1"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "fc.aliyuncs.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Policy for OSS access
resource "alibabacloud_ram_policy" "oss_policy" {
  policy_name = "fc-oss-policy"
  policy_document = jsonencode({
    Version = "1"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "oss:GetObject",
          "oss:PutObject"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "alibabacloud_ram_role_policy_attachment" "fc_policy" {
  role_name      = alibabacloud_ram_role.fc_role.name
  policy_name    = alibabacloud_ram_policy.oss_policy.policy_name
  policy_type    = "Custom"
}

# OSS Bucket for input
resource "alibabacloud_oss_bucket" "input" {
  bucket = "pipeline-input-${data.alibabacloud_account.current.id}"
  acl    = "private"
}

# OSS Bucket for output
resource "alibabacloud_oss_bucket" "output" {
  bucket = "pipeline-output-${data.alibabacloud_account.current.id}"
  acl    = "private"
}

# Data source for account ID
data "alibabacloud_account" "current" {}

# Function Compute Service
resource "alibabacloud_fc_service" "pipeline" {
  name             = "image-processor"
  description      = "Image processing pipeline"
  role             = alibabacloud_ram_role.fc_role.arn
  
  environment_variables = {
    INPUT_BUCKET  = alibabacloud_oss_bucket.input.id
    OUTPUT_BUCKET = alibabacloud_oss_bucket.output.id
  }
}

# Function: Image Processor
resource "alibabacloud_fc_function" "image_processor" {
  service_name  = alibabacloud_fc_service.pipeline.name
  function_name = "resize-image"
  filename      = "function.zip"  # Package your function code
  handler       = "index.handler"
  runtime       = "python3.9"
  memory_size   = 512
  timeout       = 60
  
  environment_variables = {
    LOG_LEVEL = "INFO"
  }
}

# OSS Trigger
resource "alibabacloud_fc_trigger" "oss_trigger" {
  service_name  = alibabacloud_fc_service.pipeline.name
  function_name = alibabacloud_fc_function.image_processor.function_name
  name          = "oss-trigger"
  type          = "oss"
  
  config = jsonencode({
    bucketName = alibabacloud_oss_bucket.input.id
    events     = ["oss:ObjectCreated:*"]
    filter = {
      key = {
        filterRules = [
          {
            name  = "prefix"
            value = "uploads/"
          },
          {
            name  = "suffix"
            value = ".jpg"
          }
        ]
      }
    }
  })
}

# Timer Trigger (cron job)
resource "alibabacloud_fc_trigger" "timer_trigger" {
  service_name  = alibabacloud_fc_service.pipeline.name
  function_name = alibabacloud_fc_function.image_processor.function_name
  name          = "daily-report"
  type          = "timer"
  config        = "cron(0 2 * * ?)"  # 2 AM daily
}

# Outputs
output "service_name" {
  value = alibabacloud_fc_service.pipeline.name
}

output "function_name" {
  value = alibabacloud_fc_function.image_processor.function_name
}

output "input_bucket" {
  value = alibabacloud_oss_bucket.input.id
}

output "output_bucket" {
  value = alibabacloud_oss_bucket.output.id
}
