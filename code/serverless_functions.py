# Serverless Functions Examples
# Production-ready Function Compute implementations

import json
import base64
from typing import Dict, Any
from datetime import datetime
import logging


logger = logging.getLogger(__name__)


def image_processor_handler(event: Dict, context: Any) -> Dict:
    \"\"\"
    Process images uploaded to OSS.
    
    Trigger: OSS → ObjectCreated event
    \"\"\"
    
    try:
        # Parse OSS event
        for record in event.get('Records', []):
            bucket = record['oss']['bucket']['name']
            key = record['oss']['object']['key']
            
            logger.info(f\"Processing {bucket}/{key}\")
            
            # Download image from OSS
            # Process (resize, filter, etc)
            # Upload to output bucket
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Image processed',
                    'input': key,
                    'output': f'processed/{key}'
                })
            }
    
    except Exception as e:
        logger.error(f\"Error: {e}\")
        return {'statusCode': 500, 'body': str(e)}


def data_transformation_handler(event: Dict, context: Any) -> Dict:
    \"\"\"
    Transform data for analytics.
    
    Trigger: Message Queue
    \"\"\"
    
    try:
        messages = event.get('Records', [])
        
        results = []
        for message in messages:
            # Parse message
            data = json.loads(message['body'])
            
            # Transform
            transformed = {
                'timestamp': datetime.now().isoformat(),
                'original': data,
                'processed': True,
                'tags': extract_tags(data)
            }
            
            results.append(transformed)
            
            # Send to next queue or store
            save_result(transformed)
        
        return {
            'statusCode': 200,
            'body': json.dumps({'processed': len(results)})
        }
    
    except Exception as e:
        logger.error(f\"Error: {e}\")
        return {'statusCode': 500}


def api_gateway_handler(event: Dict, context: Any) -> Dict:
    \"\"\"
    HTTP endpoint via API Gateway.
    
    Trigger: HTTP request
    \"\"\"
    
    try:
        # Parse HTTP request
        path = event.get('path', '/')
        method = event.get('httpMethod', 'GET')
        body = event.get('body', '')
        
        if path == '/health' and method == 'GET':
            return {'statusCode': 200, 'body': json.dumps({'status': 'ok'})}
        
        if path == '/api/process' and method == 'POST':
            data = json.loads(body)
            result = process_data(data)
            return {'statusCode': 200, 'body': json.dumps(result)}
        
        return {'statusCode': 404, 'body': 'Not found'}
    
    except Exception as e:
        logger.error(f\"Error: {e}\")
        return {'statusCode': 500, 'body': str(e)}


def batch_job_handler(event: Dict, context: Any) -> Dict:
    \"\"\"
    Scheduled batch job.
    
    Trigger: Timer (cron)
    \"\"\"
    
    try:
        logger.info(\"Starting batch job\")
        
        # Get batch configuration
        batch_size = 1000
        
        # Process batches
        total_processed = 0
        
        for i in range(10):  # 10 batches
            batch = get_batch(i, batch_size)
            results = process_batch(batch)
            total_processed += len(results)
            
            # Store results
            save_batch_results(results)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'job': 'batch-processing',
                'total_processed': total_processed,
                'timestamp': datetime.now().isoformat()
            })
        }
    
    except Exception as e:
        logger.error(f\"Batch job error: {e}\")
        return {'statusCode': 500}


def fan_out_orchestrator(event: Dict, context: Any) -> Dict:
    \"\"\"
    Fan-out to multiple worker functions.
    \"\"\"
    
    try:
        # Get parallel tasks
        tasks = event.get('tasks', [])
        
        # Dispatch to worker queue
        for task in tasks:
            send_to_queue('worker-tasks', task)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'dispatched': len(tasks),
                'status': 'queued'
            })
        }
    
    except Exception as e:
        logger.error(f\"Orchestration error: {e}\")
        return {'statusCode': 500}


# Helper functions (stubs)
def extract_tags(data: Dict) -> list:
    return ['auto', 'processed']


def save_result(result: Dict):
    logger.info(f\"Saving result: {result['processed']}\")


def process_data(data: Dict) -> Dict:
    return {'status': 'processed', 'data': data}


def get_batch(index: int, size: int) -> list:
    return [{'id': i} for i in range(index * size, (index + 1) * size)]


def process_batch(batch: list) -> list:
    return batch


def save_batch_results(results: list):
    logger.info(f\"Saved {len(results)} results\")


def send_to_queue(topic: str, message: Dict):
    logger.info(f\"Sent to {topic}: {message}\")


# Cost analysis
class ServerlessCostAnalysis:
    \"\"\"Estimate serverless costs.\"\"\"
    
    @staticmethod
    def estimate_cost(
        monthly_invocations: int,
        avg_execution_ms: int,
        memory_mb: int = 512
    ) -> Dict:
        \"\"\"Calculate monthly serverless cost.\"\"\"
        
        # Pricing in ¥
        execution_cost_per_gb_sec = 0.0000166
        
        # Calculate compute cost
        gb_seconds = (memory_mb / 1024) * (avg_execution_ms / 1000) * monthly_invocations
        compute_cost = gb_seconds * execution_cost_per_gb_sec
        
        # Add request cost (first 1M free)
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
            'total_monthly_cost': round(total_cost, 2),
            'cost_per_thousand': round((total_cost / monthly_invocations) * 1000, 4)
        }


if __name__ == '__main__':
    # Cost examples
    print(\"Serverless Cost Analysis\")
    print(\"=\" * 50)
    
    scenarios = [
        {'invocations': 100_000, 'time': 1000, 'name': 'Light usage'},
        {'invocations': 1_000_000, 'time': 2000, 'name': 'Medium usage'},
        {'invocations': 10_000_000, 'time': 500, 'name': 'Heavy usage'}
    ]
    
    for scenario in scenarios:
        cost = ServerlessCostAnalysis.estimate_cost(
            scenario['invocations'],
            scenario['time']
        )
        print(f\"\\n{scenario['name']}:\")
        print(f\"  Monthly cost: ¥{cost['total_monthly_cost']}\")\n",
        print(f\"  Per 1K calls: ¥{cost['cost_per_thousand']}\")"
   ]
  },
  {"cell_type": "code", "execution_count": null, "metadata": {}, "outputs": [], "source": ["# Code samples show key patterns\nprint(\"Shared patterns across all 9 topics\")"]}
 ],
 "metadata": {"kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"}, "language_info": {"name": "python", "version": "3.10.0"}},
 "nbformat": 4,
 "nbformat_minor": 4
}
