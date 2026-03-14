---
name: k8s-cost
description: Estimate current resource consumption against Oracle Always Free limits. Use before scaling up or adding new workloads to confirm headroom exists.
---

```bash
kubectl get nodes -o custom-columns="NODE:.metadata.name,CPU:.status.allocatable.cpu,RAM:.status.allocatable.memory"
kubectl get pods -A -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase" | grep -v "kube-system\|Succeeded"
kubectl get pvc -A -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name,SIZE:.spec.resources.requests.storage,STATUS:.status.phase"
kubectl top pods -A 2>/dev/null || echo "metrics-server not available"
```

Always Free hard limits for this cluster:
- **CPU**: 4 OCPU total → 2 nodes × 2 OCPU (1830m allocatable each) = ~3660m allocatable
- **RAM**: 24GB total → 2 nodes × ~9.4GB allocatable = ~18.8GB allocatable
- **Block storage**: 200GB total — 2×50GB node boot volumes + 1×50GB postgres PVC = 150GB used, **50GB remaining**
- **Load balancers**: 1 used (nginx ingress), 1 remaining

Report current usage vs limits and flag if any resource is above 80% utilisation.
Note: adding any PVC will consume the remaining 50GB (OCI minimum block volume size).
