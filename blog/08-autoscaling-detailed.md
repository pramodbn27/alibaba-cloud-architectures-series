# Auto-scaling Web App with ECS + SLB + RDS (Detailed Guide)

*Read time: 25 minutes*

## Table of Contents
1. [Architecture Design](#architecture)
2. [SLB Configuration](#slb)
3. [Auto-scaling Setup](#autoscaling)
4. [Database Optimization](#database)
5. [Performance Tuning](#tuning)
6. [Cost Optimization](#cost-opt)

## Architecture Design

### High-Level Flow

```
┌────────────────────────────────┐
│ Internet                       │
└────┬─────────────────────────┘
     │
     ▼
┌────────────────────────────────┐
│ SLB (Classic + Application)    │
│ - Layer 4 (TCP): high throughput│
│ - Layer 7 (HTTP): advanced routing
└────┬─────────────────────────────┘
     │
     ├──→ ECS Instance 1 (Healthy)
     ├──→ ECS Instance 2 (Healthy)
     ├──→ ECS Instance 3 (Healthy)
     └──→ ECS Instance 4 (Healthy)
             ↓
     RDS Database (Primary)
             ├─→ Read Replicas (Optional)
             └─→ Backups
```

### Scaling Triggers

```
Request Rate   | Desired Action
─────────────────────────────────────
< 100 req/s    | Min instances (2)
100-200 req/s  | 4 instances
200-500 req/s  | 8 instances
500-1000 req/s | 15 instances
> 1000 req/s   | Max instances (20)
```

## SLB Configuration

### 1. Create Load Balancer

```python
from alibabacloud_slb20130630.client import Client as SlbClient
from alibabacloud_tea_openapi import models as open_api_models

class LoadBalancerSetup:
    def __init__(self):
        config = open_api_models.Config(
            access_key_id='xxx',
            access_key_secret='xxx',
            region_id='cn-beijing'
        )
        self.client = SlbClient(config)
    
    def create_slb(self):
        """Create load balancer"""
        response = self.client.create_load_balancer(
            load_balancer_name='web-app-slb',
            address_type='internet',  # Public internet
            spec='slb.s2.small',  # Shared performance
            vswitch_id='vsw-xxx',
            tags={
                'Environment': 'production',
                'Application': 'web-app'
            }
        )
        return response.body
```

### 2. Configure Listeners

```python
def setup_listeners(self, slb_id: str):
    """Setup HTTP and HTTPS listeners"""
    
    # HTTP listener (on port 80)
    self.client.create_load_balancer_listener(
        load_balancer_id=slb_id,
        listener_port=80,
        backend_server_port=80,
        protocol='HTTP',
        bandwidth=-1,  # Unlimited
        scheduler='wlc',  # Weighted least-connection
        acl_status='off'  # No ACL yet
    )
    
    # HTTPS listener (on port 443)
    self.client.create_load_balancer_listener(
        load_balancer_id=slb_id,
        listener_port=443,
        backend_server_port=443,
        protocol='HTTPS',
        server_certificate_id='cert-xxx',
        ssl_version=['TLSv1.2', 'TLSv1.3'],
        bandwidth=-1
    )
```

### 3. Health Check Setup

```python
def setup_health_check(self, slb_id: str):
    """Configure comprehensive health checking"""
    
    health_check_config = {
        'load_balancer_id': slb_id,
        'listener_port': 80,
        'health_check': 'on',
        'health_check_type': 'HTTP',
        'health_check_domain': '',  # Use host header
        'health_check_uri': '/health',
        'health_check_http_code': 'http_2xx,http_3xx',
        'healthy_threshold': 3,  # 3 successes = healthy
        'unhealthy_threshold': 3,  # 3 failures = unhealthy
        'health_check_interval': 2,  # Check every 2 seconds
        'health_check_connect_timeout': 5  # 5 second timeout
    }
    
    response = self.client.set_load_balancer_http_listener_attribute(
        **health_check_config
    )
```

### 4. Session Persistence

```python
def enable_session_persistence(self, slb_id: str):
    """Enable sticky sessions for stateful apps"""
    
    # Cookie-based persistence (7 days)
    sticky_session_config = {
        'load_balancer_id': slb_id,
        'listener_port': 80,
        'sticky_session': 'on',
        'sticky_session_type': 'insert',  # SLB adds cookie
        'cookie_timeout': 7 * 24 * 3600,  # 7 days
    }
    
    # For HTTPS, use server cookie
    sticky_session_config['sticky_session_type'] = 'server'
    
    response = self.client.set_load_balancer_tcp_listener_attribute(
        **sticky_session_config
    )
```

## Auto-scaling Setup

### 1. Create Launch Template

```python
from alibabacloud_eas20180412.client import Client as EasClient

class AutoScalingSetup:
    def __init__(self):
        self.eas_client = EasClient()
    
    def create_launch_template(self):
        """Create template for scaling group"""
        
        template_data = {
            'LaunchTemplateName': 'web-app-template',
            'ImageId': 'ubuntu-22.04-web-app',  # Custom image
            'InstanceType': 'ecs.n7.large',  # 2vCPU, 8GB RAM
            'KeyPairName': 'web-app-key',
            'SecurityGroupId': 'sg-xxx',
            'UserData': '''#!/bin/bash
set -e
echo "Starting application..."
cd /opt/web-app
python -m uvicorn main:app --host 0.0.0.0 --port 80
''',
            'TagSpecifications': [
                {
                    'ResourceType': 'instance',
                    'Tags': [
                        {'Key': 'Application', 'Value': 'web-app'},
                        {'Key': 'ManagedBy', 'Value': 'auto-scaling'}
                    ]
                }
            ]
        }
        
        response = self.eas_client.create_launch_template(template_data)
        return response
```

### 2. Create Scaling Group

```python
def create_scaling_group(self):
    """Create auto-scaling group"""
    
    scaling_group = {
        'AutoScalingGroupName': 'web-app-asg',
        'LaunchTemplateId': 'lt-xxx',
        'LaunchTemplateVersion': '$Latest',
        'MinSize': 2,
        'MaxSize': 20,
        'DesiredCapacity': 4,
        'DefaultCooldown': 300,  # 5 minute cooldown
        'VSwitchIds': ['vsw-xxx', 'vsw-yyy'],  # Multi-AZ
        'LoadBalancerIds': ['slb-xxx'],
        'HealthCheckType': 'ELB',  # Use SLB health check
        'HealthCheckGracePeriod': 300,  # 5 min grace period
        'Tags': {
            'Application': 'web-app',
            'Environment': 'production'
        }
    }
    
    response = self.eas_client.create_auto_scaling_group(scaling_group)
    return response
```

### 3. Define Scaling Policies

```python
def create_scaling_policies(self, asg_id: str):
    """Create CPU-based scaling policies"""
    
    # Scale UP policy
    scale_up = {
        'AutoScalingGroupId': asg_id,
        'AdjustmentType': 'ChangeInCapacity',
        'AdjustmentValue': 2,  # Add 2 instances
        'Cooldown': 60,  # 1 minute between scale-ups
        'PolicyName': 'scale-up-policy'
    }
    
    up_policy = self.eas_client.create_scaling_policy(scale_up)
    
    # Scale DOWN policy
    scale_down = {
        'AutoScalingGroupId': asg_id,
        'AdjustmentType': 'ChangeInCapacity',
        'AdjustmentValue': -1,  # Remove 1 instance
        'Cooldown': 300,  # 5 minutes between scale-downs
        'PolicyName': 'scale-down-policy'
    }
    
    down_policy = self.eas_client.create_scaling_policy(scale_down)
    
    return up_policy, down_policy
```

### 4. Create Alarms to Trigger Scaling

```python
def setup_scaling_alarms(self, asg_id: str, up_policy_id: str, down_policy_id: str):
    """Setup CloudWatch alarms that trigger scaling"""
    
    # High CPU alarm (triggers scale-up)
    high_cpu_alarm = {
        'AlarmName': f'{asg_id}-high-cpu',
        'MetricName': 'CPUUtilization',
        'Namespace': 'AWS/EC2',
        'Statistic': 'Average',
        'Period': 60,  # 1 minute
        'EvaluationPeriods': 2,  # 2 consecutive periods
        'Threshold': 70,  # 70% CPU
        'ComparisonOperator': 'GreaterThanThreshold',
        'AlarmActions': [up_policy_id]
    }
    
    # Low CPU alarm (triggers scale-down)
    low_cpu_alarm = {
        'AlarmName': f'{asg_id}-low-cpu',
        'MetricName': 'CPUUtilization',
        'Namespace': 'AWS/EC2',
        'Statistic': 'Average',
        'Period': 300,  # 5 minutes
        'EvaluationPeriods': 3,  # 3 consecutive periods
        'Threshold': 30,  # 30% CPU
        'ComparisonOperator': 'LessThanThreshold',
        'AlarmActions': [down_policy_id]
    }
    
    cloudwatch = boto3.client('cloudwatch')
    cloudwatch.put_metric_alarm(**high_cpu_alarm)
    cloudwatch.put_metric_alarm(**low_cpu_alarm)
```

## Database Optimization

### 1. Connection Pooling

```python
from sqlalchemy import create_engine
from sqlalchemy.pool import QueuePool

class DatabaseConnection:
    def __init__(self):
        # Create connection pool
        self.engine = create_engine(
            'mysql+pymysql://user:pass@rds-instance:3306/app_db',
            poolclass=QueuePool,
            pool_size=20,  # Connections per instance
            max_overflow=10,  # Additional overflow connections
            pool_recycle=3600,  # Recycle connections after 1 hour
            pool_pre_ping=True,  # Verify connection before using
        )
```

### 2. Read Replicas

```python
def setup_read_replicas(self):
    """Add read replicas for read-heavy workloads"""
    
    # Create read replica in same region
    read_replica = self.rds_client.create_db_instance_read_replica(
        DBInstanceIdentifier='app-db-replica-1',
        SourceDBInstanceIdentifier='app-db-primary',
        DBInstanceClass='rds.mysql.x1.large'
    )
    
    # Create read replica in different region
    remote_replica = self.rds_client.create_db_instance_read_replica(
        DBInstanceIdentifier='app-db-replica-2-hongkong',
        SourceDBInstanceIdentifier='app-db-primary',
        DestinationRegion='hk-hongkong',
        DBInstanceClass='rds.mysql.x1.large'
    )
```

### 3. Query Optimization

```sql
-- Add indexes for common queries
CREATE INDEX idx_user_created ON users(user_id, created_at);
CREATE INDEX idx_order_status ON orders(status, created_at);

-- Monitor slow queries
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 1;  -- Log queries > 1 second
```

## Performance Tuning

### 1. Application-level Caching

```python
from functools import lru_cache
import redis

class CacheLayer:
    def __init__(self):
        self.redis_client = redis.Redis(
            host='redis-cache.aliyuncs.com',
            port=6379,
            decode_responses=True
        )
    
    @lru_cache(maxsize=1000)
    def get_user_profile(self, user_id: int):
        """Cache user profile"""
        
        cache_key = f'user:{user_id}'
        
        # Check Redis first
        cached = self.redis_client.get(cache_key)
        if cached:
            return json.loads(cached)
        
        # Query database
        user = db.query(User).filter_by(id=user_id).first()
        
        # Cache for 1 hour
        self.redis_client.setex(cache_key, 3600, json.dumps(user.to_dict()))
        
        return user.to_dict()
```

### 2. Load Testing

```python
import locust

class WebAppLoadTest(HttpUser):
    wait_time = between(1, 3)  # Wait 1-3 seconds between requests
    
    @task
    def index(self):
        self.client.get("/")
    
    @task(3)
    def get_products(self):
        self.client.get("/api/products")
    
    @task(2)
    def search(self):
        self.client.get("/api/search?q=test")

# Run: locust -f load_test.py --host=http://example.com
```

## Cost Optimization

### 1. Spot Instances

```yaml
AutoScalingGroup:
  LaunchTemplate:
    InstanceType: ecs.n7.large
    PricePerformanceRatio: Spot  # Up to 70% discount
    MaxPricePercentage: 100  # Up to on-demand price
    
  Benefits:
    - 4 On-Demand instances: $2.00/hour
    - 4 Spot instances: $0.60/hour
    - Monthly savings: ~$1,000
```

### 2. Reserved Instances

```
Combine:
- 2 Reserved Instances (1-year)
- 2-4 On-Demand (for scaling peaks)
- Saves ~$200-300/month
```

---

## Next Steps

- 🏗️ [Deploy with Terraform](../terraform/autoscaling-infrastructure/main.tf)
- 📊 [Monitor with ARMS](../blog/05-observability-detailed.md)
- 🧪 [Load Testing](../code/load_testing.py)

**Reference:** [SLB Docs](https://www.alibabacloud.com/help/slb) | [Auto Scaling](https://www.alibabacloud.com/help/eas)
