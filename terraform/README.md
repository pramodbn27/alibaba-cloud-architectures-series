# Alibaba Cloud Infrastructure as Code - Terraform Modules

Complete Infrastructure-as-Code setup for 9 Alibaba Cloud topics using Terraform. Each module is independently deployable and production-ready.

---

## 📋 What's Created

| # | Topic | Terraform Module | Key Resources |
|---|------|-----------------|---------------|
| 1 | Getting Started with Qwen | `qwen-infrastructure/` | RAM users, VPC, Security groups, CloudMonitor |
| 2 | Building RAG Pipeline | `rag-infrastructure/` | Hologres vectorDB, ECS compute, OSS buckets |
| 3 | Real-Time Analytics with Flink | `flink-infrastructure/` | Kafka cluster, JobManager, TaskManagers ASG |
| 4 | Zero Trust Architecture | `zerotrust-infrastructure/` | Multi-layer VPC, Security groups, IAM roles, ActionTrail |
| 5 | Observability (ARMS & SLS) | `observability-infrastructure/` | Log stores, ARMS namespace, CloudMonitor dashboards |
| 6 | Agent-Native Infrastructure | `agent-infrastructure/` | GPU instances, autoscaling, model repositories |
| 7 | Multi-region Failover | `failover-infrastructure/` | Dual SLBs, cross-region RDS, OSS replication |
| 8 | Auto-scaling Web App | `autoscaling-infrastructure/` | VPC, SLB, ASG, RDS MySQL, scaling policies |
| 9 | Serverless Pipeline | `serverless-infrastructure/` | Function Compute, OSS triggers, IAM roles |

**Total Infrastructure Cost (All Modules)
Note: Resource configurations are simplified examples for learning and experimentation. 
Actual costs depend on instance sizes, usage patterns, and selected Alibaba Cloud region.

---

## 🚀 Quick Start

### Prerequisites

**1. Install Terraform (v1.0+)**
```bash
# macOS
brew install terraform

# Linux
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/
```

**2. Configure Credentials**

Via environment variables (recommended):
```bash
export ALIBABACLOUD_ACCESS_KEY="your-access-key"
export ALIBABACLOUD_SECRET_KEY="your-secret-key"
export ALIBABACLOUD_REGION="your-desired-region"
```

Or via credentials file at `~/.alibabacloud/credentials`:
```ini
[default]
enable = true
type = access_key
access_key_id = your-access-key
access_key_secret = your-secret-key
```

**3. Verify**
```bash
terraform version
```

---

## 📦 Deployment

### Single Module
```bash
cd terraform/qwen-infrastructure/
terraform init
terraform plan -out=qwen.tfplan
terraform apply qwen.tfplan
```

### Multiple Modules
```bash
cd terraform/rag-infrastructure/
terraform init
terraform plan -out=rag.tfplan
terraform apply rag.tfplan

cd ../observability-infrastructure/
terraform init
terraform plan -out=obs.tfplan
terraform apply obs.tfplan
```

### All Modules
```bash
cd terraform/

for module in */; do
  cd "$module"
  echo "Deploying: $module"
  terraform init
  terraform plan -out="../plans/${module%/}.tfplan"
  terraform apply "../plans/${module%/}.tfplan"
  cd ..
done
```
> ⚠️ Note the `${module%/}` syntax — this correctly strips the trailing slash from directory names.

---

## 🔧 Common Commands

### Plan & Apply
```bash
terraform plan                                               # Preview changes
terraform plan -out=tfplan                                   # Save plan to file
terraform apply tfplan                                       # Apply saved plan
terraform apply -auto-approve                                # Skip confirmation (use carefully)
terraform apply -target=alibabacloud_vpc.primary_vpc         # Apply single resource
```

### Inspect State
```bash
terraform state list                                         # List all resources
terraform state show alibabacloud_vpc.rag_vpc                # Show resource details
terraform output                                             # Show all outputs
```

### Update & Maintain
```bash
terraform init -upgrade                                      # Update provider versions
terraform refresh                                            # Sync state with cloud
terraform import alibabacloud_vpc.existing vpc-xxxxx         # Import existing resource
terraform plan -destroy                                      # Preview destruction
terraform destroy                                            # Destroy all resources
```

---

## 📝 Configuration

Create a `terraform.tfvars` file to customize variables:
```hcl
region             = "your-desired-region"
project_name       = "my-project"
gpu_instance_count = 3
```

Apply with:
```bash
terraform plan -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"
```

Override individual variables inline:
```bash
terraform apply -var="region=your-desired-region" -var="project_name=production"
```

---

## 📊 Debugging

```bash
TF_LOG=DEBUG terraform plan                               # Verbose output
TF_LOG=DEBUG TF_LOG_PATH=terraform.log terraform apply   # Save logs to file
TF_LOG=TRACE terraform plan                              # Maximum verbosity

terraform validate        # Check configuration syntax
terraform fmt -recursive  # Auto-format all .tf files
terraform providers       # Check provider versions
```

---

## 📌 Best Practices

**Security**
- Never commit secrets, `.tfvars`, or `.tfstate` files to Git
- Use environment variables or a credentials file for secrets
- Use `terraform.tfvars.example` as a safe template to commit
- Enable state file encryption in production

**State Management**
- Use remote state (OSS backend) for team environments
- Enable state locking to prevent concurrent modifications
- Back up state files regularly
- Never manually edit `.tfstate` files

**Deployment**
- Always run `terraform plan` before `apply`
- Use saved plan files (`-out=tfplan`) for reproducibility
- Test in staging before production
- Tag your releases: `git tag -a v1.0.0 -m "Initial infrastructure"`

---

## 🔄 Remote State (Production)

```hcl
terraform {
  backend "oss" {
    bucket  = "my-terraform-state"
    key     = "terraform.tfstate"
    region  = "your-desired-region"
    encrypt = true
  }
}
```

```bash
terraform init \
  -backend-config="bucket=my-terraform-state" \
  -backend-config="prefix=prod"
```

---

## 📈 Scaling

Adjust autoscaling group capacity in the relevant `main.tf`:
```hcl
resource "alibabacloud_autoscaling_group" "flink_taskmanagers" {
  desired_capacity = 5
  max_size         = 10
}
```

Upgrade RDS instance type:
```hcl
resource "alibabacloud_db_instance" "primary_rds" {
  instance_type = "rds.mysql.t2.large"
}
```

Then apply: `terraform plan && terraform apply`

---

## 💰 Cost Optimization

Use spot instances (30–70% cheaper):
```hcl
on_demand_percentage_above_base_capacity = 10
```

Reduce log retention:
```hcl
retention_period = 7  # days
```

Shut down non-production resources when not in use:
```bash
terraform destroy -target=alibabacloud_instance.training_nodes
```

---

## 🆘 Troubleshooting

**Access Denied**
```bash
echo $ALIBABACLOUD_ACCESS_KEY   # Verify credentials are set
echo $ALIBABACLOUD_SECRET_KEY
```
Then check RAM permissions in the Alibaba Cloud console.

**Resource Already Exists**
```bash
terraform import alibabacloud_vpc.existing vpc-xxxxx
```

**Timeout Creating Resource**

The resource may still be provisioning. Wait a moment, then:
```bash
terraform refresh
terraform state list  # Confirm whether it appeared
```

**State File Locked**
```bash
terraform force-unlock LOCK_ID    # Unlock (get LOCK_ID from the error message)
terraform plan -lock=false         # Skip locking (development only)
```

---

## 📚 Documentation

- [Alibaba Cloud Terraform Provider](https://registry.terraform.io/providers/aliyun/alibabacloud/latest/docs)
- [Terraform Documentation](https://www.terraform.io/docs)
- [Terraform Best Practices](https://developer.hashicorp.com/terraform/cloud-docs/recommended-practices)
- [Alibaba Cloud Pricing](https://www.alibabacloud.com/en/pricing)

---

## ✅ Deployment Checklist

- [ ] Terraform v1.0+ installed
- [ ] Credentials configured
- [ ] Variables reviewed in `main.tf`
- [ ] `terraform.tfvars` created
- [ ] `terraform init` run
- [ ] `terraform plan` reviewed — no unexpected changes
- [ ] `terraform apply` run
- [ ] Resources verified in Alibaba Cloud console
- [ ] Output values captured (endpoints, IPs, etc.)
- [ ] Connectivity tested
- [ ] Monitoring and alerts configured
- [ ] State backup scheduled

---

## 🎯 Next Steps

1. Deploy `qwen-infrastructure/` — simplest module, lowest cost
2. Deploy `rag-infrastructure/` + `observability-infrastructure/` together
3. Add `agent-infrastructure/` for ML workloads
4. Deploy `failover-infrastructure/` for production high availability
5. Tune autoscaling and cost settings for your workload

---

Happy Infrastructure Coding! 🚀
