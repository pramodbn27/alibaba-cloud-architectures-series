# Multi-region Failover Architecture on Alibaba Cloud (Detailed Guide)

*Read time: 20 minutes*

## Table of Contents
1. [Failover Concepts](#concepts)
2. [GSLB Setup](#gslb)
3. [Database Replication](#replication)
4. [Health Monitoring](#health)
5. [Failover Testing](#testing)
6. [Compliance & Disaster Recovery](#compliance)

## Failover Concepts

### RTO vs RPO

```
┌─────────────────────────────────────┐
│ Data Loss Window (RPO)              │
├─────────────────────────────────────┤
│  Failure                Data Restore │
│  Detected               Complete    │
│  │◄─────────────────────►│                │
│  ├─────────────────────────────────────┤
│  │  Service Down (RTO)                 │
│  │  │◄──────────────────►│                │
│  │  │ Failover            Service       │
│  ▼  ▼ Triggered          Online        │
```

- **RPO = 1 min:** At most 1 minute of data loss
- **RTO = 5 min:** Service back online within 5 minutes

### Active-Active Pattern

```
User Request
    │
    ▼
  GSLB (Health Check)
    │
    ├─ Region A OK?    → Route to A
    ├─ Region B OK?    → Route to B
    └─ Both OK?        → Load balance
```

## GSLB Setup

### 1. Create Domains

```bash
# Primary domain for all regions
aliyun alidns AddDomain --DomainName "app.example.com"

# Regional subdomains
aliyun alidns AddDomain --DomainName "beijing.app.example.com"
aliyun alidns AddDomain --DomainName "shanghai.app.example.com"
aliyun alidns AddDomain --DomainName "hongkong.app.example.com"
```

### 2. Configure GSLB Policy

```python
from alibabacloud_alb_open20200616.client import Client as AlbClient
from alibabacloud_tea_openapi import models as open_api_models

class GlobalLoadBalancer:
    def __init__(self):
        config = open_api_models.Config(
            access_key_id='xxx',
            access_key_secret='xxx',
            region_id='cn-beijing'
        )
        self.client = AlbClient(config)
    
    def create_gslb_policy(self):
        """Create geographic load balancing"""
        
        # Define regional endpoints
        endpoints = [
            {
                'region': 'cn-beijing',
                'ip': '203.0.113.1',
                'weight': 50,  # Primary
                'health_check': True
            },
            {
                'region': 'cn-shanghai',
                'ip': '203.0.113.2',
                'weight': 40,
                'health_check': True
            },
            {
                'region': 'hk-hongkong',
                'ip': '203.0.113.3',
                'weight': 10,  # Backup
                'health_check': True
            }
        ]
        
        # Configure routing policy
        routing_policy = {
            'type': 'geo_proximity',  # Route by geography
            'failover_type': 'most_preferred',  # Prefer primary
            'endpoints': endpoints
        }
        
        return routing_policy
    
    def configure_health_checks(self):
        """Setup health checking for all regions"""
        
        health_check_config = {
            'interval': 10,  # Check every 10 seconds
            'timeout': 5,    # Fail if no response in 5s
            'unhealthy_threshold': 3,  # Mark down after 3 failures
            'healthy_threshold': 2,    # Mark up after 2 successes
            'type': 'HTTPS',
            'path': '/health',
            'port': 443
        }
        
        # Apply to all endpoints
        for endpoint in self.endpoints:
            self.setup_health_check(endpoint, health_check_config)
```

### 3. Health Check Endpoint

```python
from fastapi import FastAPI
from sqlalchemy import create_engine

app = FastAPI()

class HealthChecker:
    def __init__(self):
        self.db_engine = create_engine('postgresql://...')
    
    @app.get('/health')
    async def health_check(self):
        """Comprehensive health check"""
        
        health_status = {
            'status': 'healthy',
            'components': {}
        }
        
        # Check database
        try:
            with self.db_engine.connect() as conn:
                conn.execute('SELECT 1')
            health_status['components']['database'] = 'ok'
        except Exception as e:
            health_status['status'] = 'unhealthy'
            health_status['components']['database'] = f'error: {str(e)}'
        
        # Check replication lag
        try:
            repl_lag = self.get_replication_lag()
            if repl_lag > 60:  # >1 minute lag
                health_status['status'] = 'degraded'
            health_status['components']['replication_lag_seconds'] = repl_lag
        except Exception as e:
            health_status['components']['replication'] = f'error: {str(e)}'
        
        # Check API responsiveness
        try:
            start = time.time()
            # Quick internal test
            assert self.quick_test(), "Internal test failed"
            latency = (time.time() - start) * 1000
            health_status['components']['api_latency_ms'] = latency
        except Exception as e:
            health_status['status'] = 'unhealthy'
            health_status['components']['api'] = f'error: {str(e)}'
        
        status_code = 200 if health_status['status'] == 'healthy' else 503
        return health_status, status_code
```

## Database Replication

### 1. RDS Multi-Master Replication

```python
from alibabacloud_rds20140815.client import Client as RdsClient

class MultiRegionDatabase:
    def __init__(self):
        self.rds_client = RdsClient()
    
    def setup_replication(self):
        """Setup bidirectional replication"""
        
        # Primary instance in Beijing
        beijing_db = {
            'DBInstanceIdentifier': 'app-db-beijing',
            'Engine': 'MySQL',
            'EngineVersion': '8.0',
            'DBInstanceClass': 'rds.mysql.x1.large',
            'AllocatedStorage': 100
        }
        
        # Create primary
        primary = self.rds_client.create_db_instance(beijing_db)
        
        # Create standby in Shanghai
        shanghai_db = beijing_db.copy()
        shanghai_db['SourceDBInstanceIdentifier'] = primary['DBInstanceIdentifier']
        shanghai_db['ReplicationSourceRegion'] = 'cn-shanghai'
        
        standby = self.rds_client.create_db_instance_read_replica(shanghai_db)
        
        # Enable bidirectional sync
        self.rds_client.modify_db_instance_parameter_group(
            DBInstanceIdentifier=primary['DBInstanceIdentifier'],
            ParameterGroupName='mysql-binlog',
            Parameters={
                'binlog_format': 'ROW',
                'server_id': 1,
                'log_slave_updates': 'ON'
            }
        )

        return primary, standby
    
    def configure_gtid(self):
        """Global Transaction ID for consistency"""
        
        gtid_config = {
            'gtid_mode': 'ON',
            'enforce_gtid_consistency': 'ON',
            'master_info_repository': 'TABLE',  # Not FILE
            'relay_log_info_repository': 'TABLE'
        }
        
        # Apply to all regions
        for region in ['beijing', 'shanghai', 'hongkong']:
            self.apply_config(f'app-db-{region}', gtid_config)
```

### 2. Data Consistency Verification

```python
class ReplicationConsistency:
    def __init__(self):
        self.beijing_conn = create_connection('beijing')
        self.shanghai_conn = create_connection('shanghai')
    
    def verify_consistency(self, table_name: str) -> bool:
        """Verify data consistency across regions"""
        
        # Checksums at specific timestamp
        beijing_checksum = self.get_table_checksum(
            self.beijing_conn, table_name
        )
        shanghai_checksum = self.get_table_checksum(
            self.shanghai_conn, table_name
        )
        
        if beijing_checksum != shanghai_checksum:
            # Find inconsistencies
            self.sync_table(table_name)
            return False
        
        return True
    
    def get_table_checksum(self, conn, table: str):
        """Get checksum of table"""
        result = conn.execute(f'CHECKSUM TABLE {table}')
        return result[0][1]
    
    def sync_table(self, table: str):
        """Resync table using binary logs"""
        # Use pt-table-checksum and pt-table-sync
        subprocess.run([
            'pt-table-checksum',
            f'P=/tmp/mysql.sock,u=root,p=pass,D={db},t={table}',
            '--no-check-binlog-format',
            '--max-load=Threads_running:10'
        ])
```

## Health Monitoring

### Active Monitoring

```python
import asyncio
from datetime import datetime, timedelta

class FailoverMonitor:
    def __init__(self, regions: List[str]):
        self.regions = regions
        self.health_history = {r: [] for r in regions}
        self.failover_threshold = 3  # Mark down after 3 failures
    
    async def continuous_monitoring(self):
        """Monitor all regions continuously"""
        
        while True:
            tasks = [self.check_region_health(r) for r in self.regions]
            results = await asyncio.gather(*tasks)
            
            for region, is_healthy in zip(self.regions, results):
                self.health_history[region].append({
                    'timestamp': datetime.now(),
                    'healthy': is_healthy
                })
                
                # Trigger failover if needed
                if self.should_failover(region):
                    await self.trigger_failover(region)
            
            await asyncio.sleep(10)  # Check every 10 seconds
    
    async def check_region_health(self, region: str) -> bool:
        """Check if region is healthy"""
        
        try:
            response = await asyncio.wait_for(
                self.health_check_request(region),
                timeout=5.0
            )
            return response.status_code == 200
        except asyncio.TimeoutError:
            return False
        except Exception as e:
            self.log_error(f"Health check error for {region}: {e}")
            return False
    
    def should_failover(self, region: str) -> bool:
        """Determine if failover needed"""
        
        recent_checks = self.health_history[region][-self.failover_threshold:]
        
        if len(recent_checks) < self.failover_threshold:
            return False
        
        failed_count = sum(1 for c in recent_checks if not c['healthy'])
        return failed_count >= self.failover_threshold
    
    async def trigger_failover(self, failed_region: str):
        """Redirect traffic away from failed region"""
        
        print(f"FAILOVER: {failed_region} is unhealthy")
        
        # Update GSLB
        healthy_regions = [r for r in self.regions if r != failed_region]
        await self.update_gslb_weights({
            r: 100 if r in healthy_regions else 0
            for r in self.regions
        })
        
        # Alert ops team
        await self.send_alert(
            f"Failover triggered for {failed_region}",
            severity='critical'
        )
```

## Failover Testing

### Chaos Engineering Approach

```python
class FailoverTest:
    def __init__(self):
        self.metrics = {}
    
    def test_regional_failure(self, region_to_fail: str):
        """Simulate region failure and measure failover"""
        
        print(f"Starting failover test: Simulating {region_to_fail} failure")
        
        # Record start time
        start_time = time.time()
        
        # Isolate region (block traffic)
        self.isolate_region(region_to_fail)
        
        # Monitor metrics
        failover_detected_time = None
        service_restored_time = None
        data_loss_size = 0
        
        for i in range(30):  # 30 second test
            elapsed = time.time() - start_time
            
            # Check if failover detected
            if not failover_detected_time:
                if not self.can_reach_region(region_to_fail):
                    failover_detected_time = elapsed
                    print(f"✓ Failover detected at {elapsed:.1f}s")
            
            # Check if service restored
            if failover_detected_time and not service_restored_time:
                if self.is_service_healthy():
                    service_restored_time = elapsed
                    print(f"✓ Service restored at {elapsed:.1f}s")
                    
                    # Measure data loss
                    data_loss_size = self.measure_data_loss(region_to_fail)
                    print(f"✓ Data loss: {data_loss_size} records")
            
            time.sleep(1)
        
        # Restore region
        self.restore_region(region_to_fail)
        
        # Report results
        self.metrics = {
            'test_region': region_to_fail,
            'failure_detected_seconds': failover_detected_time,
            'service_restored_seconds': service_restored_time,
            'data_loss_records': data_loss_size,
            'rto_target': 300,  # 5 minutes
            'rpo_target': 60,   # 1 minute
            'test_result': (
                'PASS' if service_restored_time < 300 and data_loss_size < 1000
                else 'FAIL'
            )
        }
        
        return self.metrics
```

## Compliance & Disaster Recovery

### Backup Strategy

```bash
# Automated backups in all regions
aliyun rds CreateDBInstanceBackup \
  --DBInstanceId app-db-beijing \
  --BackupType FullBackup \
  --CopyToRegions cn-shanghai cn-hongkong

# Backup retention
BackupRetentionDays: 30
CopyBackupRetentionDays: 7
```

### RTO/RPO SLA

```yaml
SLA:
  RTO: 
    target: 300 seconds  # 5 minutes
    measurement: Time from failure detection to traffic rerouting
  
  RPO:
    target: 60 seconds   # 1 minute  
    measurement: Maximum data loss
  
  Availability:
    target: 99.99%  # 4 nines = 52.6 min downtime/year
```

---

## Next Steps

- 🏗️ [Deploy with Terraform](../terraform/failover-infrastructure/main.tf)
- 🧪 [Run Chaos Tests](../code/chaos_engineering.py)
- 📊 [Monitor with ARMS](../blog/05-observability-detailed.md)

**Reference:** [GSLB Documentation](https://www.alibabacloud.com/help/alidns) | [RDS Replication](https://www.alibabacloud.com/help/rds)
