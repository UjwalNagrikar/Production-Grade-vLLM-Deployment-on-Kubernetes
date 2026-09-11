# Failure test template

## Pod deletion

Command: `kubectl -n ai-inference delete pod -l app.kubernetes.io/name=vllm`

Record pod deletion time, replacement readiness time, failed requests, and model cache reuse.

## Container restart

Trigger a controlled restart and record liveness behavior, restart count, and recovery time.

## Node failure

A single-node K3s deployment cannot recover from an EC2 failure. Record this as a known availability limitation and describe the multi-node production evolution.
