# Multi-region Failover Architecture on Alibaba Cloud (Quick Overview)

*Read time: 5 minutes*

## What is Multi-region Failover?

**Automatic traffic redirection** when a region fails. Ensures business continuity across outages.

## Key Metrics

- **RTO (Recovery Time Objective):** <5 minutes
- **RPO (Recovery Point Objective):** <1 minute
- **Availability:** 99.99% (4 nines)

## Architecture Pattern

```
Region A (Primary)    Region B (DR)    Region C (Backup)
     │                     │                 │
     ├─── Active-Active ───┤                 │
     │                     │                 │
     └─── Failover ────────┴─────────────────┘
```

## Key Components

- **Global Load Balancing (GSLB):** Route traffic to healthy region
- **Database Replication:** Sync across regions
- **DNS Failover:** Automatic DNS updates
- **Health Checks:** Monitor all regions

## Quick Setup

### 1. Deploy in 3 Regions
```
aliyun-beijing (primary)
aliyun-shanghai (secondary)
aliyun-hongkong (tertiary)
```

### 2. Setup GSLB
```
Traffic → GSLB → Health Check → Route to Healthy Region
```

### 3. Database Replication
```
Beijing (Master) → Shanghai (Replica) → HongKong (Replica)
                   (Bidirectional Sync)
```

## Cost (3 regions)

| Component | Monthly |
|-----------|---------|
| Compute (3x) | $900 |
| GSLB | $200 |
| Replication | $300 |
| **Total** | **$1,400** |

---

→ [Detailed Guide: Multi-region Failover](07-failover-detailed.md)

→ [Terraform Config](../terraform/failover-infrastructure/main.tf)
