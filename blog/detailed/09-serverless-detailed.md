# Serverless Event-Driven Pipeline with Function Compute (Detailed Guide)

*Read time: 20 minutes*

## Table of Contents
1. [Serverless Concepts](#concepts)
2. [Function Compute Setup](#setup)
3. [Trigger Configuration](#triggers)
4. [Processing Patterns](#patterns)
5. [Monitoring & Debugging](#monitoring)
6. [Cost Optimization](#cost-opt)

## Serverless Concepts

### Traditional vs Serverless

```
Traditional VM          Serverless Function
┌─────────────────┐    ┌──────┐
│  OS (Always On) │    │      │
│  Runtime Setup  │    │ Code │
│  Code           │    │ Only │
│  Dependencies   │    │      │
└─────────────────┘    └──────┘
     Running 24/7       Runs on demand
    $400-500/mo        $10-50/mo
```

### Execution Model

```
Event → Function Triggered → Code Executes → Result → Function Stops
                                                      (No idle cost)
```

## Function Compute Setup

### 1. Create Service

```python
from alibabacloud_fc20200801.client import Client as FcClient
from alibabacloud_tea_openapi import models as open_api_models

class ServerlessSetup:
    def __init__(self):
        config = open_api_models.Config(
            access_key_id='xxx',
            access_key_secret='xxx',
            account_id='123456789012',
            region_id='cn-beijing'
        )
        self.client = FcClient(config)
    
    def create_service(self):
        """Create Function Compute service"""
        
        response = self.client.create_service(
            service_name='image-processor',
            description='Image processing pipeline',
            role='arn:aliyun:ram::xxxx:role/fc-oss-role',
            # IAM role for OSS access
            environment_variables={
                'BUCKET_NAME': 'my-bucket',
                'OUTPUT_PREFIX': 'processed/'
            },
            vpc_config={
                'vpc_id': 'vpc-xxx',
                'vswitch_ids': ['vsw-xxx'],
                'security_group_id': 'sg-xxx'
            }
        )
        
        return response
```

### 2. Create Function

```python
def create_function(self, service_name: str):
    """Create function inside service"""
    
    # Python function code
    function_code = '''
import json
import oss2
from PIL import Image
import io
import os

def handler(event, context):
    """
    Triggered by OSS object creation
    Resizes image and stores result
    """
    
    # Parse OSS event
    bucket_name = event['Records'][0]['oss']['bucket']['name']
    object_key = event['Records'][0]['oss']['object']['key']
    
    # Get credentials from context
    creds = context.credentials
    auth = oss2.Auth(creds.access_key_id, creds.access_key_secret)
    endpoint = f"https://oss-{context.region}.aliyuncs.com"
    bucket = oss2.Bucket(auth, endpoint, bucket_name)
    
    # Download source image
    obj = bucket.get_object(object_key)
    image_data = obj.read()
    
    # Resize
    image = Image.open(io.BytesIO(image_data))
    resized = image.resize((800, 600))
    
    # Save to memory
    output = io.BytesIO()
    resized.save(output, format='JPEG', quality=85)
    
    # Upload result
    output_key = f"{os.environ['OUTPUT_PREFIX']}{object_key}"
    bucket.put_object(output_key, output.getvalue())
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Image processed',
            'input': object_key,
            'output': output_key
        })
    }
'''
    
    response = self.client.create_function(
        service_name=service_name,
        function_name='resize_image',
        runtime='python3',
        handler='index.handler',
        code={'ZipFile': function_code},
        memory_size=512,  # MB
        timeout=60,  # seconds
        environment_variables={'LOG_LEVEL': 'INFO'}
    )
    
    return response
```

## Trigger Configuration

### 1. OSS Trigger

```python
def create_oss_trigger(self, service_name: str, function_name: str):
    """Trigger function when file uploaded to OSS"""
    
    trigger_config = {
        'triggerName': 'oss-trigger',
        'triggerType': 'oss',
        'triggerConfig': json.dumps({
            'bucketName': 'my-bucket',
            'events': ['oss:ObjectCreated:*'],  # All create events
            'filter': {
                'key': {
                    'filterRules': [
                        {
                            'name': 'prefix',
                            'value': 'uploads/'  # Only files in uploads/
                        },
                        {
                            'name': 'suffix',
                            'value': '.jpg'  # Only JPG files
                        }
                    ]
                }
            }
        })
    }
    
    response = self.client.create_trigger(
        service_name=service_name,
        function_name=function_name,
        **trigger_config
    )
```

### 2. Timer/Schedule Trigger

```python
def create_timer_trigger(self, service_name: str, function_name: str):
    """Periodic execution (cron-style)"""
    
    trigger_config = {
        'triggerName': 'daily-report',
        'triggerType': 'timer',
        'triggerConfig': 'cron(0 2 * * ?)  # 2 AM daily
    }
    
    response = self.client.create_trigger(
        service_name=service_name,
        function_name=function_name,
        **trigger_config
    )
```

### 3. HTTP Trigger

```python
def create_http_trigger(self, service_name: str, function_name: str):
    """HTTP endpoint trigger"""
    
    trigger_config = {
        'triggerName': 'http-trigger',
        'triggerType': 'http',
        'triggerConfig': json.dumps({
            'authType': 'FUNCTION',  # IAM authorization
            'methods': ['GET', 'POST'],
            'qualifiers': ['LATEST']
        })
    }
    
    response = self.client.create_trigger(
        service_name=service_name,
        function_name=function_name,
        **trigger_config
    )
    
    # Invoke via HTTP
    # curl https://xxxx.cn-beijing.fc.aliyuncs.com/invoke/
```

### 4. Message Queue Trigger

```python
def create_mq_trigger(self, service_name: str, function_name: str):
    """Trigger on MQ message"""
    
    trigger_config = {
        'triggerName': 'mq-trigger',
        'triggerType': 'mq',
        'triggerConfig': json.dumps({
            'sourceArn': 'acs:mq:cn-beijing:123456:instance/default',
            'topics': ['data-pipeline'],
            'tags': ['production'],
            'consumers': ['function-consumer'],
            'batchWindow': 60,  # Batch messages for 60 seconds
            'batchSize': 100  # Or until 100 messages
        })
    }
```

## Processing Patterns

### 1. Fan-Out Pattern

```python
def fan_out_handler(event, context):
    """
    Split work across multiple functions
    Main function dispatches to workers
    """
    
    import json
    from aliyun.mq.producer import Producer
    
    messages = event['Records']
    
    producer = Producer('acs:mq:...')
    
    for msg in messages:
        # Dispatch each message to worker pool
        producer.send_message(
            topic='worker-tasks',
            message_body=json.dumps(msg),
            message_type='normal'
        )
    
    return {'dispatched': len(messages)}
```

### 2. Map-Reduce Pattern

```python
def mapper_handler(event, context):
    """Extract/transform data"""
    
    data = event['data']
    
    # Transform
    result = {
        'key': data['category'],
        'value': data['amount']
    }
    
    # Send to reducer
    send_to_queue('reducer-input', result)

def reducer_handler(event, context):
    """Aggregate results"""
    
    items = event['items']
    
    # Group and sum
    totals = {}
    for item in items:
        key = item['key']
        totals[key] = totals.get(key, 0) + item['value']
    
    # Store final result
    store_result(totals)
```

### 3. Chain Pattern

```python
def chain_step_1(event, context):
    """First step in chain"""
    
    # Process
    intermediate = transform_data(event)
    
    # Trigger next step
    invoke_next('step-2', intermediate, context)
    
    return {'status': 'waiting for step 2'}

def chain_step_2(event, context):
    """Second step receives output from step 1"""
    
    data = event
    final_result = further_process(data)
    
    # Store result
    save_to_database(final_result)
    
    return final_result
```

## Monitoring & Debugging

### 1. Structured Logging

```python
import json
import sys

def handler(event, context):
    """Best practices for logging"""
    
    log_entry = {
        'timestamp': context.request_id,
        'level': 'INFO',
        'request_id': context.request_id,
        'message': f'Processing event {event["id"]}'
    }
    
    print(json.dumps(log_entry), file=sys.stdout)
    
    try:
        # Business logic
        result = process_event(event)
        
        log_entry['level'] = 'INFO'
        log_entry['message'] = 'Processing complete'
        log_entry['result'] = result
        
    except Exception as e:
        log_entry['level'] = 'ERROR'
        log_entry['error'] = str(e)
        log_entry['traceback'] = traceback.format_exc()
        print(json.dumps(log_entry), file=sys.stderr)
        raise
    
    print(json.dumps(log_entry), file=sys.stdout)
    return result
```

### 2. Metrics Collection

```python
from alibabacloud_cms20190101.client import Client as CmsClient

class ServerlessMetrics:
    def __init__(self, context):
        self.context = context
        self.cms_client = CmsClient()
    
    def record_metric(self, metric_name: str, value: float):
        """Send custom metrics to CloudWatch"""
        
        self.cms_client.put_metric_data(
            namespace='FC/Pipeline',
            metric_name=metric_name,
            value=value,
            timestamp=int(time.time() * 1000),
            dimensions={
                'ServiceName': self.context.service_name,
                'FunctionName': self.context.function_name,
                'RequestId': self.context.request_id
            }
        )

def handler(event, context):
    metrics = ServerlessMetrics(context)
    
    start = time.time()
    
    try:
        result = process_large_file(event)
        
        # Record success metric
        metrics.record_metric('ProcessingSuccess', 1)
        metrics.record_metric('ProcessingDuration', time.time() - start)
        
    except Exception as e:
        metrics.record_metric('ProcessingError', 1)
        raise
```

### 3. Distributed Tracing

```python
from opentelemetry import trace
from opentelemetry.exporter.jaeger.thrift import JaegerExporter

tracer = trace.get_tracer(__name__)

def handler(event, context):
    with tracer.start_as_current_span('fc:handler') as span:
        span.set_attribute('request_id', context.request_id)
        span.set_attribute('event_type', type(event).__name__)
        
        with tracer.start_as_current_span('fc:processing'):
            result = process_event(event)
            span.set_attribute('result_size', len(str(result)))
        
        with tracer.start_as_current_span('fc:storage'):
            save_result(result)
        
        return result
```

## Cost Optimization

### 1. Memory Optimization

```python
# Memory impacts both cost and performance

def optimize_memory(event, context):
    """
    Memory tiers:
    128MB  = $0.000011/sec (cheapest, but slow)
    512MB  = $0.000047/sec (good balance)
    3008MB = $0.000270/sec (fastest, but pricey)
    """
    
    # For batch processing
    memory = 256  # Start with 256MB
    
    # For heavy compute
    memory = 1024  # Increase to 1GB
    
    # For real-time API
    memory = 512   # 512MB is usually best value
```

### 2. Request Batching

```python
def batch_handler(event, context):
    """
    Instead of 1,000 individual invocations:
    - 1,000 events × $0.0000002 = $0.0002
    
    Batch into 10 functions:
    - 10 events × $0.0000002 = $0.000002
    - Save: 90% reduction!
    """
    
    items = event['Records']  # 100 items per batch
    
    processed = []
    for item in items:
        processed.append(process_item(item))
    
    return len(processed)
```

### 3. Reserved Capacity

```yaml
# For predictable, sustained load
# Reserve compute capacity upfront

ReservedConcurrentExecutions: 100
# Guarantees 100 concurrent executions
# Usually cheaper than pay-per-use for high volume
```

---

## Complete Example: ETL Pipeline

```python
# Step 1: Trigger on new CSV upload
def csv_loader(event, context):
    bucket = event['Records'][0]['oss']['bucket']['name']
    key = event['Records'][0]['oss']['object']['key']
    
    # Download CSV
    csv_data = download_from_oss(bucket, key)
    
    # Parse and batch
    for batch in chunk_csv(csv_data, size=100):
        send_to_queue('transform-queue', batch)

# Step 2: Transform data
def transformer(event, context):
    batch = event['data']
    
    transformed = [clean_and_enrich(row) for row in batch]
    
    send_to_queue('load-queue', transformed)

# Step 3: Load to database
def loader(event, context):
    records = event['data']
    
    db.insert_batch(records)
    
    return {'loaded': len(records)}
```

---

## Next Steps

- 🏗️ [Deploy with Terraform](../terraform/serverless-infrastructure/main.tf)
- 💻 [Python Examples](../code/serverless_functions.py)
- 📊 [Monitor with ARMS](../blog/05-observability-detailed.md)

**Reference:** [Function Compute Docs](https://www.alibabacloud.com/help/functioncompute) | [Trigger Types](https://www.alibabacloud.com/help/functioncompute/latest/triggers)
