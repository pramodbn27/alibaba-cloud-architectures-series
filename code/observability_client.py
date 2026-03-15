# Observability & Monitoring Implementation
# ARMS + SLS integration

import json
import logging
from typing import Dict, List, Optional
from datetime import datetime, timedelta
import statistics


logger = logging.getLogger(__name__)


class MetricsCollector:
    """Collect and track application metrics."""
    
    def __init__(self, service_name: str):
        self.service_name = service_name
        self.metrics = {}
        self.logs = []
    
    def record_metric(self, metric_name: str, value: float, dimensions: Dict = None):
        """Record a metric value."""
        if metric_name not in self.metrics:
            self.metrics[metric_name] = []
        
        self.metrics[metric_name].append({
            'value': value,
            'timestamp': datetime.now().isoformat(),
            'dimensions': dimensions or {}
        })
    
    def get_percentile(self, metric_name: str, percentile: int) -> float:
        """Get percentile value of metric."""
        if metric_name not in self.metrics:
            return 0
        
        values = [m['value'] for m in self.metrics[metric_name]]
        if not values:
            return 0
        
        values.sort()
        index = int((percentile / 100) * len(values))
        return values[min(index, len(values) - 1)]
    
    def get_stats(self, metric_name: str) -> Dict:
        """Get statistics for a metric."""
        if metric_name not in self.metrics:
            return {}
        
        values = [m['value'] for m in self.metrics[metric_name]]
        
        return {
            'count': len(values),
            'min': min(values),
            'max': max(values),
            'avg': statistics.mean(values),
            'p50': self.get_percentile(metric_name, 50),
            'p95': self.get_percentile(metric_name, 95),
            'p99': self.get_percentile(metric_name, 99)
        }


class LogAggregator:
    """Aggregate and query logs."""
    
    def __init__(self, project_name: str):
        self.project_name = project_name
        self.logs = []
    
    def add_log(self, level: str, message: str, **kwargs):
        """Add structured log entry."""
        entry = {
            'timestamp': datetime.now().isoformat(),
            'level': level,
            'message': message,
            'service': kwargs.get('service', ''),
            'trace_id': kwargs.get('trace_id', ''),
            'user_id': kwargs.get('user_id', ''),
            'duration_ms': kwargs.get('duration_ms', 0)
        }
        self.logs.append(entry)
    
    def query_errors(self, last_n_minutes: int = 60) -> List[Dict]:
        """Query error logs."""
        cutoff = datetime.now() - timedelta(minutes=last_n_minutes)
        
        errors = [
            log for log in self.logs
            if log['level'] == 'ERROR' 
            and datetime.fromisoformat(log['timestamp']) > cutoff
        ]
        
        return sorted(errors, key=lambda x: x['timestamp'], reverse=True)
    
    def get_error_rate(self, minutes: int = 5) -> float:
        """Calculate error rate in last N minutes."""
        cutoff = datetime.now() - timedelta(minutes=minutes)
        
        recent = [
            log for log in self.logs
            if datetime.fromisoformat(log['timestamp']) > cutoff
        ]
        
        if not recent:
            return 0.0
        
        errors = len([log for log in recent if log['level'] == 'ERROR'])
        return (errors / len(recent)) * 100


class AlertRule:
    """Alert rule definition."""
    
    def __init__(self, name: str, condition_fn, threshold: float, 
                 period_minutes: int = 5):
        self.name = name
        self.condition_fn = condition_fn
        self.threshold = threshold
        self.period_minutes = period_minutes
        self.triggered_at = None
    
    def evaluate(self, metrics: MetricsCollector) -> bool:
        """Check if alert should trigger."""
        value = self.condition_fn(metrics)
        
        if value > self.threshold:
            self.triggered_at = datetime.now()
            return True
        
        return False
    
    def should_resolve(self) -> bool:
        """Check if alert has resolved."""
        if not self.triggered_at:
            return False
        
        elapsed = (datetime.now() - self.triggered_at).total_seconds() / 60
        return elapsed > self.period_minutes


class AlertingManager:
    """Manage alerts and notifications."""
    
    def __init__(self):
        self.rules: List[AlertRule] = []
        self.active_alerts = {}
        self.notification_channels = []
    
    def add_rule(self, rule: AlertRule):
        """Register an alert rule."""
        self.rules.append(rule)
    
    def add_notification_channel(self, channel_type: str, config: Dict):
        """Add notification channel (email, Slack, etc)."""
        self.notification_channels.append({
            'type': channel_type,
            'config': config
        })
    
    def evaluate_all(self, metrics: MetricsCollector):
        """Evaluate all alert rules."""
        for rule in self.rules:
            if rule.evaluate(metrics):
                if rule.name not in self.active_alerts:
                    self.active_alerts[rule.name] = {
                        'triggered_at': datetime.now(),
                        'count': 0
                    }
                    self._send_alert(rule.name, f"Alert triggered: {rule.name}")
                
                self.active_alerts[rule.name]['count'] += 1
                logger.warning(f"Alert: {rule.name}")
    
    def _send_alert(self, alert_name: str, message: str):
        """Send notifications to all channels."""
        for channel in self.notification_channels:
            if channel['type'] == 'email':
                # Send email
                pass
            elif channel['type'] == 'slack':
                # Send Slack message
                pass


# Example usage
if __name__ == '__main__':
    import random
    
    # Setup
    metrics = MetricsCollector('user-service')
    logs = LogAggregator('production')
    alerts = AlertingManager()
    
    # Add alert rule: Error rate > 5%
    error_rate_rule = AlertRule(
        name='high-error-rate',
        condition_fn=lambda m: logs.get_error_rate(),
        threshold=5.0
    )
    alerts.add_rule(error_rate_rule)
    
    # Simulate some events
    for i in range(100):
        latency = random.randint(10, 5000)
        status = 'SUCCESS' if random.random() > 0.05 else 'ERROR'
        
        metrics.record_metric('request_latency', latency)
        logs.add_log('INFO' if status == 'SUCCESS' else 'ERROR', 
                    f'Request {i}', service='api')
    
    # Get stats
    stats = metrics.get_stats('request_latency')
    print(f"Request latency stats:")
    print(json.dumps(stats, indent=2))
    
    # Evaluate alerts
    alerts.evaluate_all(metrics)
    print(f"\nActive alerts: {list(alerts.active_alerts.keys())}")
