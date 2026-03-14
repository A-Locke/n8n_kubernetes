---
name: k8s-debug
description: Debug a specific pod — describe it, show recent logs, and surface relevant events. Use when the user mentions a pod is crashing, restarting, or behaving unexpectedly.
---

Ask the user for the pod name and namespace if not provided. Then run:

```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous --tail=50 2>/dev/null || kubectl logs <pod-name> -n <namespace> --tail=50
kubectl get events -n <namespace> --field-selector involvedObject.name=<pod-name> --sort-by='.lastTimestamp'
```

Common namespaces in this cluster:
- `workflows` — n8n main, workers, webhooks, valkey
- `data` — postgres, pgadmin
- `monitoring` — prometheus, grafana
- `ingress-nginx` — nginx ingress controller

Diagnose based on the output:
- CrashLoopBackOff → check `--previous` logs for the exit reason
- OOMKilled → memory limit too low, check resource requests/limits
- Pending → check node capacity or PVC binding issues
- ImagePullBackOff → image tag or registry issue
