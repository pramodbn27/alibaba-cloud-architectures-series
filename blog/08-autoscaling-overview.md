# Auto-scaling Web App with ECS + SLB + RDS (Quick Overview)

*Read time: 5 minutes*

## What You're Building

**Elastic web application** that scales compute based on demand while maintaining database performance.

```
Users → SLB (Load Balancer) → Auto-scaling ECS → RDS Database
                    ↓
            Health Checks & Metrics
```

## Architecture Components

- **SLB:** Layer 4/7 load balancing with health checks
- **ECS:** Horizontal scaling (add/remove instances)
- **RDS:** Managed database (vertical scaling)

## Quick Setup (15 minutes)

### 1. Create SLB
```bash
aliyun slb CreateLoadBalancer \
  --LoadBalancerName web-app-slb \
  --AddressType internet \
  --Spec large
```

### 2. Configure Health Check
```yaml
HealthCheck:
  Protocol: HTTP
  Port: 80
  Path: /health
  HealthyThreshold: 3
  UnhealthyThreshold: 3
  Interval: 10
```

### 3. Setup Auto-scaling
```bash
aliyun eas CreateAutoScalingGroup \
  --AutoScalingGroupName web-app-asg \
  --MinSize: 2
  --MaxSize: 20
  --DesiredCapacity: 4
```

### 4. Define Scaling Policies
```
CPU > 70% → Add 2 instances
CPU < 30% → Remove 1 instance
```

## Expected Performance

| Metric | Value |
|--------|-------|
| Startup time | 2-3 minutes |
| Scale-up time | 3-5 minutes |
| Scale-down time | 5-10 minutes |
| Connection pooling | 200-500 per instance |

## Cost

| Component | Monthly |
|-----------|---------|
| SLB | $50 |
| ECS (4-8 instances) | $400-800 |
| RDS (8-core) | $200-300 |
| **Total** | **$650-1,150** |

---

→ [Detailed Guide: Auto-scaling](08-autoscaling-detailed.md)

→ [Terraform Config](../terraform/autoscaling-infrastructure/main.tf)
