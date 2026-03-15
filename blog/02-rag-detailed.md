# Building a RAG Pipeline with Qwen + Hologres (Detailed Guide)

*Read time: 20 minutes*

## Table of Contents
1. [Architecture Overview](#architecture)
2. [Setting Up Hologres](#hologres-setup)
3. [Creating Embeddings](#embeddings)
4. [Vector Storage & Indexing](#indexing)
5. [Retrieval & Generation](#retrieval)
6. [Production Optimization](#optimization)
7. [Evaluation Metrics](#metrics)

## Architecture Overview

```
┌─────────────────┐
│  Raw Documents  │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────┐
│ Qwen Embedding Model        │
│ (Generates 1536-dim vectors)│
└────────┬────────────────────┘
         │
         ▼
┌──────────────────────────────┐
│ Hologres with Vector Index   │
│ (Fast similarity search)     │
└────────┬─────────────────────┘
         │
    ┌────┴────┐
    │ Query   │
    └────┬────┘
         │
         ▼
┌─────────────────────────┐
│ Semantic Search         │
│ (Top-K retrieval)       │
└────────┬────────────────┘
         │
         ▼
┌────────────────────────────────┐
│ Prompt + Context               │
│ Feed to Qwen                   │
└────────┬───────────────────────┘
         │
         ▼
┌────────────────────────────┐
│ Qwen Response with Sources │
└────────────────────────────┘
```

## Setting Up Hologres

### Prerequisites

- Alibaba Cloud account
- Hologres instance (starts at ¥100/month)
- 4-core MemoryEngine recommended

### Step 1: Create Hologres Instance

```sql
-- Via Alibaba Cloud Console

-- After instance is created, connect:
psql -h holo-instance.aliyuncs.com \
     -U admin \
     -d default_db \
     -p 50070
```

### Step 2: Create Vector Table

```sql
-- Connect to Hologres
CREATE EXTENSION vector;

-- Create documents table with vectors
CREATE TABLE documents (
    id SERIAL PRIMARY KEY,
    content TEXT NOT NULL,
    source VARCHAR(255),
    embedding VECTOR(1536),  -- Qwen embedding dimension
    created_at TIMESTAMP DEFAULT NOW(),
    CONSTRAINT embedding_check CHECK (array_length(embedding, 1) = 1536)
);

-- Create HNSW index for fast similarity search
CREATE INDEX ON documents USING hnsw (embedding vector_cosine_ops)
WITH (m=32, ef_construction=200);

-- Create additional index on source for filtering
CREATE INDEX idx_documents_source ON documents(source);
```

### Step 3: Test Connection

```python
import psycopg2
from psycopg2.extras import execute_values

# Connection parameters
conn = psycopg2.connect(
    host="holo-instance.aliyuncs.com",
    port=50070,
    database="default_db",
    user="admin",
    password="your_password"
)

cursor = conn.cursor()
cursor.execute("SELECT VERSION();")
print(cursor.fetchone())
cursor.close()
conn.close()
```

## Creating Embeddings

### Step 1: Prepare Documents

```python
from typing import List, Dict

def load_documents(source: str) -> List[Dict]:
    """Load and chunk documents"""
    documents = []
    
    # Example: Load from markdown files
    import os
    for file in os.listdir(source):
        if file.endswith('.md'):
            with open(os.path.join(source, file)) as f:
                content = f.read()
                # Chunk into ~500 token segments
                chunks = chunk_text(content, chunk_size=500)
                for i, chunk in enumerate(chunks):
                    documents.append({
                        'content': chunk,
                        'source': f"{file}:chunk_{i}",
                        'metadata': {'file': file, 'chunk': i}
                    })
    
    return documents

def chunk_text(text: str, chunk_size: int = 500) -> List[str]:
    """Split text into chunks"""
    tokens = text.split()
    chunks = []
    for i in range(0, len(tokens), chunk_size):
        chunk = ' '.join(tokens[i:i+chunk_size])
        if len(chunk.split()) < 50:  # Skip very small chunks
            continue
        chunks.append(chunk)
    return chunks

# Load documents
docs = load_documents('./data')
print(f"Loaded {len(docs)} document chunks")
```

### Step 2: Generate Embeddings with Qwen

```python
from dashscope import TextEmbedding
import os

class QwenEmbedder:
    def __init__(self):
        self.model = 'text-embedding-v1'  # 1536 dimensions
        self.batch_size = 25
    
    def embed_texts(self, texts: List[str]) -> List[List[float]]:
        """Generate embeddings in batches"""
        embeddings = []
        
        for i in range(0, len(texts), self.batch_size):
            batch = texts[i:i+self.batch_size]
            
            response = TextEmbedding.call(
                model=self.model,
                input=batch,
                text_type='document'
            )
            
            if response.status_code == 200:
                for embedding in response.output:
                    embeddings.append(embedding['embedding'])
            else:
                print(f"Error: {response.code}")
        
        return embeddings
    
    def embed_query(self, query: str) -> List[float]:
        """Embed a query (uses different type parameter)"""
        response = TextEmbedding.call(
            model=self.model,
            input=query,
            text_type='query'
        )
        
        if response.status_code == 200:
            return response.output[0]['embedding']
        else:
            raise Exception(f"Embedding error: {response.code}")

# Generate embeddings
embedder = QwenEmbedder()
texts = [doc['content'] for doc in docs]
embeddings = embedder.embed_texts(texts)

print(f"Generated {len(embeddings)} embeddings")
print(f"Embedding dimension: {len(embeddings[0])}")
```

## Vector Storage & Indexing

### Insert Embeddings into Hologres

```python
import psycopg2
from psycopg2.extras import execute_values
import numpy as np

class HologresVectorStore:
    def __init__(self, connection_params: Dict):
        self.conn = psycopg2.connect(**connection_params)
    
    def insert_vectors(self, table: str, documents: List[Dict], embeddings: List[List[float]]):
        """Insert documents with embeddings"""
        cursor = self.conn.cursor()
        
        data = [
            (
                doc['content'],
                doc['source'],
                np.array(embedding)  # PostgreSQL vector format
            )
            for doc, embedding in zip(documents, embeddings)
        ]
        
        # Bulk insert
        values_sql = ",".join(["%s"] * 3)
        insert_sql = f"""
            INSERT INTO documents (content, source, embedding) 
            VALUES ({values_sql})
        """
        
        execute_values(cursor, insert_sql, data, page_size=100)
        self.conn.commit()
        cursor.close()
        
        print(f"Inserted {len(data)} documents")
    
    def search(self, query_embedding: List[float], top_k: int = 3, threshold: float = 0.7) -> List[Dict]:
        """Search similar documents using vector similarity"""
        cursor = self.conn.cursor()
        
        # Convert to PostgreSQL format
        query_vector = np.array(query_embedding)
        
        # Cosine similarity search
        cursor.execute("""
            SELECT id, content, source, 1 - (embedding <=> %s) as similarity
            FROM documents
            WHERE 1 - (embedding <=> %s) > %s
            ORDER BY similarity DESC
            LIMIT %s
        """, (query_vector, query_vector, threshold, top_k))
        
        results = []
        for row in cursor.fetchall():
            results.append({
                'id': row[0],
                'content': row[1],
                'source': row[2],
                'similarity': row[3]
            })
        
        cursor.close()
        return results
    
    def close(self):
        self.conn.close()

# Initialize vector store
holo_params = {
    'host': 'holo-instance.aliyuncs.com',
    'port': 50070,
    'database': 'default_db',
    'user': 'admin',
    'password': 'your_password'
}

vector_store = HologresVectorStore(holo_params)

# Insert vectors
vector_store.insert_vectors('documents', docs, embeddings)
```

## Retrieval & Generation

### Complete RAG Pipeline

```python
from dashscope import Generation, TextEmbedding

class RAGPipeline:
    def __init__(self, vector_store, embedder):
        self.vector_store = vector_store
        self.embedder = embedder
    
    def answer_question(self, question: str, top_k: int = 3) -> Dict:
        """Complete RAG workflow"""
        
        # Step 1: Embed query
        query_embedding = self.embedder.embed_query(question)
        
        # Step 2: Retrieve similar documents
        retrieved_docs = self.vector_store.search(
            query_embedding, 
            top_k=top_k, 
            threshold=0.7
        )
        
        if not retrieved_docs:
            context = "No relevant documents found."
            sources = []
        else:
            # Build context
            context = "\n\n".join([
                f"[Source: {doc['source']}]\n{doc['content']}" 
                for doc in retrieved_docs
            ])
            sources = [doc['source'] for doc in retrieved_docs]
        
        # Step 3: Generate answer with Qwen
        system_prompt = """You are a helpful assistant with access to a knowledge base.
Use the provided context to answer questions accurately. 
If the context doesn't contain relevant information, say so."""
        
        response = Generation.call(
            model='qwen-turbo',
            messages=[
                {'role': 'system', 'content': system_prompt},
                {'role': 'user', 'content': f"""Context from knowledge base:
{context}

Question: {question}

Provide a clear, concise answer based on the context."""}
            ]
        )
        
        if response.status_code == 200:
            answer = response.output.choices[0].message.content
        else:
            answer = f"Error: {response.code}"
        
        return {
            'question': question,
            'answer': answer,
            'sources': sources,
            'context': context,
            'retrieved_count': len(retrieved_docs)
        }

# Initialize RAG pipeline
rag = RAGPipeline(vector_store, embedder)

# Ask questions
questions = [
    "What services does Alibaba Cloud offer?",
    "How do I create a RAG pipeline?",
    "What is Hologres used for?"
]

for q in questions:
    result = rag.answer_question(q)
    print(f"\nQ: {result['question']}")
    print(f"A: {result['answer']}")
    print(f"Sources: {result['sources']}")
```

## Production Optimization

### 1. Batch Processing

```python
def batch_embed_and_store(documents: List[Dict], batch_size: int = 1000):
    """Process large document sets efficiently"""
    
    for i in range(0, len(documents), batch_size):
        batch = documents[i:i+batch_size]
        texts = [doc['content'] for doc in batch]
        
        # Embed batch
        embeddings = embedder.embed_texts(texts)
        
        # Store batch
        vector_store.insert_vectors('documents', batch, embeddings)
        
        print(f"Processed {min(i+batch_size, len(documents))}/{len(documents)}")
```

### 2. Caching for Repeated Queries

```python
from functools import lru_cache
import json

class CachedRAG(RAGPipeline):
    def __init__(self, vector_store, embedder, cache_size=1000):
        super().__init__(vector_store, embedder)
        self.cache = {}
    
    def answer_question(self, question: str, top_k: int = 3) -> Dict:
        """Check cache before querying"""
        cache_key = f"{question}:{top_k}"
        
        if cache_key in self.cache:
            return self.cache[cache_key]
        
        result = super().answer_question(question, top_k)
        self.cache[cache_key] = result
        
        # Limit cache size
        if len(self.cache) > 1000:
            self.cache.pop(next(iter(self.cache)))
        
        return result
```

### 3. Async Processing

```python
import asyncio

async def async_rag_query(questions: List[str]) -> List[Dict]:
    """Process multiple questions concurrently"""
    tasks = [
        asyncio.to_thread(rag.answer_question, q)
        for q in questions
    ]
    return await asyncio.gather(*tasks)

# Usage
results = asyncio.run(async_rag_query(questions))
```

## Evaluation Metrics

### Key Metrics

```python
class RAGEvaluator:
    def __init__(self, rag_pipeline):
        self.rag = rag_pipeline
    
    def evaluate_retrieval(self, questions: List[str], ground_truth: List[List[str]]):
        """Evaluate retrieval quality"""
        
        total_recall = 0
        total_precision = 0
        
        for q, gt_sources in zip(questions, ground_truth):
            _, retrieved = self.rag.answer_question(q)
            retrieved_sources = set([r['source'] for r in retrieved])
            
            if not gt_sources:
                continue
            
            # Recall: fraction of relevant docs retrieved
            recall = len(retrieved_sources & set(gt_sources)) / len(gt_sources)
            
            # Precision: fraction of retrieved docs that are relevant
            precision = len(retrieved_sources & set(gt_sources)) / len(retrieved_sources) if retrieved_sources else 0
            
            total_recall += recall
            total_precision += precision
        
        return {
            'avg_recall': total_recall / len(questions),
            'avg_precision': total_precision / len(questions)
        }

# Evaluate
evaluator = RAGEvaluator(rag)
metrics = evaluator.evaluate_retrieval(
    questions,
    [['doc1', 'doc2'], ['doc3'], ['doc1', 'doc3']]
)
print(f"Recall: {metrics['avg_recall']:.2f}")
print(f"Precision: {metrics['avg_precision']:.2f}")
```

---

## Next Steps

- 🏗️ [Terraform: Deploy RAG Infrastructure](../terraform/rag-infrastructure/main.tf)
- 📊 [Monitor with ARMS](../blog/05-observability-detailed.md)
- 🔄 [Real-time Updates with Flink](03-flink-detailed.md)

**Reference:** [Hologres Docs](https://www.alibabacloud.com/help/hologres) | [Qwen API](https://dashscope.cn)
