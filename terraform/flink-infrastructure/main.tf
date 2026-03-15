# Topic 3: Stream Processing Infrastructure - Flink + Hologres + Kafka
# Real-time analytics pipeline with message streaming

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
  default     = "flink-streaming"
}

variable "kafka_admin_password" {
  description = "Kafka admin password"
  type        = string
  sensitive   = true
  default     = "ChangeMe@123"
}

# VPC for streaming infrastructure
resource "alibabacloud_vpc" "flink_vpc" {
  vpc_name   = "${var.project_name}-vpc"
  cidr_block = "10.100.0.0/16"
}

# VSwitches in multiple AZs
data "alibabacloud_zones" "flink_zones" {
  available_resource_creation = "Kafka"
}

resource "alibabacloud_vswitch" "flink_vswitch_1" {
  vpc_id       = alibabacloud_vpc.flink_vpc.id
  cidr_block   = "10.100.1.0/24"
  zone_id      = data.alibabacloud_zones.flink_zones.zones[0].id
  vswitch_name = "${var.project_name}-vs-1"
}

resource "alibabacloud_vswitch" "flink_vswitch_2" {
  vpc_id       = alibabacloud_vpc.flink_vpc.id
  cidr_block   = "10.100.2.0/24"
  zone_id      = data.alibabacloud_zones.flink_zones.zones[1].id
  vswitch_name = "${var.project_name}-vs-2"
}

# Security group
resource "alibabacloud_security_group" "flink_sg" {
  name        = "${var.project_name}-sg"
  vpc_id      = alibabacloud_vpc.flink_vpc.id
  description = "Security group for Flink streaming"
}

# Allow Kafka broker communication
resource "alibabacloud_security_group_rule" "allow_kafka" {
  type              = "ingress"
  ip_protocol       = "tcp"
  port_range        = "9092/9092"
  cidr_ip           = "10.100.0.0/16"
  security_group_id = alibabacloud_security_group.flink_sg.id
}

resource "alibabacloud_security_group_rule" "allow_zookeeper" {
  type              = "ingress"
  ip_protocol       = "tcp"
  port_range        = "2181/2181"
  cidr_ip           = "10.100.0.0/16"
  security_group_id = alibabacloud_security_group.flink_sg.id
}

# Kafka Instance (Message Queue for Kafka)
resource "alibabacloud_alikafka_instance" "streaming_kafka" {
  instance_name = "${var.project_name}-kafka"
  topic_quota   = 50
  disk_type     = "1"  # SSD
  disk_size     = 1024  # 1TB
  deploy_type   = "5"   # Multi-AZ
  eip_max       = "true"
  
  config = {
    enable_acl = "false"
  }

  vswitch_id = alibabacloud_vswitch.flink_vswitch_1.id
}

# Create first topic for events
resource "alibabacloud_alikafka_topic" "events_topic" {
  instance_id = alibabacloud_alikafka_instance.streaming_kafka.id
  topic       = "events"
  local_topic = "false"
  partition   = 10
}

# Create output topic for results
resource "alibabacloud_alikafka_topic" "results_topic" {
  instance_id = alibabacloud_alikafka_instance.streaming_kafka.id
  topic       = "results"
  local_topic = "false"
  partition   = 5
}

# ECS Cluster for Flink JobManager
resource "alibabacloud_instance" "flink_jobmanager" {
  instance_name        = "${var.project_name}-jobmanager"
  image_id             = data.alibabacloud_images.ubuntu.images[0].id
  instance_type        = "ecs.n7.2xlarge"  # 8 vCPU, 32 GiB RAM - JobManager needs more resources
  vswitch_id           = alibabacloud_vswitch.flink_vswitch_1.id
  security_groups      = [alibabacloud_security_group.flink_sg.id]
  system_disk_category = "cloud_essd"
  system_disk_size     = 100

  internet_charge_type       = "PayByTraffic"
  internet_max_bandwidth_out = 10

  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y openjdk-11-jdk wget
    cd /opt
    wget -q https://archive.apache.org/dist/flink/flink-1.15.4/flink-1.15.4-bin-scala_2.12.tgz
    tar -xzf flink-1.15.4-bin-scala_2.12.tgz
    mv flink-1.15.4 flink
    echo "Flink JobManager setup complete"
  EOF
  )

  tags = {
    Name = "${var.project_name}-jobmanager"
  }
}

# ECS Instances for Flink TaskManagers (cluster)
resource "alibabacloud_launch_template" "flink_tm_template" {
  name            = "${var.project_name}-tm-template"
  image_id        = data.alibabacloud_images.ubuntu.images[0].id
  instance_type   = "ecs.n7.xlarge"  # 4 vCPU, 16 GiB RAM per TaskManager
  security_groups = [alibabacloud_security_group.flink_sg.id]
  vswitch_id      = alibabacloud_vswitch.flink_vswitch_1.id

  system_disk_category = "cloud_essd"
  system_disk_size     = 100

  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y openjdk-11-jdk wget
    cd /opt
    wget -q https://archive.apache.org/dist/flink/flink-1.15.4/flink-1.15.4-bin-scala_2.12.tgz
    tar -xzf flink-1.15.4-bin-scala_2.12.tgz
    mv flink-1.15.4 flink
  EOF
  )
}

# Auto-scaling group for TaskManagers
resource "alibabacloud_autoscaling_group" "flink_taskmanagers" {
  scaling_group_name       = "${var.project_name}-task-managers"
  launch_template_id       = alibabacloud_launch_template.flink_tm_template.id
  min_size                 = 2
  max_size                 = 10
  desired_capacity         = 3
  vswitch_ids              = [alibabacloud_vswitch.flink_vswitch_1.id, alibabacloud_vswitch.flink_vswitch_2.id]
  multi_az_policy          = "COST_OPTIMIZED"
  default_cooldown         = 300
  health_check_type        = "ECS"
  health_check_period      = 300
}

# Data source for Ubuntu images
data "alibabacloud_images" "ubuntu" {
  owners      = "system"
  name_regex  = "ubuntu_22"
  most_recent = true
}

# Scaling policy for CPU-based scaling
resource "alibabacloud_autoscaling_scalable" "flink_scalable" {
  autoscaling_group_id = alibabacloud_autoscaling_group.flink_taskmanagers.id
  
  max_size       = 10
  min_size       = 2
  scaling_min_0  = 2
  scaling_max_10 = 10
}

resource "alibabacloud_autoscaling_schedule" "flink_scale_up_rule" {
  scalable_id           = alibabacloud_autoscaling_scalable.flink_scalable.id
  scheduled_action_name = "scale-up-high-load"
  adjustment_type       = "PercentChangeInCapacity"
  adjustment_value      = 50
  recurrence            = "* * * * * *"
  metric_alarm          = "CPU"
  metric_alarm_period   = 300
  metric_alarm_statistic = "Average"
  metric_alarm_operator = "GreaterThanThreshold"
  metric_alarm_threshold = 70
}

# RAM Role for Flink and Kafka
resource "alibabacloud_ram_role" "flink_kafka_role" {
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

resource "alibabacloud_ram_policy" "flink_kafka_policy" {
  policy_name = "${var.project_name}-kafka-policy"
  policy_document = jsonencode({
    Version = "1"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kafka:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "monitoring:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
  policy_type = "Custom"
}

resource "alibabacloud_ram_role_policy_attachment" "flink_kafka_attach" {
  role_name       = alibabacloud_ram_role.flink_kafka_role.name
  policy_name     = alibabacloud_ram_policy.flink_kafka_policy.policy_name
  policy_type     = "Custom"
}

# CloudMonitor Alarms for Kafka
resource "alibabacloud_cms_alarm" "kafka_cpu" {
  name                = "${var.project_name}-kafka-cpu-alarm"
  comparison_operator = "GreaterThanThreshold"
  metric_name         = "CPU"
  namespace           = "acs:alikafka"
  period              = "300"
  statistics          = "Average"
  threshold           = "80"
  alarm_actions       = []
}

resource "alibabacloud_cms_alarm" "kafka_disk" {
  name                = "${var.project_name}-kafka-disk-alarm"
  comparison_operator = "GreaterThanThreshold"
  metric_name         = "DiskUtilizationPercent"
  namespace           = "acs:alikafka"
  period              = "300"
  statistics          = "Average"
  threshold           = "85"
  alarm_actions       = []
}

# Outputs
output "kafka_brokers" {
  value       = alibabacloud_alikafka_instance.streaming_kafka.broker_node_ids
  description = "Kafka broker node IDs"
}

output "kafka_bootstrap_servers" {
  value       = alibabacloud_alikafka_instance.streaming_kafka.endpoints[0].endpoint
  description = "Kafka bootstrap servers"
}

output "flink_jobmanager_ip" {
  value       = alibabacloud_instance.flink_jobmanager.private_ip
  description = "Flink JobManager private IP"
}

output "flink_taskmanager_asg_id" {
  value       = alibabacloud_autoscaling_group.flink_taskmanagers.id
  description = "Flink TaskManager auto-scaling group ID"
}

output "monthly_cost_estimate" {
  value = "Estimated: ¥900-1300 (Kafka: ¥500-700, JobManager: ¥200-250, TaskManagers: ¥200-350)"
}
