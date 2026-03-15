# Terraform: Auto-scaling Web App (ECS + SLB + RDS)

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

# Variables
variable "region" {
  default = "cn-beijing"
}

variable "az_list" {
  type    = list(string)
  default = ["cn-beijing-a", "cn-beijing-b"]
}

# VPC and Network
resource "alibabacloud_vpc" "main" {
  vpc_name   = "web-app-vpc"
  cidr_block = "172.16.0.0/16"
}

resource "alibabacloud_vswitch" "vswitches" {
  count             = length(var.az_list)
  vpc_id            = alibabacloud_vpc.main.id
  cidr_block        = "172.16.${count.index + 1}.0/24"
  availability_zone = var.az_list[count.index]
  vswitch_name      = "web-app-vsw-${count.index}"
}

# Security Group
resource "alibabacloud_security_group" "app_sg" {
  name        = "web-app-sg"
  vpc_id      = alibabacloud_vpc.main.id
  description = "Security group for web app"
}

resource "alibabacloud_security_group_rule" "allow_http" {
  type              = "ingress"
  ip_protocol       = "tcp"
  port_range        = "80/80"
  priority          = 1
  security_group_id = alibabacloud_security_group.app_sg.id
  cidr_ip           = "0.0.0.0/0"
}

# SLB (Load Balancer)
resource "alibabacloud_slb" "main" {
  name       = "web-app-slb"
  vswitch_id = alibabacloud_vswitch.vswitches[0].id
  load_balancer_spec = "slb.s2.small"
}

resource "alibabacloud_slb_listener" "http" {
  load_balancer_id = alibabacloud_slb.main.id
  frontend_port    = 80
  backend_port     = 80
  protocol         = "http"
  bandwidth        = -1
  scheduler        = "wlc"
}

# Auto Scaling
resource "alibabacloud_launch_template" "web" {
  name_prefix     = "web-app-"
  image_id        = "ubuntu_22_04_x64_20G_alibase_20230913.vhd"
  instance_type   = "ecs.n7.large"
  security_groups = [alibabacloud_security_group.app_sg.id]
  
  user_data = base64encode(<<-EOF
              #!/bin/bash
              cd /opt/web-app
              python -m uvicorn main:app --host 0.0.0.0 --port 80
              EOF
  )
}

resource "alibabacloud_autoscaling_group" "web" {
  load_balancer_ids    = [alibabacloud_slb.main.id]
  asg_name             = "web-app-asg"
  min_size             = 2
  max_size             = 20
  desired_capacity     = 4
  default_cooldown     = 300
  health_check_type    = "ELB"
  health_check_grace_period = 300
  vswitch_ids          = [for vsw in alibabacloud_vswitch.vswitches : vsw.id]
  
  launch_template_id      = alibabacloud_launch_template.web.id
  launch_template_version = "$Latest"
}

# Scaling policies
resource "alibabacloud_autoscaling_policy" "scale_up" {
  asg_name             = alibabacloud_autoscaling_group.web.asg_name
  adjustment_type      = "ChangeInCapacity"
  adjustment_value     = 2
  cooldown             = 60
  scaling_rule_name    = "scale-up-policy"
  scaling_rule_type    = "SimpleScalingRule"
}

resource "alibabacloud_autoscaling_policy" "scale_down" {
  asg_name             = alibabacloud_autoscaling_group.web.asg_name
  adjustment_type      = "ChangeInCapacity"
  adjustment_value     = -1
  cooldown             = 300
  scaling_rule_name    = "scale-down-policy"
  scaling_rule_type    = "SimpleScalingRule"
}

# RDS Database
resource "alibabacloud_db_instance" "web" {
  engine               = "MySQL"
  engine_version       = "8.0"
  instance_type        = "rds.mysql.x1.large"
  instance_storage     = 100
  instance_name        = "web-app-db"
  
  vswitch_id           = alibabacloud_vswitch.vswitches[0].id
  security_ips         = ["172.16.0.0/16"]
  
  master_user_name     = "admin"
  master_user_password = "YourPassword@123"  # Change this!
}

# Outputs
output "slb_address" {
  value       = alibabacloud_slb.main.address
  description = "Load balancer public IP"
}

output "rds_connection_string" {
  value       = alibabacloud_db_instance.web.connection_string
  description = "RDS connection string"
  sensitive   = true
}

output "asg_name" {
  value       = alibabacloud_autoscaling_group.web.asg_name
  description = "Auto-scaling group name"
}
