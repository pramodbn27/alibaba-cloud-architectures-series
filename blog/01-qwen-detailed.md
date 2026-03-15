# Getting Started with Qwen on Alibaba Cloud Model Studio (Detailed Guide)

*Read time: 15 minutes*

## Table of Contents
1. [What is Qwen?](#what-is-qwen)
2. [Account Setup](#account-setup)
3. [API Authentication](#api-authentication)
4. [Making Your First Request](#making-your-first-request)
5. [Advanced Features](#advanced-features)
6. [Optimization Tips](#optimization-tips)
7. [Troubleshooting](#troubleshooting)

## What is Qwen?

Qwen (通义千问) is Alibaba's multilingual large language model family:

- **Open-source models:** Qwen-7B, Qwen-14B (run locally)
- **API models:** Qwen-turbo, Qwen-plus, Qwen-max (cloud-based)
- **Specialized models:** Code-focused, Chat, Math reasoning

**Key Advantages:**
- Native Chinese language understanding
- Fast inference on Alibaba infrastructure
- Integration with DashScope (Alibaba's LLM service)
- Cost-effective for high-volume requests

## Account Setup

### Step 1: Create Alibaba Cloud Account

1. Visit [aliyun.com](https://www.aliyun.com)
2. Register with email/phone
3. Complete real-name verification (required for API access)
4. Add payment method

### Step 2: Access DashScope (Model Studio)

1. Login to Alibaba Cloud Console
2. Search for "DashScope" or "Model Studio"
3. Accept terms of service
4. You're ready to create API keys!

### Step 3: Generate API Key

**Via Console:**
```
DashScope → API-Key Management → Create API Key
```

**Store safely:**
```
API Key: sk-abc123xyz...
Access ID: LTAI5t...
Access Key: nPxabc...
```

**⚠️ Security:** Never commit keys to version control. Use environment variables or secrets manager.

## API Authentication

### Method 1: Environment Variables (Recommended)

```bash
# Linux/Mac
export DASHSCOPE_API_KEY="sk-your-key-here"

# Windows
set DASHSCOPE_API_KEY=sk-your-key-here
```

### Method 2: Direct in Code (Development Only)

```python
import os
os.environ['DASHSCOPE_API_KEY'] = 'sk-your-key-here'
```

### Method 3: Configuration File

Create `.dashscope/config.yaml`:
```yaml
dashscope:
  api_key: sk-your-key-here
  region: cn-beijing
  timeout: 30
```

## Making Your First Request

### Basic Chat Request

```python
from dashscope import Generation
import os

def simple_chat():
    response = Generation.call(
        model='qwen-turbo',
        messages=[
            {'role': 'user', 'content': 'What is machine learning?'}
        ]
    )
    
    if response.status_code == 200:
        print(response.output.choices[0].message.content)
    else:
        print(f"Error: {response.code}, {response.message}")

simple_chat()
```

### Streaming Response

```python
from dashscope import Generation

def streaming_chat():
    responses = Generation.call(
        model='qwen-turbo',
        messages=[
            {'role': 'user', 'content': 'Write a poem about AI'}
        ],
        stream=True
    )
    
    for response in responses:
        if response.status_code == 200:
            print(response.output.choices[0].message.content, end='')
        else:
            print(f"Error: {response.code}")

streaming_chat()
```

### Multi-turn Conversation

```python
from dashscope import Generation

def multi_turn_conversation():
    messages = []
    
    # Turn 1
    messages.append({'role': 'user', 'content': 'What is AI?'})
    response = Generation.call(model='qwen-turbo', messages=messages)
    assistant_msg = response.output.choices[0].message.content
    messages.append({'role': 'assistant', 'content': assistant_msg})
    print(f"AI: {assistant_msg}\n")
    
    # Turn 2
    messages.append({'role': 'user', 'content': 'How does machine learning fit into that?'})
    response = Generation.call(model='qwen-turbo', messages=messages)
    assistant_msg = response.output.choices[0].message.content
    messages.append({'role': 'assistant', 'content': assistant_msg})
    print(f"AI: {assistant_msg}\n")

multi_turn_conversation()
```

## Advanced Features

### System Prompts

Control model behavior with system instructions:

```python
messages = [
    {'role': 'system', 'content': 'You are a helpful poetry expert. Respond in simple Chinese.'},
    {'role': 'user', 'content': 'Write a short poem about spring'}
]

response = Generation.call(model='qwen-plus', messages=messages)
```

### Temperature & Top-P

Control randomness:

```python
response = Generation.call(
    model='qwen-turbo',
    messages=[{'role': 'user', 'content': 'Generate a creative story'}],
    temperature=0.8,  # 0-1, higher = more creative
    top_p=0.95        # nucleus sampling
)
```

### Function Calling (Tool Use)

Enable model to call external functions:

```python
functions = [
    {
        'name': 'get_weather',
        'description': 'Get weather for a city',
        'parameters': {
            'type': 'object',
            'properties': {
                'city': {'type': 'string', 'description': 'City name'}
            }
        }
    }
]

response = Generation.call(
    model='qwen-turbo',
    messages=[{'role': 'user', 'content': 'What is the weather in Beijing?'}],
    tools=functions
)
```

### Batch Processing

```python
from dashscope import Generation

def batch_inference(prompts):
    results = []
    for prompt in prompts:
        response = Generation.call(
            model='qwen-turbo',
            messages=[{'role': 'user', 'content': prompt}]
        )
        if response.status_code == 200:
            results.append(response.output.choices[0].message.content)
    return results

prompts = [
    'Explain quantum computing',
    'Summarize climate change',
    'Describe blockchain'
]

outputs = batch_inference(prompts)
for prompt, output in zip(prompts, outputs):
    print(f"Q: {prompt}")
    print(f"A: {output}\n")
```

## Optimization Tips

### 1. Choose the Right Model

```
qwen-turbo:   For real-time responses, chatbots
qwen-plus:    Balanced quality/speed, default choice
qwen-max:     Complex reasoning, analysis
qwen-long:    Large documents, long context
```

### 2. Implement Caching

```python
import hashlib
import json

cache = {}

def cached_inference(model, prompt):
    # Create cache key
    key = hashlib.md5(prompt.encode()).hexdigest()
    
    if key in cache:
        return cache[key]
    
    # Call API
    response = Generation.call(
        model=model,
        messages=[{'role': 'user', 'content': prompt}]
    )
    
    if response.status_code == 200:
        result = response.output.choices[0].message.content
        cache[key] = result
        return result
```

### 3. Batch Requests

```python
import asyncio
from dashscope import Generation

async def async_inference(prompt):
    return Generation.call(
        model='qwen-turbo',
        messages=[{'role': 'user', 'content': prompt}]
    )

async def batch_async(prompts):
    tasks = [async_inference(p) for p in prompts]
    return await asyncio.gather(*tasks)

# Usage
prompts = ['Prompt 1', 'Prompt 2', 'Prompt 3']
results = asyncio.run(batch_async(prompts))
```

### 4. Monitor Token Usage

```python
response = Generation.call(
    model='qwen-turbo',
    messages=[{'role': 'user', 'content': 'Hello'}]
)

# Extract token counts
input_tokens = response.usage.input_tokens
output_tokens = response.usage.output_tokens
total_cost = (input_tokens * 0.001 + output_tokens * 0.002) / 1000  # Approximate

print(f"Input tokens: {input_tokens}")
print(f"Output tokens: {output_tokens}")
print(f"Estimated cost: ¥{total_cost}")
```

### 5. Implement Retry Logic

```python
import time
from dashscope import Generation

def call_with_retry(model, messages, max_retries=3):
    for attempt in range(max_retries):
        try:
            response = Generation.call(model=model, messages=messages)
            if response.status_code == 200:
                return response
        except Exception as e:
            if attempt < max_retries - 1:
                wait_time = 2 ** attempt  # Exponential backoff
                print(f"Retry in {wait_time}s... ({attempt + 1}/{max_retries})")
                time.sleep(wait_time)
            else:
                raise e
    
    return None
```

## Troubleshooting

### Issue: "Invalid API Key"

**Solution:**
```python
# Verify API key is set
import os
print(os.environ.get('DASHSCOPE_API_KEY', 'NOT SET'))

# Check format starts with 'sk-'
assert key.startswith('sk-'), "API key should start with 'sk-'"
```

### Issue: Rate Limiting

**Solution:**
```python
import time
from functools import wraps

def rate_limit(calls_per_minute=10):
    min_interval = 60.0 / calls_per_minute
    last_called = [0.0]
    
    def decorator(func):
        def wrapper(*args, **kwargs):
            elapsed = time.time() - last_called[0]
            wait_time = min_interval - elapsed
            if wait_time > 0:
                time.sleep(wait_time)
            result = func(*args, **kwargs)
            last_called[0] = time.time()
            return result
        return wrapper
    return decorator

@rate_limit(calls_per_minute=30)
def call_qwen(prompt):
    return Generation.call(
        model='qwen-turbo',
        messages=[{'role': 'user', 'content': prompt}]
    )
```

### Issue: Connection Timeout

**Solution:**
```python
from dashscope import Generation

response = Generation.call(
    model='qwen-turbo',
    messages=[{'role': 'user', 'content': 'Hello'}],
    timeout=60  # Increase timeout from default 30s
)
```

### Issue: High Costs

**Solutions:**
1. Use `qwen-turbo` instead of `qwen-max`
2. Reduce output tokens with `max_tokens` parameter
3. Cache responses for repeated queries

```python
response = Generation.call(
    model='qwen-turbo',
    messages=[{'role': 'user', 'content': 'Summarize this...'}],
    max_tokens=200  # Limit output
)
```

---

## Next Steps

- 📓 [Hands-on Jupyter Notebook: Qwen Setup](../notebooks/01_qwen_setup.ipynb)
- 🏗️ [Use Qwen in RAG Pipeline](02-rag-detailed.md)
- 📊 [Monitor Costs with ARMS](../blog/05-observability-detailed.md)

**Reference:** [Official Qwen Documentation](https://dashscope.console.aliyun.com)
