---
name: n8n-queue
description: Check n8n queue mode health — Valkey queue depth, worker status, webhook listeners, and any stuck or failed jobs. Use when n8n workflows seem slow or stuck.
---

```bash
kubectl get pods -n workflows
kubectl get hpa -n workflows
kubectl exec -n workflows statefulset/n8n-valkey-primary -- valkey-cli -a $VALKEY_PASSWORD llen bull:jobs:wait 2>/dev/null || \
  kubectl exec -n workflows statefulset/n8n-valkey-primary -- valkey-cli llen bull:jobs:wait
kubectl exec -n workflows statefulset/n8n-valkey-primary -- valkey-cli dbsize
kubectl logs -n workflows -l app.kubernetes.io/component=worker --tail=30 --prefix
```

Queue mode architecture for this cluster:
- **n8n main** (1 pod) — handles UI and enqueues jobs to Valkey
- **n8n-worker** (HPA: 1–5 pods) — consumes jobs from Valkey queue
- **n8n-webhook** (HPA: 1–5 pods) — receives inbound webhook triggers
- **Valkey** (n8n-valkey-primary) — queue broker with AOF persistence to emptyDir

Healthy state: workers Running, queue depth near 0, no CrashLoopBackOff.
If queue is growing: HPA may need time to scale up workers (stabilizationWindowSeconds: 300 for scale-down).
If workers are crashing: check logs for DB connection errors — postgres in `data` namespace may be unhealthy.
