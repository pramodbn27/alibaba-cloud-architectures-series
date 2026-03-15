# Building a RAG Pipeline with Qwen + Hologres (Quick Overview)

*Read time: 5 minutes*

## What is RAG?

**Retrieval-Augmented Generation** gives your LLM access to custom knowledge through semantic search + vector databases.

## Architecture in 30 Seconds

```
Documents → Embeddings → Hologres (Vector DB) → Semantic Search → Qwen → Answer
```

## Why Qwen + Hologres?

- ✅ **Qwen:** Fast Chinese embedding model
- ✅ **Hologres:** OLAP database with vector search
- ✅ **Integrated:** Alibaba Cloud ecosystem synergy

## Quick 3-Step Implementation

### 1. Prepare Documents
```python
documents = [
    "Alibaba Cloud is a cloud platform...",
    "Qwen is a large language model...",
    # ... more docs
]
```

### 2. Create Embeddings & Store
```python
from qwen import QwenEmbedding
from hologres import HologresClient

embeddings = QwenEmbedding.embed(documents)
hologres = HologresClient()
hologres.insert_vectors("documents", embeddings)
```

### 3. Query & Generate
```python
# Search similar documents
query = "What is Alibaba Cloud?"
results = hologres.search_vectors(query, top_k=3)

# Generate answer with context
context = "\n".join([r['text'] for r in results])
answer = qwen.chat(f"Context: {context}\nQuestion: {query}")
```

## Performance Tips

- **Chunk size:** 500-1000 tokens per document
- **Vector dimension:** 1536 (qwen-embedding)
- **Similarity threshold:** 0.7 for quality

## Cost Breakdown

| Component | Monthly Cost |
|-----------|------|
| Qwen API (100M tokens/mo) | $50-80 |
| Hologres (RI 4-core) | $100-150 |
| Storage (100GB) | $10 |
| **Total** | **$160-240** |

## Use Cases

- 📚 Documentation Q&A
- 💼 Internal knowledge bases
- 📄 Contract analysis
- 🏥 Medical information retrieval

---

→ [Detailed Guide: RAG Pipeline](02-rag-detailed.md)

→ [Hands-on: Run Notebook](../notebooks/02_rag_pipeline.ipynb)
