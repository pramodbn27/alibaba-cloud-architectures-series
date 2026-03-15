# Zero Trust Architecture on Alibaba Cloud (Quick Overview)

*Read time: 5 minutes*

## What is Zero Trust?

**Never trust, always verify.** Every access request is authenticated and authorized, regardless of source.

## 3 Core Principles

1. **Verify Identity:** Use MFA, certificates for all users/services
2. **Least Privilege:** Minimum necessary permissions
3. **Encrypt Everything:** Data at rest and in transit

## Quick Implementation

### 1. Setup RAM (Identity & Access Management)
```
Users → RAM → RAM Policies → IAM Roles
```

### 2. Multi-Factor Authentication
```yaml
Users: All enabled with MFA
Type: TOTP (Time-based) or SMS
```

### 3. Network Isolation
```
Principle: Only specific VPC traffic allowed
- Security Groups: Whitelist rules
- NACLs: Stateless filters
- VPC endpoints: Encrypted tunnels
```

## Authentication Flow

```
User → MFA → Certificate → VPC Endpoint → RAM Policy → Access Granted/Denied
```

## Key Components

| Component | Purpose |
|-----------|---------|
| RAM | Identity & Access Management |
| VPC | Network isolation |
| KMS | Encryption key management |
| Bastion Host | Secure SSH gateway |
| Security Groups | Firewall rules |

## Cost: ~$50-100/month (mostly for data transfer)

---

→ [Detailed Guide: Zero Trust](04-zerotrust-detailed.md)

→ [Terraform Config](../terraform/zerotrust-infrastructure/main.tf)
