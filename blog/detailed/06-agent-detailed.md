# Agent-Native Infrastructure for AI Workloads (Detailed Guide)

*Read time: 20 minutes* 

## Table of Contents
1. [Agent Architecture](#architecture)
2. [GPU Instance Selection](#gpu-selection)
3. [Auto-scaling Configuration](#autoscaling)
4. [Event-Driven Framework](#event-driven)
5. [Multi-Agent Orchestration](#orchestration)
6. [Cost Optimization](#cost-optimization)

## Agent Architecture

### Single Agent Workflow

```
Request → Queue → Agent Container → LLM Call → Tool Use → Output → Storage
                     ↓
                  Memory/State
                  Knowledge Base
```

### Multi-Agent System

```
┌─────────────────────────────────────┐
│     Orchestrator (Coordinator)      │
│  (Routes tasks, manages workflows)  │
└────────────┬────────────────────────┘
             │
    ┌────────┼────────┐
    │        │        │
    ▼        ▼        ▼
  Agent1   Agent2   Agent3
  (LLM)    (LLM)    (LLM)
    │        │        │
    └────────┼────────┘
             ▼
        Action Queue
        (External tasks)
```

## GPU Instance Selection

### Alibaba Cloud GPU Options

```
g7-xilinx:      Xilinx FPGAs (specialized)
g7-gpu-x100:    NVIDIA L100 (best for LLMs)
g7-gpu-a100:    NVIDIA A100 (high throughput)
g7-gpu-v100:    NVIDIA V100 (balanced)
cu30-c8m32-g4:  NVIDIA A10 (cost-effective)
```

### Recommended for LLMs

```python
# Selection logic
def select_gpu_instance(requirements):
    if requirements['model_size'] > '13B':
        return 'g7-gpu-x100'  # L100 - 120GB VRAM
    elif requirements['model_size'] > '7B':
        return 'g7-gpu-a100'  # A100 - 80GB VRAM
    else:
        return 'cu30-c8m32-g4'  # A10 - 24GB VRAM (cost-effective)

# Launch instance
from alibabacloud_ecs20140526.client import Client as EcsClient

ecs = EcsClient(config)
ecs.run_instances({
    'ImageId': 'ubuntu-22.04-gpu',
    'InstanceType': 'g7.2xlarge',  # 2x L100
    'GPU': 2,
    'SecurityGroupId': 'sg-xxx',
    'VpcId': 'vpc-xxx'
})
```

## Auto-scaling Configuration

### Setup Scaling Group

```yaml
# Terraform or direct configuration
auto_scaling_group:
  name: agent-fleet
  launch_template:
    image_id: ami-gpu-qwen
    instance_type: g7.2xlarge
    gpu_count: 2
  desired_capacity: 1
  min_size: 1
  max_size: 10
  scaling_policies:
    - name: scale_up
      metric: queue_depth
      threshold: 100  # Queue length > 100
      adjustment: +2  # Add 2 instances
      cooldown: 300
    
    - name: scale_down
      metric: cpu_utilization
      threshold: 20
      adjustment: -1
      cooldown: 600
```

### Python Auto-scaling Controller

```python
import boto3
from datetime import datetime
from typing import Dict

class AgentAutoScaler:
    def __init__(self, group_name: str):
        self.asg_client = boto3.client('autoscaling')
        self.cloudwatch = boto3.client('cloudwatch')
        self.group_name = group_name
    
    def get_scaling_metrics(self) -> Dict:
        """Get current scaling metrics"""
        
        # Query message queue depth
        queue_depth = self.get_mq_depth()
        
        # Query CPU/GPU utilization
        stats = self.cloudwatch.get_metric_statistics(
            Namespace='AWS/EC2',
            MetricName='CPUUtilization',
            Dimensions=[
                {'Name': 'AutoScalingGroupName', 'Value': self.group_name}
            ],
            StartTime=datetime.utcnow() - timedelta(minutes=5),
            EndTime=datetime.utcnow(),
            Period=60,
            Statistics=['Average']
        )
        
        return {
            'queue_depth': queue_depth,
            'avg_cpu': stats['Datapoints'][0]['Average'] if stats['Datapoints'] else 0,
            'gpu_utilization': self.get_gpu_util()
        }
    
    def should_scale_up(self, metrics: Dict) -> bool:
        """Determine if we need more capacity"""
        return (
            metrics['queue_depth'] > 50 or 
            metrics['avg_cpu'] > 75 or 
            metrics['gpu_utilization'] > 80
        )
    
    def should_scale_down(self, metrics: Dict) -> bool:
        """Determine if we can reduce capacity"""
        return (
            metrics['queue_depth'] < 10 and 
            metrics['avg_cpu'] < 20
        )
    
    def scale_up(self, num_instances: int = 1):
        """Add instances"""
        response = self.asg_client.set_desired_capacity(
            AutoScalingGroupName=self.group_name,
            DesiredCapacity=self.get_current_capacity() + num_instances,
            HonorCooldown=True
        )
        print(f"Scaling up by {num_instances} instances")
    
    def scale_down(self, num_instances: int = 1):
        """Remove instances"""
        response = self.asg_client.set_desired_capacity(
            AutoScalingGroupName=self.group_name,
            DesiredCapacity=max(1, self.get_current_capacity() - num_instances),
            HonorCooldown=True
        )
        print(f"Scaling down by {num_instances} instances")
    
    def get_current_capacity(self) -> int:
        """Get current running instances"""
        response = self.asg_client.describe_auto_scaling_groups(
            AutoScalingGroupNames=[self.group_name]
        )
        return response['AutoScalingGroups'][0]['DesiredCapacity']
    
    def get_mq_depth(self) -> int:
        """Query message queue depth from MQ service"""
        # Implementation specific to your MQ solution
        pass
    
    def get_gpu_util(self) -> float:
        """Get GPU utilization across instances"""
        # Implementation specific to your monitoring
        pass

# Usage
scaler = AgentAutoScaler('agent-fleet')

def scaling_loop():
    while True:
        metrics = scaler.get_scaling_metrics()
        
        if scaler.should_scale_up(metrics):
            scaler.scale_up(num_instances=2)
        elif scaler.should_scale_down(metrics):
            scaler.scale_down(num_instances=1)
        
        time.sleep(60)
```

## Event-Driven Framework

### Message Queue Setup

```python
from aliyun.mq.consumer.push_consumer import PushConsumer

class AgentEventConsumer:
    def __init__(self):
        self.consumer = PushConsumer('agent-instance-id')
        self.consumer.set_namesrv_addr('mq-broker.aliyuncs.com:80')
    
    def subscribe_to_events(self):
        """Subscribe to agent tasks"""
        self.consumer.subscribe('agent-tasks', '*', self.handle_message)
        self.consumer.start()
    
    def handle_message(self, message):
        """Process incoming task"""
        task = json.loads(message.body)
        
        # Route to appropriate agent
        if task['type'] == 'analysis':
            result = self.run_analysis_agent(task)
        elif task['type'] == 'planning':
            result = self.run_planning_agent(task)
        else:
            result = self.run_default_agent(task)
        
        # Send result
        self.send_result(task['request_id'], result)
        
        return True  # Acknowledge
    
    def run_analysis_agent(self, task):
        """Run analysis agent with tool use"""
        from langchain.agents import AgentType, initialize_agent, load_tools
        from langchain.chat_models import ChatOpenAI
        
        llm = ChatOpenAI(model="gpt-4", temperature=0)
        tools = load_tools(["python_repl", "wikipedia"])
        
        agent = initialize_agent(
            tools,
            llm,
            agent=AgentType.CHAT_ZERO_SHOT_REACT_DESCRIPTION,
            verbose=True
        )
        
        return agent.run(task['prompt'])
```

## Multi-Agent Orchestration

### Agent Coordinator

```python
from typing import List, Dict
from enum import Enum

class TaskStatus(Enum):
    PENDING = 'pending'
    ASSIGNED = 'assigned'
    IN_PROGRESS = 'in_progress'
    COMPLETED = 'completed'
    FAILED = 'failed'

class AgentOrchestrator:
    def __init__(self, num_agents: int = 3):
        self.agents = [f'agent-{i}' for i in range(num_agents)]
        self.task_queue = []
        self.tasks = {}  # task_id -> Task
    
    def submit_task(self, task_type: str, prompt: str, deadline_seconds: int = 300):
        """Submit a task for processing"""
        task_id = str(uuid.uuid4())
        
        task = {
            'id': task_id,
            'type': task_type,
            'prompt': prompt,
            'status': TaskStatus.PENDING,
            'created_at': time.time(),
            'deadline': time.time() + deadline_seconds
        }
        
        self.tasks[task_id] = task
        self.task_queue.append(task)
        
        return task_id
    
    def orchestrate(self):
        """Main orchestration loop"""
        while self.task_queue:
            task = self.task_queue.pop(0)
            
            # Route to best available agent
            agent = self.select_agent(task)
            if not agent:
                self.task_queue.append(task)  # Requeue
                continue
            
            # Assign task
            self.assign_task_to_agent(agent, task)
            task['status'] = TaskStatus.ASSIGNED
            task['assigned_agent'] = agent
            task['assigned_at'] = time.time()
    
    def select_agent(self, task: Dict) -> str:
        """Select best agent for task"""
        # Could use different strategies:
        # - Load-based: Least loaded agent
        # - Sequence-based: Round-robin
        # - Capability-based: Agent specialized for task type
        
        return min(self.agents, key=self.get_agent_load)
    
    def get_agent_load(self, agent_id: str) -> float:
        """Get current load on agent"""
        active_tasks = [t for t in self.tasks.values() 
                       if t.get('assigned_agent') == agent_id 
                       and t['status'] == TaskStatus.IN_PROGRESS]
        return len(active_tasks)
    
    def assign_task_to_agent(self, agent_id: str, task: Dict):
        """Send task to agent via queue"""
        message = json.dumps(task)
        # Send to MQ topic for specific agent
        self.mq_producer.send_message(
            topic=f'agent-tasks-{agent_id}',
            message=message
        )
    
    def handle_completion(self, task_id: str, result: Dict):
        """Handle task completion"""
        task = self.tasks[task_id]
        task['status'] = TaskStatus.COMPLETED
        task['result'] = result
        task['completed_at'] = time.time()
        
        # Store result
        self.store_result(task_id, result)
```

## Cost Optimization

### Strategies

```python
# 1. Spot Instances (up to 70% discount)
spot_config = {
    'instance_type': 'g7.2xlarge',
    'purchase_type': 'spot',
    'max_price': 'auto'  # Up to on-demand price
}

# 2. Reserved Instances (commit to 1-year)
reserved_config = {
    'instance_type': 'g7.2xlarge',
    'purchase_type': 'reserved',
    'duration': '1y',
    'upfront_fee': True  # Pay upfront for max discount
}

# 3. Mixed strategy
def get_cheapest_instance():
    prices = {
        'on_demand': 2.50,  # $/hour
        'spot': 0.75,       # 70% discount
        'reserved': 1.25    # 50% discount
    }
    return min(prices, key=prices.get)

# 4. Model batching to improve GPU utilization
def batch_inference(tasks: List[Dict], batch_size: int = 8):
    """Process multiple tasks on single GPU"""
    for i in range(0, len(tasks), batch_size):
        batch = tasks[i:i+batch_size]
        results = model.batch_forward(batch)
        yield results
```

---

## Next Steps

- 🏗️ [Deploy with Terraform](../terraform/agent-infrastructure/main.tf)
- 📊 [Monitor Agents with ARMS](../blog/05-observability-detailed.md)
- 🤖 [LangChain Agent Examples](../code/agent_examples.py)

**Reference:** [LangChain Docs](https://python.langchain.com/docs/agents) | [AutoGen](https://microsoft.github.io/autogen)
