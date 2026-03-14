---
name: k8s-status
description: Show full cluster health — nodes, pods across all app namespaces, PVCs, and recent warning events. Use this when the user wants a cluster overview or health check.
---

Run the following kubectl commands and present a clean summary:

```bash
kubectl get nodes -o wide
kubectl get pods -n workflows
kubectl get pods -n data
kubectl get pods -n monitoring
kubectl get pods -n ingress-nginx
kubectl get pvc -A
kubectl get events -A --field-selector type=Warning --sort-by='.lastTimestamp' | tail -20
```

Report:
- Node status and allocatable CPU/RAM
- Any pods not in Running/Completed state (highlight CrashLoopBackOff, Pending, OOMKilled)
- PVC status and storage usage (note: OCI minimum is 50GB per volume, Always Free cap is 200GB total)
- Any recent warning events worth investigating

Keep the output concise — lead with problems if any exist, otherwise confirm healthy.
