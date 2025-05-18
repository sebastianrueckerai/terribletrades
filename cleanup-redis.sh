#!/bin/bash
export KUBECONFIG=infra/platform/kubeconfig.yaml

echo "Deleting Redis StatefulSets without deleting data..."
kubectl delete statefulset -n trading redis-master --cascade=orphan || true
kubectl delete statefulset -n trading redis-replicas --cascade=orphan || true
echo "StatefulSets deleted. You can now run terraform apply again."