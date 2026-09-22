variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "g4dn.xlarge"
}

variable "ami_id" {
  description = "Ubuntu 24.04 AMI ID"
  type        = string
  default     = "ami-0ba4172b23e57d5a8"
}

variable "key_name" {
  description = "EC2 key pair name"
  type        = string
  default     = "vllm_model-deployment"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 100
}