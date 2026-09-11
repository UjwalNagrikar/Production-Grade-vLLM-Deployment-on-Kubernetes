provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {
  state = "available"
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

resource "aws_security_group" "vllm" {
  name        = "vllm-k3s"
  description = "Minimal access for the vLLM K3s host"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Allow all inbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "vllm-k3s" }
}

resource "aws_iam_role" "node" {
  name = "vllm-k3s-node"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_instance_profile" "node" {
  name = "vllm-k3s-node"
  role = aws_iam_role.node.name
}

resource "aws_instance" "node" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.vllm.id]
  key_name                    = var.key_name
  iam_instance_profile        = aws_iam_instance_profile.node.name
  associate_public_ip_address = true

  root_block_device {
    volume_size = 100
    volume_type = "gp3"
    encrypted   = true
  }

  tags = { Name = "vllm-k3s-gpu" }
}

output "public_ip" {
  value = aws_instance.node.public_ip
}
