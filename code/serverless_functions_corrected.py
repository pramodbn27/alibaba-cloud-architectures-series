# Correct Serverless Functions Implementation
import json
import logging
from datetime import datetime
from typing import Dict, Any


logger = logging.getLogger(__name__)


def image_processor_handler(event: Dict, context: Any) -> Dict:
    """Process images uploaded to OSS."""
    try:
        for record in event.get('Records', []):
            bucket = record['oss']['bucket']['name']
            key = record['oss']['object']['key']
            logger.info(f"Processing {bucket}/{key}")
            
        return {'statusCode': 200, 'body': json.dumps({'message': 'Processed'})}
    except Exception as e:
        logger.error(f"Error: {e}")
        return {'statusCode': 500, 'body': str(e)}


def data_transformation_handler(event: Dict, context: Any) -> Dict:
    """Transform data for analytics."""
    try:
        messages = event.get('Records', [])
        results = []
        
        for message in messages:
            data = json.loads(message['body'])
            transformed = {
                'timestamp': datetime.now().isoformat(),
                'original': data,
                'processed': True
            }
            results.append(transformed)
        
        return {'statusCode': 200, 'body': json.dumps({'processed': len(results)})}
    except Exception as e:
        logger.error(f"Error: {e}")
        return {'statusCode': 500}


class ServerlessCostAnalysis:
    """Estimate serverless costs."""
    
    @staticmethod
    def estimate_cost(monthly_invocations: int, avg_execution_ms: int, 
                     memory_mb: int = 512) -> Dict:
        execution_cost_per_gb_sec = 0.0000166
        gb_seconds = (memory_mb / 1024) * (avg_execution_ms / 1000) * monthly_invocations
        compute_cost = gb_seconds * execution_cost_per_gb_sec
        
        request_cost_per_million = 0.33
        requests_over_free = max(0, (monthly_invocations - 1_000_000) / 1_000_000)
        request_cost = requests_over_free * request_cost_per_million
        
        total_cost = compute_cost + request_cost
        
        return {
            'invocations': monthly_invocations,
            'execution_time_ms': avg_execution_ms,
            'memory_mb': memory_mb,
            'compute_cost': round(compute_cost, 2),
            'request_cost': round(request_cost, 2),
            'total_monthly_cost': round(total_cost, 2)
        }


if __name__ == '__main__':
    analysis = ServerlessCostAnalysis()
    cost = analysis.estimate_cost(100_000, 1000)
    print(f"Monthly cost: ¥{cost['total_monthly_cost']}")
