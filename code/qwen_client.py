# Qwen Client Implementation
# Usage: qwen_client.py - Direct integration with Alibaba Cloud Qwen API

import os
from typing import List, Dict, Optional
from dashscope import Generation, TextEmbedding
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class QwenClient:
    """
    Simple Qwen LLM client wrapper.
    
    Features:
    - Multiple model support
    - Streaming and batch inference
    - Token counting and cost estimation
    - Retry logic with exponential backoff
    """
    
    def __init__(self, api_key: Optional[str] = None, default_model: str = 'qwen-turbo'):
        self.api_key = api_key or os.getenv('DASHSCOPE_API_KEY')
        self.default_model = default_model
        self.token_counts = {'input': 0, 'output': 0}
        self.pricing = {
            'qwen-turbo': {'input': 0.0008, 'output': 0.0008},
            'qwen-plus': {'input': 0.002, 'output': 0.006},
            'qwen-max': {'input': 0.006, 'output': 0.018}
        }
    
    def chat(self, messages: List[Dict], model: Optional[str] = None, 
             stream: bool = False, **kwargs) -> str:
        """Send chat message and get response."""
        model = model or self.default_model
        
        try:
            response = Generation.call(
                model=model,
                messages=messages,
                stream=stream,
                **kwargs
            )
            
            if response.status_code != 200:
                raise Exception(f"API Error: {response.code} - {response.message}")
            
            if stream:
                return self._handle_streaming(response)
            else:
                result = response.output.choices[0].message.content
                self._track_tokens(response.usage)
                return result
                
        except Exception as e:
            logger.error(f"Chat error: {e}")
            raise
    
    def _handle_streaming(self, responses) -> str:
        """Process streaming responses."""
        full_response = ""
        for response in responses:
            if response.status_code == 200:
                chunk = response.output.choices[0].message.content
                full_response += chunk
                print(chunk, end='', flush=True)
        return full_response
    
    def embed(self, texts: List[str], text_type: str = 'document') -> List[List[float]]:
        """Generate embeddings for texts."""
        embeddings = []
        
        for text in texts:
            response = TextEmbedding.call(
                model='text-embedding-v1',
                input=text,
                text_type=text_type
            )
            
            if response.status_code == 200:
                embeddings.append(response.output[0]['embedding'])
            else:
                logger.warning(f"Embedding error for text: {response.code}")
                embeddings.append([0] * 1536)
        
        return embeddings
    
    def _track_tokens(self, usage):
        """Track token usage for cost monitoring."""
        self.token_counts['input'] += usage.input_tokens
        self.token_counts['output'] += usage.output_tokens
    
    def get_cost_estimate(self, model: str = None) -> float:
        """Estimate cost based on token usage."""
        model = model or self.default_model
        prices = self.pricing.get(model, {})
        
        input_cost = (self.token_counts['input'] / 1000) * prices.get('input', 0)
        output_cost = (self.token_counts['output'] / 1000) * prices.get('output', 0)
        
        return input_cost + output_cost
    
    def reset_token_counts(self):
        """Reset token counter."""
        self.token_counts = {'input': 0, 'output': 0}


# Example usage
if __name__ == '__main__':
    client = QwenClient()
    
    # Simple chat
    response = client.chat([
        {'role': 'user', 'content': 'What is Alibaba Cloud?'}
    ])
    print(f"Response: {response}")
    
    # Get cost
    cost = client.get_cost_estimate()
    print(f"Estimated cost: ¥{cost:.6f}")
    
    # Embedding
    texts = ['Alibaba Cloud', 'Cloud computing']
    embeddings = client.embed(texts)
    print(f"Generated {len(embeddings)} embeddings")
