---
name: k8s-scale
description: Scale a deployment up or down and verify the rollout completes. Use when the user wants to adjust replica counts for n8n workers, webhooks, or other deployments.
---

Ask the user for the deployment name, namespace, and desired replica count if not provided.

```bash
kubectl scale deployment <deployment-name> -n <namespace> --replicas=<count>
kubectl rollout status deployment/<deployment-name> -n <namespace> --timeout=120s
kubectl get pods -n <namespace> -l app.kubernetes.io/name=<app>
```

Deployments in this cluster:
- `n8n` in `workflows` — main n8n instance (keep at 1, PDB enforces minAvailable: 1)
- `n8n-worker` in `workflows` — queue workers (HPA min: 1, max: 5)
- `n8n-webhook` in `workflows` — webhook listeners (HPA min: 1, max: 5)

Always Free resource reminder:
- 2 nodes × 1830m CPU, 2 nodes × ~9.4GB RAM allocatable
- HPA manages workers/webhooks automatically based on CPU — manual scaling is usually not needed
- Confirm resource headroom before scaling up: run /k8s-cost first
