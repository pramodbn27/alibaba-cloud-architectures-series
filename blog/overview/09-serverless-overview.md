# Serverless Event-Driven Pipeline with Function Compute (Quick Overview)

*Read time: 5 minutes*

## What Is Serverless?

**Pay-per-execution (no running infrastructure).** Code runs only when triggered by events.

## Architecture Pattern

```
Event Source → Function Compute → Processing → Output Storage
   (Trigger)      (Execution)
   
   Examples:
   • OSS (Object Storage) → Image resize
   • EventBridge → Scheduled jobs
   • HTTP → API endpoint
   • Message Queue → Batch processing
```

## Key Advantages

- ✅ **No servers to manage**
- ✅ **Auto-scaling** (0 → millions)
- ✅ **Pay per execution** (cost-effective)
- ✅ **Sub-second startup** typically

## 10-Minute Quickstart

### 1. Create Function
```python
def handler(event, context):
    return {
        'statusCode': 200,
        'body': f"Processed: {event['Records'][0]['bucket']}"
    }
```

### 2. Deploy
```bash
fc deploy --name image-processor
```

### 3. Connect OSS Trigger
```
OSS Bucket → New Object → Trigger Function Compute
```

### 4. Process & Store
```
Function resizes image → Stores in OSS
```

## Use Cases

| Use Case | Trigger | Output |
|----------|---------|--------|
| Image processing | OSS | Resized image |
| Data transformation | SQS | Database |
| Report generation | Timer | Email |
| API middleware | HTTP | Response |

## Pricing (100K events/month)

```
Compute: 0.0000166 ¥/GB-sec
Memory: 128MB default
First 1M events: Free tier
Expected: ¥10-50/month
```

---

→ [Detailed Guide: Serverless Pipeline](09-serverless-detailed.md)

→ [Hands-on: Run Notebook](../notebooks/09_serverless_pipeline.ipynb)
