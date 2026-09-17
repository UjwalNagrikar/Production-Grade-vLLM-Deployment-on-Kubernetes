provider "aws" {
  region = var.region
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "tls_private_key" "vllm" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "vllm" {
  key_name   = var.key_name
  public_key = tls_private_key.vllm.public_key_openssh

  tags = {
    Name        = var.key_name
    Project     = "vLLM Kubernetes"
    Environment = "Portfolio"
  }
}

resource "aws_security_group" "vllm" {
  name        = "vllm-k3s"
  description = "Security group for vLLM Kubernetes EC2 host"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Allow all inbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "vllm-k3s"
    Project     = "vLLM Kubernetes"
    Environment = "Portfolio"
  }
}

resource "aws_iam_role" "node" {
  name = "vllm-k3s-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name    = "vllm-k3s-node"
    Project = "vLLM Kubernetes"
  }
}

resource "aws_iam_instance_profile" "node" {
  name = "vllm-k3s-node"
  role = aws_iam_role.node.name
}

resource "aws_instance" "node" {
  ami           = var.ami_id
  instance_type = var.instance_type

  subnet_id = data.aws_subnets.default.ids[0]

  vpc_security_group_ids = [
    aws_security_group.vllm.id
  ]

  key_name = aws_key_pair.vllm.key_name

  iam_instance_profile = aws_iam_instance_profile.node.name

  associate_public_ip_address = true

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name        = "vllm-k3s-gpu"
    Project     = "vLLM Kubernetes"
    Environment = "Portfolio"
    Model       = "Qwen2.5-3B-Instruct"
  }
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.node.id
}

output "public_ip" {
  description = "Public IP address"
  value       = aws_instance.node.public_ip
}

output "public_dns" {
  description = "Public DNS name"
  value       = aws_instance.node.public_dns
}

output "instance_type" {
  description = "EC2 instance type"
  value       = aws_instance.node.instance_type
}

output "key_name" {
  description = "AWS EC2 key pair name"
  value       = aws_key_pair.vllm.key_name
}

output "private_key_pem" {
  value     = tls_private_key.vllm.private_key_pem
  sensitive = true
}