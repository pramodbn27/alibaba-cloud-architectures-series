# Agent-Native Infrastructure for AI Workloads (Quick Overview)

*Read time: 5 minutes*

## What is Agent-Native Infrastructure?

Infrastructure **optimized for autonomous AI agents** - not just models, but agents making decisions and taking actions.

## Key Differences

| Traditional Apps | Agent Apps |
|-----------------|-----------|
| Predictable traffic | Bursty, event-driven |
| Fixed compute needs | Variable GPU/memory |
| Batch processing | Real-time decision making |
| Users trigger actions | Agents trigger actions |

## Architecture Blueprint

```
┌─────────┐
│ Event   │
│ Source  │
└────┬────┘
     │
     ▼
┌─────────────────────┐
│ Message Queue (MQ)  │  Fast, reliable event distribution
└────┬────────────────┘
     │
     ▼
┌─────────────────────────┐
│ Auto-scaling ECS Group  │  GPU instances for agent compute
│ (GPU A100, V100)        │
└────┬────────────────────┘
     │
     ▼
┌────────────────────────┐
│ Agent Framework        │  Multi-turn reasoning, planning
│ (LangChain, AutoGen)   │
└────┬───────────────────┘
     │
     ▼
┌────────────────────────────┐
│ Action Execution Layer     │  Call external APIs/services
└────────────────────────────┘
```

## Key Services

- **ECS GPU Instances:** compute
- **Auto Scaling Groups:** dynamic scaling
- **Message Queue (MQ):** event routing
- **Function Compute:** serverless agent tasks
- **Vector Database:** memory/knowledge base

## Cost Planning

| Component | Monthly |
|-----------|---------|
| GPU Instance (g7-2xL100) | $1,500-2,000 |
| Auto-scaling overhead | $200-300 |
| Message Queue (1M msgs) | $50-100 |
| Storage | $100-200 |
| **Total (1 agent)** | **$1,900-2,600** |

---

→ [Detailed Guide: Agent Infrastructure](06-agent-detailed.md)

→ [Terraform Config](../terraform/agent-infrastructure/main.tf)
