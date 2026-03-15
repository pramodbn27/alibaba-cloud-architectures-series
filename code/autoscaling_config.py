# Auto-scaling Configuration
# ECS + SLB + RDS setup with monitoring

import json
from typing import Dict, List, Optional


class AutoScalingConfig:
    \"\"\"Generate auto-scaling configuration.\"\"\"
    
    @staticmethod
    def launch_template_config() -> Dict:
        \"\"\"Launch template for scaling group.\"\"\"
        return {
            'LaunchTemplateName': 'web-app-template',
            'ImageId': 'ubuntu-22.04-web',  # Custom image
            'InstanceType': 'ecs.n7.large',
            'KeyPairName': 'web-app-key',
            'SecurityGroupIds': ['sg-xxx'],
            'UserData': '''#!/bin/bash
cd /opt/web-app
python -m uvicorn main:app --host 0.0.0.0 --port 80
''',
            'TagSpecifications': [
                {
                    'ResourceType': 'instance',
                    'Tags': [
                        {'Key': 'Application', 'Value': 'web-app'},
                        {'Key': 'ManagedBy', 'Value': 'auto-scaling'}
                    ]
                }
            ]
        }
    
    @staticmethod
    def scaling_group_config() -> Dict:
        \"\"\"Auto-scaling group configuration.\"\"\"
        return {
            'AutoScalingGroupName': 'web-app-asg',
            'MinSize': 2,
            'MaxSize': 20,
            'DesiredCapacity': 4,
            'DefaultCooldown': 300,
            'HealthCheckType': 'ELB',
            'HealthCheckGracePeriod': 300,
            'VSwitchIds': ['vsw-xxx', 'vsw-yyy'],  # Multi-AZ
            'LoadBalancerIds': ['slb-xxx'],
            'Tags': {
                'Environment': 'production',
                'Application': 'web-app'
            }
        }
    
    @staticmethod
    def scaling_policies() -> List[Dict]:
        \"\"\"Scaling policies (scale up/down).\"\"\"
        return [
            {
                'PolicyName': 'scale-up-cpu-70',
                'AdjustmentType': 'ChangeInCapacity',
                'AdjustmentValue': 2,
                'Cooldown': 60,
                'Metric': 'CPUUtilization',
                'Threshold': 70,
                'ComparisonOperator': 'GreaterThanThreshold'
            },
            {
                'PolicyName': 'scale-down-cpu-30',
                'AdjustmentType': 'ChangeInCapacity',
                'AdjustmentValue': -1,
                'Cooldown': 300,
                'Metric': 'CPUUtilization',
                'Threshold': 30,
                'ComparisonOperator': 'LessThanThreshold'
            }
        ]
    
    @staticmethod
    def health_check_config() -> Dict:
        \"\"\"SLB health check configuration.\"\"\"
        return {
            'HealthCheck': 'on',
            'HealthCheckType': 'HTTP',
            'HealthCheckUri': '/health',
            'HealthCheckHttpCode': 'http_2xx,http_3xx',
            'HealthyThreshold': 3,
            'UnhealthyThreshold': 3,
            'HealthCheckInterval': 2,
            'HealthCheckConnectTimeout': 5
        }


class RDSOptimization:
    \"\"\"RDS optimization for high-concurrency scenarios.\"\"\"
    
    @staticmethod
    def connection_pooling_config() -> Dict:
        \"\"\"SQLAlchemy pool configuration.\"\"\"
        return {
            'poolclass': 'QueuePool',
            'pool_size': 20,  # Per instance
            'max_overflow': 10,
            'pool_recycle': 3600,
            'pool_pre_ping': True
        }
    
    @staticmethod
    def read_replica_config() -> List[Dict]:
        \"\"\"Read replica configurations.\"\"\"
        return [
            {
                'ReplicaName': 'app-db-replica-1-same-region',
                'SourceDB': 'app-db-primary',
                'Async': True
            },
            {
                'ReplicaName': 'app-db-replica-2-hongkong',
                'SourceDB': 'app-db-primary',
                'DestinationRegion': 'hk-hongkong',
                'Async': True
            }
        ]
    
    @staticmethod
    def optimization_sqls() -> List[str]:
        \"\"\"SQL optimizations for auto-scaling.\"\"\"
        return [
            # Add indexes for common queries
            'CREATE INDEX idx_user_id ON users(user_id, created_at)',
            'CREATE INDEX idx_order_status ON orders(status, created_at DESC)',
            
            # Enable query optimization
            'SET slow_query_log = ON',
            'SET long_query_time = 1',
            
            # Connection pooling settings
            'SET max_connections = 500',
            'SET shared_buffers = 256MB'
        ]


class LoadTestScenarios:
    \"\"\"Pre-configured load testing scenarios.\"\"\"
    
    @staticmethod
    def gradual_ramp() -> Dict:
        \"\"\"Gradually increase load.\"\"\"
        return {
            'name': 'Gradual Ramp',
            'stages': [
                {'duration': 60, 'target': 10},     # 1 min @ 10 req/s
                {'duration': 120, 'target': 50},    # 2 min @ 50 req/s
                {'duration': 180, 'target': 100},   # 3 min @ 100 req/s
                {'duration': 120, 'target': 50},    # Ramp down
                {'duration': 60, 'target': 10}
            ]
        }
    
    @staticmethod
    def spike_test() -> Dict:
        \"\"\"Sudden spike in traffic.\"\"\"
        return {
            'name': 'Spike Test',
            'stages': [
                {'duration': 30, 'target': 10},
                {'duration': 5, 'target': 500},     # Sudden spike
                {'duration': 30, 'target': 10}
            ]
        }


# Usage example
if __name__ == '__main__':
    # Generate configurations
    launch_config = AutoScalingConfig.launch_template_config()
    print(\"Launch Template Config:\")
    print(json.dumps(launch_config, indent=2))
    
    scaling_config = AutoScalingConfig.scaling_group_config()
    print(\"\\n\\nAuto-Scaling Group Config:\")
    print(json.dumps(scaling_config, indent=2))
    
    policies = AutoScalingConfig.scaling_policies()
    print(\"\\n\\nScaling Policies:\")
    print(json.dumps(policies, indent=2))
