# Observability on Alibaba Cloud: ARMS & SLS (Quick Overview)

*Read time: 5 minutes*

## What is Observability?

See inside your systems through **Metrics → Logs → Traces (3 pillars)**

## ARMS + SLS Stack

- **ARMS:** Application monitoring (metrics, traces, errors)
- **SLS:** Log aggregation (structured logs, queries)
- **Integrated:** Single dashboard for all signals

## Quick 5-Step Setup

### 1. Enable SLS
```bash
aliyun log CreateProject --ProjectName ops-logs --Description "Operations"
aliyun log CreateLogStore --ProjectName ops-logs --LogStoreName app-logs
```

### 2. Install Agent
```bash
# Python
pip install aliyun-log-python-sdk

# Node.js
npm install aliyun-log
```

### 3. Send Logs
```python
from aliyun.log.logclient import LogClient

client = LogClient('region.log.aliyuncs.com', 'access_id', 'access_key')
client.put_logs('ops-logs', 'app-logs', [
    {'level': 'INFO', 'message': 'User login', 'user_id': 123}
])
```

### 4. Query Logs
```sql
* | select level, count() as cnt group by level
```

### 5. Create Dashboards
```
SLS → Dashboards → Add Widget → Select Metric → Visualize
```

## Key Metrics to Monitor

| Metric | Alert Threshold |
|--------|---|
| Error Rate | > 5% |
| Latency P99 | > 500ms |
| CPU Usage | > 80% |
| Memory Usage | > 85% |
| Disk Usage | > 90% |

## Cost Estimate

| Service | Monthly |
|---------|---------|
| SLS (10GB/day logs) | $50-100 |
| ARMS (10M metrics) | $30-50 |
| **Total** | **$80-150** |

---

→ [Detailed Guide: ARMS & SLS](05-observability-detailed.md)

→ [Hands-on: Run Notebook](../notebooks/05_observability_setup.ipynb)
