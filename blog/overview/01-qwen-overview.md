# Getting Started with Qwen on Alibaba Cloud Model Studio (Quick Overview)

*Read time: 5 minutes*

## What is Qwen?

Qwen is Alibaba's advanced large language model family optimized for fast inferencing and low latency on Alibaba Cloud infrastructure.

## Prerequisites

- ✅ Alibaba Cloud account
- ✅ Model Studio API credentials
- ✅ Python 3.8+

## 5-Step Setup

### 1. Create API Key
```
Dashboard → Model Studio → API Keys → Create New
Save your: Access ID, Access Key
```

### 2. Install SDKs
```bash
pip install alibaba-cloud-tea-openapi alibaba-cloud-tea-util
```

### 3. Set Environment Variables
```bash
export QWEN_ACCESS_ID="your_access_id"
export QWEN_ACCESS_KEY="your_access_key"
export QWEN_ENDPOINT="https://qwen-api.cn-beijing.aliyuncs.com"
```

### 4. Make First Call
```python
from alibaba_cloud_qwen import QwenClient

client = QwenClient()
response = client.chat.completions.create(
    model="qwen-plus",
    messages=[{"role": "user", "content": "Hello Qwen!"}]
)
print(response.choices[0].message.content)
```

### 5. Choose Your Model

| Model | Latency | Context | Best For |
|-------|---------|---------|----------|
| qwen-turbo | 100ms | 8K | Real-time chat |
| qwen-plus | 200ms | 32K | Balanced |
| qwen-max | 500ms | 128K | Complex tasks |
| qwen-long | 1000ms | 1M | Document analysis |

## Model Comparison

**Qwen vs Competitors:**
- ✅ Faster on Alibaba Cloud by 30-50%
- ✅ Integrated with Alibaba services
- ✅ Lower latency for CN regions
- ⚠️ Context window smaller than GPT-4

## Next Steps

→ [Detailed Guide: Getting Started with Qwen](01-qwen-detailed.md)

→ [Hands-on: Run Jupyter Notebook](../notebooks/01_qwen_setup.ipynb)

## Cost Breakdown

- **Standard inference:** ¥0.001-0.008/1K tokens
- **First month:** Usually $30-50 for experimentation
- **Scaling:** Pricing drops at volume commitments

---

**Key Takeaway:** Qwen is production-ready within 15 minutes of setup. Perfect for prototyping AI applications on Alibaba Cloud.
