# vLLM Kubernetes Platform

A single-node K3s platform for serving `Qwen/Qwen2.5-3B-Instruct` with vLLM on an NVIDIA T4 GPU. The project provisions an AWS GPU host, installs the Kubernetes and NVIDIA runtime components, deploys the model through Helm, and provides Prometheus/Grafana-compatible observability.

This is a portfolio and lab deployment, not a highly available production cluster. The EC2 instance, K3s control plane, GPU, model cache, and observability stack are single points of failure.

## Project goals

- Run an OpenAI-compatible LLM API on a GPU-backed Kubernetes workload.
- Provision the underlying AWS infrastructure with Terraform.
- Make model deployment repeatable with Helm and shell scripts.
- Persist the Hugging Face model cache so pod restarts do not redownload the model.
- Collect application, Kubernetes, node, and NVIDIA GPU metrics.
- Validate infrastructure and Kubernetes configuration in GitHub Actions.

## Technology stack

| Area | Technology | Purpose |
| --- | --- | --- |
| Cloud | AWS EC2 `g4dn.xlarge` | Hosts the NVIDIA T4 GPU and single-node cluster |
| Infrastructure | Terraform | Creates the EC2 instance, key pair, IAM role, security group, and encrypted EBS volume |
| Operating system | Ubuntu 24.04 | Base operating system for the GPU host |
| Container orchestration | K3s | Lightweight Kubernetes distribution for the single-node cluster |
| GPU runtime | NVIDIA driver, NVIDIA Container Toolkit, NVIDIA device plugin | Makes the T4 available as `nvidia.com/gpu` to Kubernetes pods |
| Inference server | vLLM OpenAI image `v0.10.2` | Serves `Qwen/Qwen2.5-3B-Instruct` and exposes the OpenAI-compatible API |
| Packaging | Helm | Deploys and configures the vLLM workload |
| Networking | NGINX Ingress Controller | Routes HTTP/HTTPS traffic to the vLLM service |
| Storage | K3s `local-path` StorageClass and PVC | Stores the Hugging Face model cache on the node |
| Monitoring | kube-prometheus-stack and NVIDIA DCGM exporter | Provides Prometheus, Grafana, Alertmanager, node, and GPU metrics |
| Load testing | Locust | Exercises the chat completions endpoint |
| CI validation | GitHub Actions, kubeconform, Trivy | Checks YAML, Helm rendering, Kubernetes schemas, and configuration risks |

## Architecture

```text
                         AWS account
                             |
          Terraform: VPC subnet, IAM, security group, EC2
                             |
                     Ubuntu 24.04 host
                             |
       NVIDIA driver + container toolkit + K3s control plane
                             |
       NVIDIA device plugin advertises one T4 GPU to Kubernetes
                             |
 Internet -> NGINX Ingress -> ClusterIP Service -> vLLM Deployment -> NVIDIA T4
                                      |
                                      +-> PVC -> Hugging Face model cache

 Prometheus <- vLLM / node metrics / DCGM exporter -> Grafana and Alertmanager
 GitHub Actions -> Helm lint, YAML parse, kubeconform, Trivy config scan
```

### Request flow

1. DNS points the configured hostname, such as `llm.example.com`, at the host or load balancer.
2. NGINX Ingress receives the request and forwards it to the `ClusterIP` service.
3. The service selects the single vLLM pod in the `ai-inference` namespace.
4. vLLM loads the model from the PVC-backed Hugging Face cache and uses the T4 for inference.
5. Health probes use `/health`; model metadata and chat completions are available through `/v1` routes.

### Deployment architecture diagram

![vLLM deployment architecture](docs/diagram.png)

### vLLM model deployment guide

Use the following sequence to deploy the model on the cluster and validate that the inference API is serving requests.

1. Provision the GPU host and base Kubernetes node.
   - Run the Terraform configuration in `terraform/` to create the EC2 instance, security group, IAM role, and EBS volume.
   - Ensure the host is reachable by SSH and has internet access for package installation.

2. Install NVIDIA support and K3s.
   - Run `sudo bash scripts/install-nvidia.sh` on the GPU host.
   - Run `sudo bash scripts/install-k3s.sh` to install the Kubernetes control plane.
   - Confirm the node registers successfully with `kubectl get nodes`.

3. Install the GPU device plugin.

   ```bash
   helm repo add nvdp https://nvidia.github.io/k8s-device-plugin
   helm repo update
   helm upgrade --install nvidia-device-plugin nvdp/nvidia-device-plugin \
     --namespace nvidia-device-plugin --create-namespace
   kubectl get pods -n nvidia-device-plugin
   ```

4. Deploy the model with Helm.
   - The chart in `helm/vllm/` creates the namespace, PVC, deployment, service, ingress, and monitoring resources.
   - By default it deploys `Qwen/Qwen2.5-3B-Instruct` with the vLLM OpenAI-compatible image.

   ```bash
   helm upgrade --install vllm ./helm/vllm \
     --namespace ai-inference \
     --create-namespace
   ```

5. Verify the workload.

   ```bash
   kubectl get pods -n ai-inference
   kubectl get svc -n ai-inference
   kubectl logs -n ai-inference deployment/vllm
   ```

6. Test the inference endpoint.

   ```bash
   kubectl port-forward -n ai-inference svc/vllm 8000:8000
   curl http://127.0.0.1:8000/v1/models
   curl http://127.0.0.1:8000/health
   ```

7. Run a sample chat completion request.

   ```bash
   curl http://127.0.0.1:8000/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{
       "model": "Qwen/Qwen2.5-3B-Instruct",
       "messages": [{"role": "user", "content": "Write a short Kubernetes deployment summary."}],
       "temperature": 0.7,
       "max_tokens": 200
     }'
   ```

8. Optional: enable monitoring and load testing.
   - Review the Prometheus/Grafana values in `monitoring/`.
   - Use Locust in `load-testing/locustfile.py` to test traffic and throughput.

### Default workload settings

- Model: `Qwen/Qwen2.5-3B-Instruct`
- Container image: `vllm/vllm-openai:v0.10.2`
- Replicas: `1` with a `Recreate` deployment strategy
- GPU request and limit: `1 x nvidia.com/gpu`
- CPU request/limit: `2` / `3`
- Memory request/limit: `8 GiB` / `12 GiB`
- Model cache: `40 GiB` PVC using the K3s `local-path` StorageClass
- vLLM port: `8000` inside the cluster
- GPU memory utilization: `90%`

## Repository layout

- `terraform/`: AWS provider configuration, infrastructure resources, variables, and outputs.
- `kubernetes/`: direct Kubernetes manifests such as the application namespace.
- `helm/vllm/`: reusable Helm chart for the vLLM Deployment, Service, Ingress, PVC, Secret, and ServiceMonitor.
- `monitoring/`: kube-prometheus-stack values and NVIDIA DCGM exporter manifest.
- `load-testing/`: Locust workload for the OpenAI-compatible endpoint.
- `scripts/`: NVIDIA/K3s host bootstrap and application deployment helpers.
- `docs/`: architecture, performance, and incident-test notes.
- `.github/workflows/ci-cd.yaml`: repository validation workflow.
- `Makefile`: shortcuts for linting, rendering, deployment, status, logs, and removal.

## Prerequisites

## Required tools and installation commands

Use the following commands to prepare both the local machine and the Ubuntu GPU host used by this project.

### 1. Install required tools on your local workstation

The local machine is used for Terraform, Helm, `kubectl`, Git, SSH, AWS authentication, and optionally Python/Locust.

#### Windows PowerShell (recommended)

```powershell
winget install --id Git.Git -e
winget install --id Hashicorp.Terraform -e
winget install --id Helm.Helm -e
winget install --id Kubernetes.kubectl -e
winget install --id Amazon.AWSCLI -e
winget install --id Python.Python.3.12 -e
```

Verify the tools:

```powershell
git --version
terraform version
helm version
kubectl version --client
aws --version
python --version
pip --version
```

If you prefer Chocolatey:

```powershell
choco install git terraform kubernetes-cli kubernetes-helm awscli python -y
```

#### macOS

```bash
brew install git terraform helm kubectl awscli python
```

#### Ubuntu/Debian

```bash
sudo apt-get update
sudo apt-get install -y curl git unzip ca-certificates gnupg lsb-release openssh-client
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update
sudo apt-get install -y terraform

curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

sudo apt-get install -y python3 python3-pip
```

Install Locust for load testing if needed:

```bash
pip install locust
```

#### Configure AWS credentials

```bash
aws configure
```

Set the AWS region and create a valid profile before running Terraform:

```bash
export AWS_PROFILE=default
export AWS_REGION=us-west-2
aws sts get-caller-identity
```

### 2. Install the required packages on the Ubuntu GPU host

This project expects an Ubuntu 24.04 EC2 host with an NVIDIA T4 GPU. The host must have internet access, a public IP or a reachable SSH endpoint, and permission to install NVIDIA and K3s components.

Run the following on the host:

```bash
sudo apt-get update
sudo apt-get install -y curl ca-certificates gnupg apt-transport-https software-properties-common
```

Install the NVIDIA driver and toolkit:

```bash
sudo bash scripts/install-nvidia.sh
```

The script performs the equivalent of:

```bash
sudo apt-get update
sudo apt-get install -y ubuntu-drivers-common
sudo ubuntu-drivers install
sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=containerd
sudo systemctl restart containerd || true
nvidia-smi
```

Install K3s:

```bash
sudo bash scripts/install-k3s.sh
```

The script runs:

```bash
curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes
```

Install Helm on the host if you want to manage charts directly:

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

Install the NVIDIA device plugin in the cluster:

```bash
helm repo add nvdp https://nvidia.github.io/k8s-device-plugin
helm repo update
helm upgrade --install nvidia-device-plugin nvdp/nvidia-device-plugin \
  --namespace nvidia-device-plugin --create-namespace
kubectl get pods -n nvidia-device-plugin
```

### 3. Validation commands

After the install steps above, confirm the environment is ready:

```bash
nvidia-smi
kubectl get nodes
kubectl describe node | grep -A3 nvidia.com/gpu
helm version
terraform version
```

### Local workstation

- AWS credentials configured for Terraform.
- Terraform, Helm, and `kubectl` installed locally.
- Git and an SSH client.
- An AWS region offering `g4dn.xlarge` and an Ubuntu 24.04 AMI ID for that region.
- A DNS record for the eventual ingress hostname, if the API will be accessed by name.

### AWS and host

- Permission to create EC2, IAM, security group, key pair, and networking resources.
- An Ubuntu 24.04 GPU-capable EC2 host. The default is `g4dn.xlarge` with one NVIDIA T4.
- Enough root disk space for the OS, container images, logs, and the 40 GiB model cache. The Terraform default is a 100 GiB encrypted `gp3` volume.
- A Hugging Face token only if a selected model requires gated access. The default Qwen model is normally public.

## Deployment

### 1. Provision AWS infrastructure

From PowerShell at the repository root:

```powershell
Set-Location terraform
terraform init
Copy-Item terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: ami_id, region, instance_type, key_name, and root_volume_size.
terraform fmt -check
terraform validate
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

Save the Terraform outputs, especially `public_ip`, `public_dns`, and the sensitive generated `private_key`:

```powershell
terraform output public_ip
terraform output public_dns
terraform output -raw private_key | Set-Content -NoNewline .\vllm-k3s.pem
icacls .\vllm-k3s.pem /inheritance:r /grant:r "$($env:USERNAME):(R)"
```

The private key is stored in Terraform state. Protect the state file and never commit it to source control.

### 2. Install GPU support and K3s

SSH to the new host, copy this repository to it, and run the bootstrap scripts from the repository root:

```bash
sudo bash scripts/install-nvidia.sh
sudo bash scripts/install-k3s.sh
```

Reboot if `nvidia-smi` does not work immediately. Verify the host and GPU:

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

### 3. Deploy the inference service

Set the DNS hostname through `INGRESS_HOST` and run the deployment helper:

```bash
export INGRESS_HOST=llm.example.com
bash scripts/deploy.sh
```

The helper creates the `ai-inference` namespace, installs or upgrades the `qwen-vllm` Helm release, waits up to 30 minutes for the Deployment, and prints the resulting resources.

For a direct Helm deployment:

```bash
helm upgrade --install qwen-vllm ./helm/vllm \
  --namespace ai-inference --create-namespace \
  --set ingress.host=llm.example.com
```

The first startup downloads the model into the PVC and can take several minutes. Watch readiness:

```bash
kubectl -n ai-inference get pods -w
kubectl -n ai-inference get pvc,service,ingress
kubectl -n ai-inference rollout status deployment/qwen-vllm --timeout=30m
```

### 4. Configure API authentication and TLS

Create a private values file rather than putting credentials in the repository:

```yaml
apiKey: replace-with-a-secret
ingress:
  host: llm.example.com
  tls:
    - hosts:
        - llm.example.com
      secretName: llm-tls
```

Install with the private file:

```bash
helm upgrade --install qwen-vllm ./helm/vllm \
  --namespace ai-inference --create-namespace \
  -f private-values.yaml
```

The TLS secret must exist in `ai-inference` before the Ingress can terminate TLS. Add a certificate manager or create the secret through your chosen secret-management process.

### 5. Test the API

```bash
curl https://llm.example.com/health
curl https://llm.example.com/v1/models

curl https://llm.example.com/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer replace-with-a-secret' \
  -d '{"model":"Qwen/Qwen2.5-3B-Instruct","messages":[{"role":"user","content":"Say hello in one sentence."}],"max_tokens":32}'
```

## Day-to-day operations

The Makefile provides common commands from the repository root:

```bash
make lint     # Helm lint
make render   # Render Kubernetes YAML locally
make deploy   # Install or upgrade the qwen-vllm release
make status   # Show workloads, PVC, and Ingress
make logs     # Follow vLLM logs
make destroy  # Uninstall the Helm release
```

Useful troubleshooting commands:

```bash
kubectl -n ai-inference describe pod -l app.kubernetes.io/name=vllm
kubectl -n ai-inference logs deploy/qwen-vllm
kubectl -n ai-inference get events --sort-by=.lastTimestamp
kubectl get nodes -o wide
nvidia-smi
```

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

The chart exposes vLLM metrics through `/metrics` and includes a ServiceMonitor. Monitor request rate, error rate, latency, time to first token, tokens per second, pod restarts, GPU utilization, GPU memory, and model load time.

## Load testing

Install Locust and point it at the deployed endpoint:

```bash
pip install locust
VLLM_BASE_URL=https://llm.example.com VLLM_API_KEY=replace-with-a-secret \
  locust -f load-testing/locustfile.py
```

Start with 10, 25, and 50 users. Record P50/P95/P99 latency, time to first token, tokens per second, error rate, and GPU utilization. Do not begin with 100 users on a single T4 without observing saturation. See `docs/performance.md` for the performance test record.

## Failure testing

Exercise pod recovery with:

```bash
kubectl -n ai-inference delete pod -l app.kubernetes.io/name=vllm
kubectl -n ai-inference rollout status deployment/qwen-vllm --timeout=30m
```

Record model reload time, recovery behavior, and the interval during which traffic is unavailable. A node or EC2 failure still takes the entire service offline. See `docs/incident-test.md` for the incident-test checklist.

## CI and validation

GitHub Actions runs on pushes and pull requests. The workflow:

1. Lints the Helm chart.
2. Parses non-template YAML files.
3. Renders the Helm chart.
4. Validates rendered resources against Kubernetes schemas with kubeconform.
5. Scans the repository configuration with Trivy for high and critical findings.

Deployment is deliberately not automatic until a cluster credential and release strategy are selected.

## Security and production limitations

- The current Terraform security group contains an allow-all inbound rule. Restrict it before deployment to SSH from an administrator IP and HTTP/HTTPS only, or replace it with a load balancer and private node access.
- Keep the vLLM service port `8000` private; access it through the Ingress or an internal tunnel.
- Put the endpoint behind HTTPS and authentication. The vLLM API key is endpoint-level protection, not a complete security boundary for every HTTP route.
- Do not commit API keys, Hugging Face tokens, kubeconfigs, private keys, or Terraform state.
- Add a real Ingress TLS secret and authentication middleware before public use.
- This topology has one node, one GPU, one model cache, and one control plane. It has no failover, rolling capacity, or durable cross-node storage.
- The default `local-path` PVC is node-local. Replacing the EC2 instance requires restoring or redownloading the model.

## Teardown

Remove the Kubernetes release first, then destroy the AWS resources when the environment is no longer needed:

```bash
make destroy
```

```powershell
Set-Location terraform
terraform destroy -var-file=terraform.tfvars
```

Review the Terraform plan carefully before destroying resources. The generated key pair and encrypted EBS volume are also removed with the stack.
