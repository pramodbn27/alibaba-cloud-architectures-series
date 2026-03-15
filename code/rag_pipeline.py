# RAG Pipeline Implementation
# Complete retrieval-augmented generation with Qwen + Hologres

import json
import numpy as np
import psycopg2
from typing import List, Dict, Optional, Tuple
from qwen_client import QwenClient


class RAGPipeline:
    """
    Retrieval-Augmented Generation pipeline.
    
    Combines:
    - Vector embeddings (Qwen)
    - Vector search (Hologres)
    - LLM answer generation (Qwen)
    """
    
    def __init__(self, db_config: Dict, embedder: QwenClient):
        self.db_config = db_config
        self.embedder = embedder
        self.conn = None
        self._connect()
    
    def _connect(self):
        """Connect to Hologres."""
        try:
            self.conn = psycopg2.connect(**self.db_config)
            logger.info("Connected to Hologres")
        except Exception as e:
            logger.error(f"Database connection failed: {e}")
            raise
    
    def setup_tables(self):
        """Create vector storage tables."""
        sql = """
        CREATE EXTENSION IF NOT EXISTS vector;
        
        CREATE TABLE IF NOT EXISTS documents (
            id SERIAL PRIMARY KEY,
            content TEXT NOT NULL,
            source VARCHAR(255),
            embedding vector(1536),
            metadata JSONB,
            created_at TIMESTAMP DEFAULT NOW()
        );
        
        CREATE INDEX IF NOT EXISTS idx_embedding ON documents 
        USING hnsw (embedding vector_cosine_ops);
        """
        
        try:
            cursor = self.conn.cursor()
            cursor.execute(sql)
            self.conn.commit()
            cursor.close()
            logger.info("Tables created successfully")
        except Exception as e:
            logger.error(f"Table creation failed: {e}")
            self.conn.rollback()
    
    def insert_documents(self, documents: List[Dict]):
        \"\"\"Insert documents with embeddings.\"\"\"
        
        cursor = self.conn.cursor()
        
        for doc in documents:
            # Generate embedding
            embedding = self.embedder.embed([doc['content']])[0]
            
            # Insert into database
            sql = \"\"\"
            INSERT INTO documents (content, source, embedding, metadata)
            VALUES (%s, %s, %s, %s)
            \"\"\"
            
            cursor.execute(sql, (
                doc['content'],
                doc.get('source', 'unknown'),
                np.array(embedding),
                json.dumps(doc.get('metadata', {}))
            ))
        
        self.conn.commit()
        cursor.close()
        logger.info(f"Inserted {len(documents)} documents")
    
    def search(self, query: str, top_k: int = 3, threshold: float = 0.7) -> List[Dict]:
        \"\"\"Search for similar documents.\"\"\"
        
        # Get query embedding
        query_embedding = self.embedder.embed([query], text_type='query')[0]
        
        # Search database
        cursor = self.conn.cursor()
        
        sql = \"\"\"
        SELECT id, content, source, 1 - (embedding <=> %s::vector) as similarity
        FROM documents
        WHERE 1 - (embedding <=> %s::vector) > %s
        ORDER BY similarity DESC
        LIMIT %s
        \"\"\"
        
        cursor.execute(sql, (
            json.dumps(query_embedding),
            json.dumps(query_embedding),
            threshold,
            top_k
        ))
        
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
    
    def answer(self, query: str, top_k: int = 3) -> Dict:
        \"\"\"Generate answer with retrieved context.\"\"\"
        
        # Step 1: Retrieve documents
        retrieved = self.search(query, top_k)
        
        if not retrieved:
            context = \"No relevant documents found.\"
            sources = []
        else:
            context = \"\\n\\n\".join([
                f\"[{doc['source']}]: {doc['content']}\"
                for doc in retrieved
            ])
            sources = [doc['source'] for doc in retrieved]
        
        # Step 2: Generate answer
        system_prompt = \"\"\"You are a helpful assistant. Answer questions based on the provided context.
If the context doesn't contain relevant information, say so.\"\"\"
        
        user_prompt = f\"\"\"Context:
{context}

Question: {query}

Answer:\"\"\"
        
        response = self.embedder.chat([
            {'role': 'system', 'content': system_prompt},
            {'role': 'user', 'content': user_prompt}
        ])
        
        return {
            'question': query,
            'answer': response,
            'sources': sources,
            'retrieved_count': len(retrieved)
        }
    
    def close(self):
        \"\"\"Close database connection.\"\"\"
        if self.conn:
            self.conn.close()


# Usage example
if __name__ == '__main__':
    import logging
    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)
    
    # Setup
    db_config = {
        'host': 'hologres.aliyuncs.com',
        'port': 50070,
        'database': 'hologres',
        'user': 'admin',
        'password': 'password'
    }
    
    embedder = QwenClient()
    rag = RAGPipeline(db_config, embedder)
    
    # Create tables
    rag.setup_tables()
    
    # Insert documents
    documents = [
        {'content': 'Alibaba Cloud offers ECS, RDS, and OSS services', 'source': 'services'},
        {'content': 'Qwen is a language model with strong Chinese understanding', 'source': 'qwen'}
    ]
    rag.insert_documents(documents)
    
    # Query
    result = rag.answer('What services does Alibaba Cloud offer?')
    print(json.dumps(result, indent=2, ensure_ascii=False))
    
    rag.close()
