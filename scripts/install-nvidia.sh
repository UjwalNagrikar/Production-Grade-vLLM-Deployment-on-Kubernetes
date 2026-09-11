#!/usr/bin/env bash
set -euo pipefail

apt-get update
apt-get install -y ubuntu-drivers-common
ubuntu-drivers install
apt-get install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=containerd
systemctl restart containerd || true
nvidia-smi
