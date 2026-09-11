# Architecture

The platform runs on one `g4dn.xlarge` EC2 instance. Ubuntu hosts the NVIDIA driver, NVIDIA container toolkit, K3s, and the container runtime. A GPU-requesting Deployment runs the Qwen2.5-3B-Instruct model behind a ClusterIP Service and NGINX Ingress.

The model cache is backed by a PVC so pod recreation does not require downloading the model again. Prometheus-compatible metrics are exposed by vLLM and DCGM exporter, with Grafana and Alertmanager supplied by kube-prometheus-stack.

This topology has no node-level redundancy. An EC2 or GPU failure causes an outage until the host recovers.
