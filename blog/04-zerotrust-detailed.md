# Zero Trust Architecture on Alibaba Cloud (Detailed Guide)

*Read time: 15 minutes*

## Table of Contents
1. [Zero Trust Fundamentals](#fundamentals)
2. [RAM Setup](#ram-setup)
3. [Network Security](#network-security)
4. [Encryption Strategy](#encryption)
5. [Monitoring & Audit](#monitoring)
6. [Implementation Checklist](#checklist)

## Zero Trust Fundamentals

### Traditional vs Zero Trust

| Traditional | Zero Trust |
|------------|-----------|
| Trust inside perimeter | Verify every access |
| Implicit by location | Explicit authentication |
| Few MFA points | MFA everywhere |
| Broad permissions | Least privilege |
| Manual auditing | Automated logging |

### Alibaba Zero Trust Layers

```
┌─────────────────────────────────────────┐
│ User/Service Authentication (MFA + Cert)│
├─────────────────────────────────────────┤
│ Identity Verification (RAM)             │
├─────────────────────────────────────────┤
│ Authorization (IAM Policies)            │
├─────────────────────────────────────────┤
│ Network Segmentation (VPC)              │
├─────────────────────────────────────────┤
│ Data Protection (Encryption + TLS)      │
├─────────────────────────────────────────┤
│ Audit & Monitoring (ActionTrail + SLS)  │
└─────────────────────────────────────────┘
```

## RAM Setup

### 1. Organizational Structure

```yaml
Root Account
├── Admin Users (MFA Required)
│   └── Terraform automation
├── Development Team
│   ├── Dev-ReadWrite (limited resources)
│   ├── Dev-ReadOnly
│   └── Dev-Ops
├── Production Team
│   ├── Prod-Admin (very limited)
│   ├── Prod-Operations
│   └── Prod-Auditor
└── Security Team
    ├── Security-Admin
    └── Security-Auditor
```

### 2. Create RAM Users

```bash
# Via CLI
aliyun ram CreateUser --UserName developer1
aliyun ram CreateAccessKey --UserName developer1

# Output
"AccessKeyId": "LTAI5...",
"AccessKeySecret": "nPxA..."
```

### 3. Create Custom Policies

```json
{
  "Version": "1",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecs:DescribeInstances",
        "ecs:DescribeSecurityGroups"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "acs:SourceVpc": "vpc-xxxx"
        }
      }
    },
    {
      "Effect": "Deny",
      "Action": "ecs:DeleteInstance",
      "Resource": "*"
    }
  ]
}
```

### 4. Attach Policies to Users

```bash
aliyun ram AttachUserPolicy \
  --UserName developer1 \
  --PolicyName ReadOnlyAccess

aliyun ram AttachUserPolicy \
  --UserName developer1 \
  --PolicyName CustomVpcAccess
```

## Network Security

### 1. VPC Architecture

```
┌─────────────────────────────────┐
│ VPC (172.16.0.0/16)            │
├─────────────────────────────────┤
│ Public Subnet (172.16.1.0/24)  │
│  └─ NAT Gateway, Bastion      │
├─────────────────────────────────┤
│ Private Subnet (172.16.2.0/24) │
│  └─ Application Servers       │
├─────────────────────────────────┤
│ Database Subnet (172.16.3.0/24)│
│  └─ RDS Instance              │
└─────────────────────────────────┘
```

### 2. Security Group Setup

```bash
# Create security group
aliyun ecs CreateSecurityGroup \
  --SecurityGroupName app-sg \
  --VpcId vpc-xxxx \
  --Description "Application server security group"

# Default-deny, then whitelist
# Inbound: Only from ALB
aliyun ecs AuthorizeSecurityGroup \
  --SecurityGroupId sg-xxxx \
  --SourceSecurityGroupId sg-alb \
  --IpProtocol tcp \
  --PortRange "80/80"

# Outbound: Only to DB security group (database)
aliyun ecs AuthorizeSecurityGroupEgress \
  --SecurityGroupId sg-xxxx \
  --DestinationSecurityGroupId sg-db \
  --IpProtocol tcp \
  --PortRange "3306/3306"
```

### 3. Bastion Host (Jump Box)

```python
# Deploy via Terraform (see terraform/ folder)
# Access pattern:
# User → SSH Key (MFA) → Bastion (in Public Subnet)
#                      → Internal SSH → App Server

import paramiko

class BastionAccess:
    def __init__(self, bastion_host, private_key_path):
        self.bastion_host = bastion_host
        self.client = paramiko.SSHClient()
        self.client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    
    def connect_via_bastion(self, target_host, command):
        """SSH to target via bastion using ProxyJump"""
        # Client connects through bastion with MFA verification
        
        # This is handled by SSH config:
        # Host bastion
        #     HostName <bastion-ip>
        #     User ec2-user
        #     IdentityFile ~/.ssh/bastion-key
        #     StrictHostKeyChecking accept-new
        #
        # Host app-server
        #     HostName <private-ip>
        #     ProxyJump bastion
        #     User ec2-user
        #     IdentityFile ~/.ssh/app-key
        ```

### 4. NACLs (Network ACLs)

```bash
# Explicit allow/deny at subnet level
# Rule: Allow only specific IPs to specific ports

aliyun vpc CreateNetworkAclEntry \
  --NetworkAclId acl-xxx \
  --RuleNumber 100 \
  --Direction Ingress \
  --Protocol TCP \
  --PortRange "443/443" \
  --SourceCidrIp "203.0.113.0/24" \
  --Action Allow
```

## Encryption Strategy

### 1. KMS Setup

```python
import os
from alibabacloud_kms20160120.client import Client as KmsClient
from alibabacloud_tea_openapi import models as open_api_models

class KmsEncryption:
    def __init__(self):
        config = open_api_models.Config(
            access_key_id=os.environ.get('ALIYUN_ACCESS_KEY_ID'),
            access_key_secret=os.environ.get('ALIYUN_ACCESS_KEY_SECRET'),
            region_id='cn-beijing',
            endpoint='kms.aliyuncs.com'
        )
        self.client = KmsClient(config)
    
    def create_key(self, key_desc: str):
        """Create a master key"""
        response = self.client.create_key(
            description=key_desc,
            origin='Aliyun_KMS'
        )
        return response.body.key_metadata.key_id
    
    def encrypt_data(self, key_id: str, data: str):
        """Encrypt data with KMS key"""
        response = self.client.encrypt(
            key_id=key_id,
            plaintext=data.encode('utf-8')
        )
        return response.body.ciphertext_blob
    
    def decrypt_data(self, ciphertext: str):
        """Decrypt data"""
        response = self.client.decrypt(
            ciphertext_blob=ciphertext
        )
        return response.body.plaintext.decode('utf-8')

# Usage
kms = KmsEncryption()
key_id = kms.create_key("Application Master Key")

# Encrypt sensitive data
secret = "database_password_123"
encrypted = kms.encrypt_data(key_id, secret)

# Decrypt
decrypted = kms.decrypt_data(encrypted)
```

### 2. TLS/mTLS for Service-to-Service

```yaml
# Istio-style service mesh on Alibaba Cloud

apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
  name: app-mtls
spec:
  host: app-service
  trafficPolicy:
    tls:
      mode: MUTUAL
      clientCertificate: /etc/certs/client.crt
      clientKey: /etc/certs/client.key
      sni: app-service.default.svc.cluster.local
```

### 3. Database Encryption

```sql
-- Create encrypted RDS
ALTER TABLE users ENCRYPTED WITH 'aes-256-gcm';

-- Application-level encryption
CREATE TABLE credit_cards (
    id INT PRIMARY KEY,
    card_number VARBINARY(255),  -- Encrypted
    created_at TIMESTAMP
);

-- Encrypt on insert
INSERT INTO credit_cards (card_number) 
VALUES (ENCRYPT_AES('4111111111111111', master_key));
```

## Monitoring & Audit

### 1. ActionTrail (Audit Logs)

```bash
# Enable ActionTrail
aliyun actiontrail CreateTrail \
  --Name security-audit \
  --S3BucketName my-audit-bucket \
  --IsMultiRegionTrail true

# Query audit logs
aliyun actiontrail LookupEvents \
  --EventName DeleteSecurityGroup \
  --LookupAttributes Key=EventName
```

### 2. SLS (Log Service) Alerts

```python
from aliyun_log_python_sdk import *

def setup_security_alerts():
    """Configure security alerts"""
    
    # Create project
    log_client = LogClient('region.log.aliyuncs.com', 'access_id', 'access_key')
    
    # Query suspicious activities
    query = """
    source = 'action' 
    | 
    where (EventSource = 'ecs.aliyuncs.com' and EventName='DeleteSecurityGroup')
        or (EventSource = 'ram.aliyuncs.com' and EventName='DeletePolicy')
        or (RequestParameters like /192.168/ and ErrorCode='Forbidden')
    | 
    stats count() as alert_count by EventName, SourceIPAddress
    """
    
    # Create alert rule
    response = log_client.create_alert_rule(
        project='security-alerts',
        alert_name='unauthorized_access_attempts',
        query_string=query,
        query_time_range=900,  # Check every 15 minutes
        log_store='action_trail',
        threshold=5  # Alert if >5 failures
    )
```

### 3. ARMS (Application Monitoring)

```python
# Monitor authentication failures
from aliyun_opentelemetry import OpenTelemetry

otel = OpenTelemetry()
tracer = otel.get_tracer(__name__)

def authenticate_user(username: str, password: str):
    with tracer.start_as_current_span("user_authentication") as span:
        try:
            # Verify MFA
            mfa_verified = verify_mfa(username)
            span.set_attribute("mfa_verified", mfa_verified)
            
            # Check credentials
            user = verify_credentials(username, password)
            span.set_attribute("auth_success", True)
            
            return user
        except Exception as e:
            span.set_attribute("auth_success", False)
            span.set_attribute("error_type", type(e).__name__)
            raise
```

## Implementation Checklist

- [ ] Create separate RAM accounts for users
- [ ] Enable MFA for all console users
- [ ] Create custom IAM policies (least privilege)
- [ ] Setup VPC with public/private subnets
- [ ] Deploy Bastion host for SSH access
- [ ] Configure security groups with default-deny
- [ ] Create KMS keys for encryption
- [ ] Enable TLS/mTLS between services
- [ ] Setup ActionTrail audit logging
- [ ] Configure SLS alerts for security events
- [ ] Test access control with denied requests
- [ ] Document access procedures
- [ ] Schedule quarterly access reviews

---

## Next Steps

- 🏗️ [Deploy with Terraform](../terraform/zerotrust-infrastructure/main.tf)
- 📊 [Monitor with ARMS & SLS](../blog/05-observability-detailed.md)
- 🔑 [KeyVault Management](../code/kms_manager.py)

**Reference:** [RAM Documentation](https://www.alibabacloud.com/help/ram) | [VPC Security](https://www.alibabacloud.com/help/vpc)
