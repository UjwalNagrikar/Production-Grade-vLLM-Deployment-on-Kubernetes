#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-ai-inference}
RELEASE=${RELEASE:-qwen-vllm}
HOST=${INGRESS_HOST:-llm.example.com}

kubectl apply -f kubernetes/namespace.yaml
helm upgrade --install "$RELEASE" helm/vllm \
  --namespace "$NAMESPACE" \
  --set ingress.host="$HOST" \
  --create-namespace
kubectl -n "$NAMESPACE" rollout status deployment/"$RELEASE-vllm" --timeout=30m
kubectl -n "$NAMESPACE" get all,pvc,ingress
