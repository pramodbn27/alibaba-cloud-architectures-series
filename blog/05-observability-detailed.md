# Observability on Alibaba Cloud: ARMS & SLS (Detailed Guide)

*Read time: 20 minutes*

## Table of Contents
1. [Three Pillars](#three-pillars)
2. [SLS Setup](#sls-setup)
3. [ARMS Application Monitoring](#arms)
4. [Distributed Tracing](#tracing)
5. [Dashboards & Alerts](#dashboards)
6. [Cost Optimization](#cost-optimization)

## Three Pillars of Observability

### 1. Logs (SLS)

```
Raw unstructured/structured text data
Diagnostic information for root cause analysis
```

### 2. Metrics (ARMS)

```
Time-series numerical data (CPU, memory, latency, errors)
High-level system health overview
```

### 3. Traces (ARMS)

```
Request flow across distributed services
Latency breakdown and bottleneck identification
```

### Relationship
```
Traces (What happened?)
  ↓ (Contains)
Logs (Why did it happen?)
  + Metrics (How much? How fast?)
```

## SLS Setup

### 1. Create Project & LogStore

```python
from aliyun.log import LogClient

client = LogClient(
    endpoint='region.log.aliyuncs.com',
    access_id='xxx',
    access_key='xxx'
)

# Create project
client.create_project(
    project_name='production-logs',
    description='Production observability'
)

# Create log stores for different purposes
log_stores = [
    ('app-logs', 'Application logs'),
    ('error-logs', 'Error tracking'),
    ('audit-logs', 'Security audit'),
    ('performance-logs', 'Performance metrics')
]

for store_name, description in log_stores:
    client.create_logstore(
        project_name='production-logs',
        logstore_name=store_name,
        ttl=90,  # Retention: 90 days
        shard_count=2,  # 2 shards for throughput
        auto_split=True,
        max_split_shard_count=10
    )
```

### 2. Send Structured Logs

```python
import json
from datetime import datetime
from aliyun.log.models import LogItem, LogItemContentPair

def send_structured_logs(client):
    """Send structured logs with context"""
    
    log_items = [
        LogItem(
            timestamp=int(datetime.now().timestamp()),
            contents=[
                LogItemContentPair('level', 'INFO'),
                LogItemContentPair('service', 'user-service'),
                LogItemContentPair('user_id', '12345'),
                LogItemContentPair('action', 'login'),
                LogItemContentPair('duration_ms', '145'),
                LogItemContentPair('status', 'success')
            ]
        ),
        LogItem(
            timestamp=int(datetime.now().timestamp()),
            contents=[
                LogItemContentPair('level', 'ERROR'),
                LogItemContentPair('service', 'payment-service'),
                LogItemContentPair('error_code', 'TIMEOUT'),
                LogItemContentPair('retry_count', '3'),
                LogItemContentPair('trace_id', 'abc123xyz')
            ]
        )
    ]
    
    client.put_logs(
        project_name='production-logs',
        logstore_name='app-logs',
        log_items=log_items
    )

send_structured_logs(client)
```

### 3. Query Logs (SLS Query Language)

```sql
-- Basic query: errors in last hour
level: ERROR | stats count() as error_count by service

-- Complex analysis: error rate by service
* | where level = 'ERROR'
  | stats count() as errors by service
  | join 
    (
      * | stats count() as total by service
    ) on service
  | project service, errors, total, 
            round(errors * 100.0 / total, 2) as error_rate_pct

-- Trend analysis: request latency over time
* where service = 'user-service'
  | stats avg(duration_ms) as avg_latency, 
          pct99(duration_ms) as p99_latency by __time__('5m')

-- User behavior analysis
action: login | stats count() as login_count, 
                      count_distinct(user_id) as unique_users
                 by date_trunc('1h', __time__)
```

### 4. Log Processing & ETL

```python
# Process logs before storage (SLS Processor)

processor_config = {
    "processors": [
        {
            "type": "processor_regex",
            "detail": {
                "source_key": "message",
                "regex": r"(\w+) (\d+) (\w+)",
                "keys": ["action", "count", "status"]
            }
        },
        {
            "type": "processor_json",
            "detail": {
                "source_key": "data",
                "expand_depth": 2,
                "prefix": "parsed_"
            }
        },
        {
            "type": "processor_filter",
            "detail": {
                "filters": [
                    {
                        "key": "level",
                        "regex": "ERROR|WARN"
                    }
                ]
            }
        }
    ]
}
```

## ARMS Application Monitoring

### 1. Setup Application Monitoring

```python
# Install ARMS agent
# pip install aliyun-arms-python-sdk

from aliyun.arms import *

# Initialize ARMS
arms_config = {
    'service': 'user-service',
    'environment': 'production',
    'region': 'cn-beijing',
    'access_id': 'xxx',
    'access_key': 'xxx'
}

client = ARMSClient(arms_config)

# Custom metrics
client.custom_counter('users.registered', 1)
client.custom_gauge('active_connections', 42)
client.custom_timer('request.duration', 145, 'ms')
```

### 2. Distributed Tracing

```python
from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import SimpleSpanProcessor
from opentelemetry.exporter.jaeger.thrift import JaegerExporter

# Configure Jaeger exporter to ARMS
jaeger_exporter = JaegerExporter(
    agent_host_name="arms-agent.region.aliyuncs.com",
    agent_port=6831,
)

trace.set_tracer_provider(TracerProvider())
trace.get_tracer_provider().add_span_processor(
    SimpleSpanProcessor(jaeger_exporter)
)

tracer = trace.get_tracer(__name__)

def process_payment(order_id: str, amount: float):
    """Trace payment processing"""
    
    with tracer.start_as_current_span("process_payment") as span:
        span.set_attribute("order_id", order_id)
        span.set_attribute("amount", amount)
        
        # Trace sub-operations
        with tracer.start_as_current_span("validate_payment"):
            validate_result = validate_payment(order_id)
            span.set_attribute("validation_result", validate_result)
        
        with tracer.start_as_current_span("charge_card"):
            charge_result = charge_card(order_id, amount)
            span.set_attribute("charge_result", charge_result)
        
        with tracer.start_as_current_span("update_database"):
            update_order_status(order_id, 'PAID')
        
        return charge_result
```

### 3. Custom Metrics

```python
from opentelemetry import metrics

meter = metrics.get_meter(__name__)

# Create custom instruments
order_counter = meter.create_counter(
    name="orders_processed",
    description="Total orders processed",
    unit="1"
)

payment_latency = meter.create_histogram(
    name="payment_processing_latency",
    description="Payment processing latency",
    unit="ms"
)

active_sessions = meter.create_observable_gauge(
    name="active_sessions",
    description="Currently active user sessions",
    unit="1",
    callbacks=[lambda options: get_active_sessions()]
)

# Use metrics
order_counter.add(1, {"region": "cn-beijing"})
payment_latency.record(245, {"method": "alipay"})
```

### 4. Exception Tracking

```python
import traceback
from functools import wraps

def track_exceptions(func):
    @wraps(func)
    def wrapper(*args, **kwargs):
        try:
            return func(*args, **kwargs)
        except Exception as e:
            # Send to ARMS
            client.report_error({
                'error_type': type(e).__name__,
                'error_message': str(e),
                'stack_trace': traceback.format_exc(),
                'function': func.__name__,
                'severity': 'high' if isinstance(e, CriticalError) else 'medium'
            })
            raise
    
    return wrapper

@track_exceptions
def critical_operation():
    # Your code here
    pass
```

## Dashboards & Alerts

### 1. Create Dashboards

```python
# Programmatic dashboard creation
dashboard_config = {
    "name": "Production Health",
    "description": "Real-time production system health",
    "widgets": [
        {
            "type": "chart.line",
            "title": "Request Latency (P99)",
            "query": "* | stats pct99(latency_ms) as p99 by service, __time__('5m')",
            "x_axis": "time",
            "y_axis": "p99"
        },
        {
            "type": "chart.bar",
            "title": "Error Rate by Service",
            "query": "level: ERROR | stats count() as errors by service"
        },
        {
            "type": "stat",
            "title": "Active Users",
            "query": "action: page_view | stats count_distinct(user_id)"
        }
    ]
}

client.create_dashboard('production-logs', dashboard_config)
```

### 2. Configure Alerts

```python
# Alert for high error rate
alert_config = {
    "name": "High Error Rate Alert",
    "query": "level: ERROR | stats count() as errors / count() as total | project error_rate=round(errors*100/total, 2)",
    "threshold": 5,  # Alert if >5% errors
    "condition": ">",
    "check_interval": 300,  # Check every 5 minutes
    "notification_channels": ["email", "slack"],
    "recipients": ["ops-team@company.com"],
    "slack_webhook": "https://hooks.slack.com/..."
}

client.create_alert('production-logs', alert_config)

# Multi-condition alert
multi_alert = {
    "name": "Cascading Failure Detection",
    "conditions": [
        {"metric": "error_rate", "operator": ">", "value": 10},
        {"metric": "latency_p99", "operator": ">", "value": 1000},
        {"metric": "cpu_usage", "operator": ">", "value": 90}
    ],
    "trigger": "ALL",  # All conditions must be true
    "escalation": {
        "level1": {"delay_minutes": 5, "notify": "team-lead"},
        "level2": {"delay_minutes": 15, "notify": "manager"}
    }
}
```

### 3. Anomaly Detection

```python
# SLS with ML-based anomaly detection
anomaly_query = """
* | select avg(latency_ms) as avg_latency, 
          stddev(latency_ms) as stddev_latency
        by service, __time__('1m')
  | where abs(avg_latency - avg(avg_latency) over ()) > 2 * stddev_latency
"""

# Baseline establishment
baseline_query = """
* where __time__ > date_sub(now(), 604800)  -- Last 7 days
  | stats avg(latency_ms) as baseline_latency by service
  | project service, baseline_latency
"""
```

## Cost Optimization

### 1. Log Sampling

```python
import random
from functools import wraps

def sample_logs(sample_rate: float = 0.1):
    """Send only a percentage of logs"""
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            if random.random() < sample_rate:
                result = func(*args, **kwargs)
                return result
            return None
        return wrapper
    return decorator

@sample_logs(sample_rate=0.05)  # Only 5% of logs
def log_debug_event(event):
    client.put_logs('app-logs', event)
```

### 2. Log Compression

```python
# Compress before sending
import gzip

def compress_logs(logs: list) -> bytes:
    log_json = json.dumps(logs).encode('utf-8')
    return gzip.compress(log_json)

# SLS handles decompression automatically
```

### 3. Retention Policies

```python
# Set different TTLs by log store
client.update_logstore(
    project='production-logs',
    logstore='app-logs',
    ttl=30  # 30 days
)

client.update_logstore(
    project='production-logs',
    logstore='audit-logs',
    ttl=365  # 1 year for compliance
)
```

---

## Recommended Alert Rules

```yaml
alerts:
  - name: "Error Spike"
    query: "level: ERROR | stats count() as cnt"
    threshold: "baseline * 3"  # 3x normal
    
  - name: "Service Latency"
    query: "* | stats pct99(duration_ms) as p99 by service"
    threshold: 500
    
  - name: "Database Connection Pool Exhaustion"
    query: "source: db_pool | stats max(active_connections) as max_conn"
    threshold: "connection_limit * 0.9"
```

---

## Next Steps

- 🏗️ [Deploy Monitoring Infrastructure](../terraform/observability-infrastructure/main.tf)
- 📊 [Create Custom Dashboards](../code/dashboards.py)
- 🔔 [Setup Alert Escalation](../code/alerting.py)

**Reference:** [SLS Documentation](https://www.alibabacloud.com/help/sls) | [ARMS Docs](https://www.alibabacloud.com/help/arms)
