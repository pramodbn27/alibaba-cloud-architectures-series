# Real-Time Analytics with Hologres + Flink (Detailed Guide)

*Read time: 20 minutes*

## Table of Contents
1. [Architecture](#architecture)
2. [Flink Setup](#flink-setup)
3. [Streaming Pipeline](#streaming-pipeline)
4. [Hologres Integration](#hologres-integration)
5. [Source & Sink Connectors](#connectors)
6. [Stateful Processing](#stateful)
7. [Production Considerations](#production)

## Architecture

```
┌──────────┐
│   Kafka  │ (Event Source)
└─────┬────┘
      │
      ▼
┌─────────────────────────────┐
│  Flink Processing           │
│  • Windowing                │
│  • Aggregations             │
│  • State Management         │
└─────┬───────────────────────┘
      │
      ▼
┌──────────────────────┐
│   Hologres OLAP      │
│   (Interactive DB)   │
└─────┬────────────────┘
      │
      ▼
┌────────────────────────┐
│ Real-time Dashboards  │
│ (Sub-100ms queries)   │
└────────────────────────┘
```

## Flink Setup

### Step 1: Create Flink Instance

**Via Alibaba Cloud Console:**
```
Realtime Compute → Instance Management → Create Instance

Configuration:
- Instance name: my-flink-cluster
- Version: Flink 1.15.x
- Compute Units: 8 (4 TaskManagers × 2 CU each)
- Memory: 16GB total
- Storage: OSS bucket for checkpoints
```

### Step 2: Configure Checkpointing

```java
import org.apache.flink.streaming.api.CheckpointingMode;

StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();

// Enable checkpointing every 60 seconds
env.enableCheckpointing(60000);
env.getCheckpointConfig().setCheckpointingMode(CheckpointingMode.EXACTLY_ONCE);

// Use OSS for checkpoint storage
env.getCheckpointConfig().setCheckpointStorage(
    "oss://my-bucket/checkpoints"
);
```

### Step 3: Deploy via SQL

Alibaba Flink supports SQL APIs for rapid development:

```sql
-- Create Kafka source
CREATE TABLE kafka_source (
    event_id STRING,
    user_id STRING,
    event_type STRING,
    value FLOAT,
    event_time TIMESTAMP(3),
    WATERMARK FOR event_time AS event_time - INTERVAL '5' SECOND
) WITH (
    'connector' = 'kafka',
    'topic' = 'events',
    'properties.bootstrap.servers' = 'kafka-broker:9092',
    'format' = 'json',
    'json.timestamp-format.standard' = 'ISO-8601'
);

-- Create Hologres sink
CREATE TABLE hologres_sink (
    window_start TIMESTAMP(3),
    window_end TIMESTAMP(3),
    event_type STRING,
    event_count BIGINT,
    avg_value FLOAT
) WITH (
    'connector' = 'hologres',
    'dbname' = 'holo_db',
    'tablename' = 'analytics_results',
    'username' = 'admin',
    'password' = 'xxx',
    'endpoint' = 'holo-instance.aliyuncs.com:50070'
);

-- Streaming aggregation
INSERT INTO hologres_sink
SELECT
    TUMBLE_START(event_time, INTERVAL '1' MINUTE) as window_start,
    TUMBLE_END(event_time, INTERVAL '1' MINUTE) as window_end,
    event_type,
    COUNT(*) as event_count,
    AVG(value) as avg_value
FROM kafka_source
GROUP BY
    TUMBLE(event_time, INTERVAL '1' MINUTE),
    event_type;
```

## Streaming Pipeline

### Example: Event Counting Pipeline

```python
from pyflink.datastream import StreamExecutionEnvironment
from pyflink.datastream.functions import MapFunction, ReduceFunction
from pyflink.datastream.windows import TumblingEventTimeWindow

env = StreamExecutionEnvironment.get_execution_environment()

# Map Kafka messages to event objects
class EventParser(MapFunction):
    def map(self, value):
        import json
        event = json.loads(value)
        return (event['user_id'], event['event_type'], event['value'], event['timestamp'])

# Aggregate events by user and type
class EventAggregator(ReduceFunction):
    def reduce(self, v1, v2):
        return (v1[0], v1[1], v1[2] + v2[2], v2[3])

# Read from Kafka (simplified)
kafka_stream = env.add_source(...)

# Process
result = kafka_stream \
    .map(EventParser()) \
    .key_by(lambda x: (x[0], x[1])) \
    .window(TumblingEventTimeWindow.of(60 * 1000)) \
    .reduce(EventAggregator()) \
    .map(lambda x: json.dumps({
        'user_id': x[0],
        'event_type': x[1],
        'total': x[2],
        'timestamp': x[3]
    }))

env.execute("Event Counting Pipeline")
```

### Complex Stateful Processing

```java
import org.apache.flink.streaming.api.functions.KeyedProcessFunction;
import org.apache.flink.util.Collector;
import org.apache.flink.api.common.state.ValueState;
import org.apache.flink.api.common.state.ValueStateDescriptor;

// Detect user anomalies based on value spike
public class AnomalyDetector extends KeyedProcessFunction<String, Event, Alert> {
    
    private transient ValueState<Float> previousValueState;
    private transient ValueState<Long> lastEventTimeState;
    
    @Override
    public void open(Configuration parameters) {
        previousValueState = getRuntimeContext().getState(
            new ValueStateDescriptor<Float>("previousValue", Float.class)
        );
        lastEventTimeState = getRuntimeContext().getState(
            new ValueStateDescriptor<Long>("lastEventTime", Long.class)
        );
    }
    
    @Override
    public void processElement(Event event, Context ctx, Collector<Alert> out) 
            throws Exception {
        
        Float previous = previousValueState.value();
        Long lastTime = lastEventTimeState.value();
        
        if (previous != null) {
            float delta = event.getValue() - previous;
            
            // Alert if spike > 50%
            if (Math.abs(delta) / previous > 0.5) {
                out.collect(new Alert(
                    event.getUserId(),
                    "ANOMALY_DETECTED",
                    event.getValue(),
                    delta,
                    event.getTimestamp()
                ));
            }
        }
        
        previousValueState.update(event.getValue());
        lastEventTimeState.update(event.getTimestamp());
    }
}
```

## Hologres Integration

### Setup Hologres for Real-Time

```sql
-- Create high-performance analytics table
CREATE TABLE analytics_metrics (
    window_start TIMESTAMP NOT NULL,
    window_end TIMESTAMP NOT NULL,
    event_type VARCHAR(255) NOT NULL,
    metric_name VARCHAR(255) NOT NULL,
    metric_value FLOAT NOT NULL,
    event_count BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT NOW(),
    CONSTRAINT pk_metrics PRIMARY KEY (
        window_start, window_end, event_type, metric_name
    )
)
WITH (
    orientation = 'column',
    'shard_count' = '16',
    'segment_row_limit' = '100000'
);

-- Enable Hologres Column Store for analytics
-- This is key - treat it as an OLAP engine!

-- Create materialized view for fast queries
CREATE MATERIALIZED VIEW user_aggregates AS
SELECT 
    DATE_TRUNC('minute', window_start) as minute,
    event_type,
    COUNT(DISTINCT event_type) as type_count,
    SUM(event_count) as total_events,
    AVG(metric_value) as avg_metric
FROM analytics_metrics
GROUP BY DATE_TRUNC('minute', window_start), event_type;

-- Index for fast queries
CREATE INDEX idx_analytics_window ON analytics_metrics(window_start DESC, event_type);
```

### Flink-Hologres Connector

```java
import com.alibaba.hologres.client.HoloConfig;
import com.alibaba.hologres.flink.connector.*;

// Configure Hologres sink
HoloConfig config = new HoloConfig();
config.setJdbcUrl("jdbc:hologres://holo-instance.aliyuncs.com:50070/holo_db");
config.setUsername("admin");
config.setPassword("xxx");
config.setWriteMode(WriteMode.INSERT_OR_REPLACE);
config.setDynamicPartition(true);

HologresSinkFunction<Row> sink = new HologresSinkFunction<>(
    new HologresOutputFormat(config, "analytics_metrics")
);

// Add to pipeline
dataStream.addSink(sink);
```

## Connectors

### Kafka Source Configuration

```java
import org.apache.flink.connector.kafka.source.KafkaSource;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;

KafkaSource<String> kafkaSource = KafkaSource.<String>builder()
    .setBootstrapServers("kafka-broker:9092")
    .setTopics("events")
    .setGroupId("flink-group")
    .setStartingOffsets(OffsetsInitializer.earliest())
    .setValueOnlyDeserializer(new SimpleStringSchema())
    .build();

DataStream<String> kafkaStream = env.fromSource(
    kafkaSource,
    WatermarkStrategy.forMonotonousTimestamps(),
    "Kafka Source"
);
```

### Multiple Sink Patterns

```java
// Sink 1: Hologres (primary analytics)
dataStream.addSink(new HologresSinkFunction(...));

// Sink 2: OSS (backup/archive)
dataStream.addSink(new StreamingFileSink.forBulkFormat(
    new Path("oss://bucket/analytics/"),
    new JsonFileFormat()
).build());

// Sink 3: Elasticsearch (search/visualization)
dataStream.addSink(new ElasticsearchSink.Builder<>(
    servers,
    new ElasticsearchSinkFunction<>()
).build());
```

## Stateful Processing

### Window Types

```java
// Tumbling window (non-overlapping)
.window(TumblingEventTimeWindow.of(Time.minutes(1)))

// Sliding window (overlapping)
.window(SlidingEventTimeWindow.of(Time.minutes(10), Time.minutes(1)))

// Session window (event-based gaps)
.window(EventTimeSessionWindows.withGap(Time.seconds(30)))
```

### Session Detection Example

```java
public class SessionWindow extends ProcessWindowFunction<Event, SessionStats, String, TimeWindow> {
    
    @Override
    public void process(
            String userId,
            ProcessWindowFunction<Event, SessionStats, String, TimeWindow>.Context context,
            Iterable<Event> elements,
            Collector<SessionStats> out) {
        
        long windowStart = context.window().getStart();
        long windowEnd = context.window().getEnd();
        List<Event> events = Lists.newArrayList(elements);
        
        int eventCount = events.size();
        float totalValue = (float) events.stream()
            .mapToDouble(Event::getValue)
            .sum();
        
        out.collect(new SessionStats(
            userId,
            windowStart,
            windowEnd,
            eventCount,
            totalValue / eventCount
        ));
    }
}
```

## Production Considerations

### 1. Backpressure Handling

```java
env.setStreamTimeCharacteristic(TimeCharacteristic.EventTime);
env.getConfig().setAutoWatermarkInterval(5000);

// Handle slow consumers
getExecutionConfig().enableObjectReuse();
```

### 2. Exactly-Once Semantics

```java
// Enable state backend with exactly-once
StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();

env.enableCheckpointing(60000);
env.getCheckpointConfig().setCheckpointingMode(CheckpointingMode.EXACTLY_ONCE);
env.getCheckpointConfig().setCheckpointTimeout(600000);
env.getCheckpointConfig().setMaxConcurrentCheckpoints(1);

// Use RocksDB for large state
env.setStateBackend(new RocksDBStateBackend("oss://bucket/flink-state"));
```

### 3. Monitoring

```java
// Custom metrics
Counter eventCounter = getRuntimeContext()
    .getMetricGroup()
    .counter("events_processed");

Histogram latencyHistogram = getRuntimeContext()
    .getMetricGroup()
    .histogram("processing_latency", new DescriptiveStatisticsHistogram(1000));
```

---

## Query Examples on Real-Time Data

```sql
-- Real-time percentiles
SELECT 
    event_type,
    PERCENTILE_CONT(0.95) AS p95_value,
    PERCENTILE_CONT(0.99) AS p99_value
FROM analytics_metrics
WHERE window_start > NOW() - INTERVAL '1' HOUR
GROUP BY event_type;

-- Trending analysis
SELECT 
    event_type,
    window_start,
    SUM(event_count) as count,
    LAG(SUM(event_count)) OVER (
        PARTITION BY event_type 
        ORDER BY window_start
    ) as previous_count
FROM analytics_metrics
WHERE window_start > NOW() - INTERVAL '24' HOUR
GROUP BY event_type, window_start;
```

---

## Next Steps

- 🏗️ [Deploy with Terraform](../terraform/flink-infrastructure/main.tf)
- 📊 [Create Dashboards with Grafana](../diagrams/flink-dashboard.md)
- 🔍 [Monitor with ARMS](../blog/05-observability-detailed.md)

**Reference:** [Flink Docs](https://flink.apache.org) | [Hologres Docs](https://www.alibabacloud.com/help/hologres)
