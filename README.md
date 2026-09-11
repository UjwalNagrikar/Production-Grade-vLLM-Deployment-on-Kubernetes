# vLLM Kubernetes Platform

A single-node K3s platform for serving `Qwen/Qwen2.5-3B-Instruct` with vLLM on an NVIDIA T4 GPU.

This is a portfolio/lab deployment, not a highly available production cluster. The EC2 instance, K3s control plane, GPU, model cache, and observability stack are single points of failure.

## Architecture

```text
Internet -> NGINX Ingress -> vLLM Service -> vLLM Deployment -> NVIDIA T4
                                      |
                                      +-> PVC-backed Hugging Face model cache

Prometheus <- vLLM metrics / node metrics / DCGM exporter -> Grafana
GitHub Actions -> lint, schema validation, Trivy config scan
Terraform -> VPC, subnet, security group, IAM, g4dn.xlarge
```

## Repository layout

- `terraform/`: AWS networking, security group, IAM, and GPU EC2 instance.
- `kubernetes/`: direct Kubernetes manifests for the platform.
- `helm/vllm/`: reusable Helm chart for the inference workload.
- `monitoring/`: Prometheus/Grafana values and NVIDIA DCGM exporter manifest.
- `load-testing/`: Locust workload for the OpenAI-compatible endpoint.
- `scripts/`: host bootstrap and deployment helpers.
- `.github/workflows/ci-cd.yaml`: YAML, Helm, kubeconform, and Trivy checks.

## Prerequisites

- AWS account and credentials configured for Terraform.
- An AWS region offering `g4dn.xlarge`.
- Ubuntu 24.04 on the EC2 host.
- A DNS name pointed at the host or load balancer.
- `kubectl`, `helm`, `terraform`, and `k3s` access.
- A Hugging Face token only if the selected model requires gated access. Qwen2.5 is normally public.

## Quick start

### 1. Provision the host

```powershell
cd terraform
terraform init
Copy-Item terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your AMI ID, key name, region, and SSH CIDR.
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

The security group intentionally does not expose port `8000`. Allow only SSH from your IP and HTTP/HTTPS for ingress.

### 2. Bootstrap the host

SSH to the instance and run:

```bash
sudo bash scripts/install-nvidia.sh
sudo bash scripts/install-k3s.sh
```

Reboot after the NVIDIA driver installation if `nvidia-smi` does not work immediately. Then verify:

```bash
nvidia-smi
kubectl get nodes
kubectl describe node | grep -A3 nvidia.com/gpu
```

Install the NVIDIA device plugin:

```bash
helm repo add nvdp https://nvidia.github.io/k8s-device-plugin
helm repo update
helm upgrade --install nvidia-device-plugin nvdp/nvidia-device-plugin \
  --namespace nvidia-device-plugin --create-namespace
kubectl get pods -n nvidia-device-plugin
```

### 3. Deploy vLLM

From the repository root:

```bash
bash scripts/deploy.sh
```

Or use Helm directly:

```bash
helm upgrade --install qwen-vllm ./helm/vllm \
  --namespace ai-inference --create-namespace \
  --set ingress.host=llm.example.com
```

The first startup downloads the model into the PVC and can take several minutes. Watch readiness:

```bash
kubectl -n ai-inference get pods -w
kubectl -n ai-inference get ingress
```

### 4. Test the API

```bash
curl https://llm.example.com/health
curl https://llm.example.com/v1/models

curl https://llm.example.com/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer replace-me' \
  -d '{"model":"Qwen/Qwen2.5-3B-Instruct","messages":[{"role":"user","content":"Say hello in one sentence."}],"max_tokens":32}'
```

Set `vllm.apiKey` in a private values file or secret workflow before exposing the endpoint. TLS is also expected to be configured in the ingress values before internet exposure.

## Monitoring

Install the Prometheus community stack separately:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f monitoring/kube-prometheus-stack-values.yaml
kubectl apply -f monitoring/dcgm-exporter.yaml
```

The vLLM ServiceMonitor scrapes `/metrics`. Grafana dashboards should track request rate, latency, tokens, GPU utilization, GPU memory, pod restarts, and error rate.

## Load test

```bash
pip install locust
VLLM_BASE_URL=https://llm.example.com VLLM_API_KEY=replace-me \
  locust -f load-testing/locustfile.py
```

Start with 10, 25, and 50 users. Record P50/P95/P99 latency, time to first token, tokens per second, error rate, and GPU utilization. Do not begin with 100 users on a single T4 without observing saturation.

## Failure tests

```bash
kubectl -n ai-inference delete pod -l app.kubernetes.io/name=vllm
kubectl -n ai-inference rollout status deployment/qwen-vllm
```

Document model reload time, recovery behavior, and the interval during which traffic is unavailable. A node or EC2 failure still takes the entire service offline.

## CI

The workflow runs YAML parsing, Helm linting, Kubernetes schema validation, and Trivy configuration scanning. Deployment is deliberately not automatic until a real cluster credential strategy is selected.

## Security notes

- Keep EC2 port `8000` closed to the internet.
- Put the endpoint behind HTTPS and an authentication layer.
- Do not commit API keys, Hugging Face tokens, kubeconfigs, or Terraform state.
- vLLM's API key flag is endpoint-level protection, not a complete security boundary for every HTTP route.
- Add a real ingress TLS secret and authentication middleware before public use.
