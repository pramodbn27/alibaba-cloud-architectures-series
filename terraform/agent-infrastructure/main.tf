# Topic 6: Agent-Native Infrastructure - GPU Instances for AI Workloads
# High-performance infrastructure for LLM agents, inference, and model training

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
  default     = "agent-infrastructure"
}

variable "gpu_instance_count" {
  description = "Number of GPU instances for inference"
  type        = number
  default     = 2
}

variable "training_instance_count" {
  description = "Number of instances for parallel training"
  type        = number
  default     = 1
}

# ==================== Networking ====================

# VPC for AI agents
resource "alibabacloud_vpc" "agent_vpc" {
  vpc_name   = "${var.project_name}-vpc"
  cidr_block = "10.10.0.0/16"
}

# Inference cluster subnet
resource "alibabacloud_vswitch" "inference_subnet" {
  vpc_id       = alibabacloud_vpc.agent_vpc.id
  cidr_block   = "10.10.1.0/24"
  zone_id      = data.alibabacloud_zones.gpu_zones.zones[0].id
  vswitch_name = "${var.project_name}-inference"
}

# Training cluster subnet
resource "alibabacloud_vswitch" "training_subnet" {
  vpc_id       = alibabacloud_vpc.agent_vpc.id
  cidr_block   = "10.10.2.0/24"
  zone_id      = data.alibabacloud_zones.gpu_zones.zones[1].id
  vswitch_name = "${var.project_name}-training"
}

# Data source for GPU-available zones
data "alibabacloud_zones" "gpu_zones" {
  available_resource_creation = "Instance"
  instance_charge_type        = "PostPaid"
}

# Security group for AI workloads
resource "alibabacloud_security_group" "agent_sg" {
  name        = "${var.project_name}-sg"
  vpc_id      = alibabacloud_vpc.agent_vpc.id
  description = "Security group for AI agents and GPU workloads"
}

# Allow model serving port (typically 8000)
resource "alibabacloud_security_group_rule" "allow_model_serving" {
  type              = "ingress"
  ip_protocol       = "tcp"
  port_range        = "8000/8000"
  cidr_ip           = "10.10.0.0/16"  # Internal VPC only
  security_group_id = alibabacloud_security_group.agent_sg.id
}

# Allow JupyterLab for development
resource "alibabacloud_security_group_rule" "allow_jupyter" {
  type              = "ingress"
  ip_protocol       = "tcp"
  port_range        = "8888/8888"
  cidr_ip           = "10.10.0.0/16"
  security_group_id = alibabacloud_security_group.agent_sg.id
}

# Allow TensorFlow distributed training ports
resource "alibabacloud_security_group_rule" "allow_tf_ps" {
  type              = "ingress"
  ip_protocol       = "tcp"
  port_range        = "2222/2222"
  cidr_ip           = "10.10.0.0/16"
  security_group_id = alibabacloud_security_group.agent_sg.id
}

# Allow internal communication
resource "alibabacloud_security_group_rule" "allow_internal" {
  type              = "ingress"
  ip_protocol       = "all"
  port_range        = "-1/-1"
  cidr_ip           = "10.10.0.0/16"
  security_group_id = alibabacloud_security_group.agent_sg.id
}

# ==================== GPU Inference Cluster ====================

# Launch template for inference nodes (T4 GPUs optimal for inference)
resource "alibabacloud_launch_template" "inference_template" {
  name            = "${var.project_name}-inference-template"
  image_id        = data.alibabacloud_images.gpu_image.images[0].id
  instance_type   = "ecs.gn7i-c8g1.2xlarge"  # 8 vCPU, 32GB RAM, 1x Tesla T4 GPU
  security_groups = [alibabacloud_security_group.agent_sg.id]
  vswitch_id      = alibabacloud_vswitch.inference_subnet.id

  system_disk_category = "cloud_essd"
  system_disk_size     = 200  # Larger disk for model weights

  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y \
      python3-pip \
      cuda-toolkit-12-0 \
      nvidia-driver-525
    
    pip3 install --upgrade pip
    pip3 install \
      torch torchvision torchaudio \
      transformers \
      vLLM \
      fastapi \
      uvicorn \
      dashscope \
      pydantic
    
    # Setup NVIDIA container runtime
    apt-get install -y nvidia-container-toolkit
    
    echo "GPU inference node ready"
  EOF
  )

  data_disks {
    size                 = 500  # Large storage for model cache
    category             = "cloud_essd"
    delete_with_instance = true
  }

  tags = {
    Service = "inference"
  }
}

# Get GPU image
data "alibabacloud_images" "gpu_image" {
  owners      = "system"
  name_regex  = "ubuntu_22.*gpu"
  most_recent = true
}

# Inference auto-scaling group
resource "alibabacloud_autoscaling_group" "inference_asg" {
  scaling_group_name       = "${var.project_name}-inference-asg"
  launch_template_id       = alibabacloud_launch_template.inference_template.id
  min_size                 = 1
  max_size                 = 5
  desired_capacity         = var.gpu_instance_count
  vswitch_ids              = [alibabacloud_vswitch.inference_subnet.id]
  default_cooldown         = 300
  health_check_type        = "ECS"
  health_check_period      = 300
  multi_az_policy          = "COST_OPTIMIZED"
  on_demand_base_capacity  = 1  # Run at least 1 on-demand
  on_demand_percentage_above_base_capacity = 20  # Use 20% on-demand, rest spot
}

# Scaling policy for inference - based on CPU
resource "alibabacloud_autoscaling_schedule" "inference_scale_up" {
  scalable_id           = alibabacloud_autoscaling_group.inference_asg.id
  scheduled_action_name = "scale-up-high-inference-load"
  adjustment_type       = "PercentChangeInCapacity"
  adjustment_value      = 50
  recurrence            = "* * * * * *"
}

# ==================== Training Cluster (High-memory GPUs) ====================

# Launch template for training (A100 preferred for training, but V100 for cost)
resource "alibabacloud_launch_template" "training_template" {
  name            = "${var.project_name}-training-template"
  image_id        = data.alibabacloud_images.gpu_image.images[0].id
  instance_type   = "ecs.gn7-c12g1.3xlarge"  # 12 vCPU, 48GB RAM, 1x Tesla V100 (16GB)
  security_groups = [alibabacloud_security_group.agent_sg.id]
  vswitch_id      = alibabacloud_vswitch.training_subnet.id

  system_disk_category = "cloud_essd"
  system_disk_size     = 200

  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y \
      python3-pip \
      cuda-toolkit-12-0 \
      nvidia-driver-525 \
      nccl-2.15.2-1+cuda12.0 \
      openmpi-bin
    
    pip3 install --upgrade pip
    pip3 install \
      torch==2.0.1+cu118 \
      torchvision \
      pytorch-lightning \
      transformers \
      accelerate \
      datasets \
      tensorboard
    
    echo "GPU training node ready"
  EOF
  )

  data_disks {
    size                 = 1000  # Very large storage for training data
    category             = "cloud_essd"
    delete_with_instance = true
  }

  tags = {
    Service = "training"
  }
}

# Training cluster (smaller, more expensive)
resource "alibabacloud_autoscaling_group" "training_asg" {
  scaling_group_name = "${var.project_name}-training-asg"
  launch_template_id = alibabacloud_launch_template.training_template.id
  min_size           = 0
  max_size           = 3
  desired_capacity   = var.training_instance_count
  vswitch_ids        = [alibabacloud_vswitch.training_subnet.id]
  default_cooldown   = 300
  health_check_type  = "ECS"
  health_check_period = 300
}

# ==================== Model Repository ====================

# OSS bucket for model artifacts
resource "alibabacloud_oss_bucket" "model_repository" {
  bucket = "${var.project_name}-models-${data.alibabacloud_caller_identity.current.account_id}"
  acl    = "private"
  region = var.region

  versioning {
    enabled = true
  }

  server_side_encryption_rule {
    sse_algorithm = "AES256"
  }

  # Keep last 5 versions, archive older ones
  lifecycle_rule {
    id      = "version-management"
    enabled = true

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# ==================== Monitoring ====================

# Dedicated monitor group for GPU resources
resource "alibabacloud_cms_monitor_group" "gpu_group" {
  monitor_group_name = "${var.project_name}-gpu-group"
}

# GPU Utilization alarm
resource "alibabacloud_cms_alarm" "gpu_utilization" {
  name                = "${var.project_name}-gpu-util-alarm"
  comparison_operator = "GreaterThanThreshold"
  metric_name         = "GPUUtilization"
  namespace           = "acs:ecs"
  period              = "300"
  statistics          = "Average"
  threshold           = "95"
  alarm_actions       = []
}

# GPU Memory alarm
resource "alibabacloud_cms_alarm" "gpu_memory" {
  name                = "${var.project_name}-gpu-memory-alarm"
  comparison_operator = "GreaterThanThreshold"
  metric_name         = "GPUMemoryUtilization"
  namespace           = "acs:ecs"
  period              = "300"
  statistics          = "Average"
  threshold           = "90"
  alarm_actions       = []
}

# High temperature alarm
resource "alibabacloud_cms_alarm" "gpu_temperature" {
  name                = "${var.project_name}-gpu-temp-alarm"
  comparison_operator = "GreaterThanThreshold"
  metric_name         = "GPUTemperature"
  namespace           = "acs:ecs"
  period              = "60"
  statistics          = "Maximum"
  threshold           = "85"  # Celsius
  alarm_actions       = []
}

# ==================== IAM for Agent Services ====================

resource "alibabacloud_ram_role" "agent_role" {
  name       = "${var.project_name}-agent-role"
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

resource "alibabacloud_ram_policy" "agent_policy" {
  policy_name = "${var.project_name}-agent-policy"
  policy_document = jsonencode({
    Version = "1"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "oss:GetObject",
          "oss:PutObject",
          "oss:ListBucket"
        ]
        Resource = [
          alibabacloud_oss_bucket.model_repository.arn,
          "${alibabacloud_oss_bucket.model_repository.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dashscope:*"  # For Qwen API access
        ]
        Resource = "*"
      }
    ]
  })
  policy_type = "Custom"
}

resource "alibabacloud_ram_role_policy_attachment" "agent_attach" {
  role_name       = alibabacloud_ram_role.agent_role.name
  policy_name     = alibabacloud_ram_policy.agent_policy.policy_name
  policy_type     = "Custom"
}

# Data source for current account
data "alibabacloud_caller_identity" "current" {}

# Outputs
output "inference_asg_id" {
  value       = alibabacloud_autoscaling_group.inference_asg.id
  description = "Inference cluster auto-scaling group ID"
}

output "training_asg_id" {
  value       = alibabacloud_autoscaling_group.training_asg.id
  description = "Training cluster auto-scaling group ID"
}

output "model_repository_bucket" {
  value       = alibabacloud_oss_bucket.model_repository.bucket
  description = "Model repository bucket name"
}

output "infer_instance_types" {
  value = "ecs.gn7i-c8g1.2xlarge (T4 GPU) - ¥12-15/hour"
}

output "training_instance_types" {
  value = "ecs.gn7-c12g1.3xlarge (V100 GPU) - ¥18-22/hour"
}

output "cost_estimation" {
  value = <<-EOT
    Inference Setup (2 T4 instances):
    - Base cost: ¥600-900/month (20% on-demand, 80% spot)
    - OSS storage: ¥50-100/month
    - Total: ¥650-1000/month
    
    Training Setup (1 V100 instance, on-demand):
    - Per hour: ¥18-22
    - 100 hours/month: ¥1800-2200/month
    - Full training cluster (3 max): ¥5400-6600/month
  EOT
}

output "setup_instructions" {
  value = <<-EOT
    Agent Infrastructure Setup Complete!
    
    1. Inference Setup:
       - Instances auto-scale from 1-5 based on load
       - Model serving on port 8000 with vLLM
       - Deploy: docker pull vllm:latest && vllm serve modelo
    
    2. Training Setup:
       - Manual or scheduled training jobs
       - NVIDIA NCCL for multi-GPU communication
       - Distributed training with PyTorch Lightning
    
    3. Model Management:
       - Upload models to: ${alibabacloud_oss_bucket.model_repository.bucket}
       - Versioning enabled (keep last 5)
       - Archive older versions automatically
    
    4. Agent Development:
       - Python SDK: pip install alibaba-cloud-python-sdk
       - Use role: ${alibabacloud_ram_role.agent_role.name}
       - Access Qwen API via DashScope
    
    5. Recommended Setup:
       - 2 T4 instances for inference (¥12-15/hour each)
       - 1 V100 for development/small training (¥18-22/hour)
       - Total daily cost: ¥288-576 for continuous operation
  EOT
}
