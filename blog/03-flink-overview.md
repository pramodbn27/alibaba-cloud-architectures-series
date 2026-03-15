# Real-Time Analytics with Hologres + Flink (Quick Overview)

*Read time: 5 minutes*

## What You're Building

A **real-time data pipeline** that processes streaming data and enables sub-second analytics queries.

```
Kafka → Flink (Processing) → Hologres (OLAP DB) → Real-time Dashboards
```

## Why Hologres + Flink?

- ✅ **Flink:** Event-time processing, complex aggregations
- ✅ **Hologres:** Interactive OLAP queries on streaming data
- ✅ **Sub-second latency** for analytics

## 5-Minute Setup

### 1. Create Flink Cluster
```bash
# Alibaba Cloud Console
Search → Realtime Compute for Apache Flink → Create Instance
- 2 TaskManagers (for dev)
- 4 CPU, 8GB RAM each
```

### 2. Deploy Simple Pipeline
```java
// Kafka → Hologres
StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();

// Read from Kafka
DataStream<String> kafka = env.addSource(new FlinkKafkaConsumer<>(...));

// Write to Hologres
kafka.addSink(new HologresSink(...));

env.execute("Kafka-Hologres Pipeline");
```

### 3. Query Real-Time Data
```sql
SELECT timestamp, COUNT(*) as event_count, AVG(value) as avg_value
FROM events
WHERE timestamp > NOW() - INTERVAL '5' MINUTE
GROUP BY TUMBLE(timestamp, INTERVAL '1' MINUTE);
```

## Performance Benchmarks

- **Latency:** 100-500ms end-to-end
- **Throughput:** 100K+ events/second
- **Query latency:** <100ms for OLAP queries

## Cost Estimate

| Service | Monthly |
|---------|---------|
| Flink (2 TM, 8 CU) | $400-600 |
| Hologres (4-core RI) | $100-150 |
| Kafka (3 brokers) | $200-300 |
| **Total** | **$700-1050** |

## Use Cases

- 📊 Real-time dashboards
- 🛡️ Fraud detection
- 📈 Metrics aggregation
- 🎯 User behavior analytics

---

→ [Detailed Guide: Flink + Hologres](03-flink-detailed.md)

→ [Hands-on: Run Notebook](../notebooks/03_flink_analytics.ipynb)
