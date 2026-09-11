variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "instance_type" {
  type    = string
  default = "g4dn.xlarge"
}

variable "ssh_cidr" {
  type        = string
  description = "CIDR allowed to SSH to the instance, for example 203.0.113.10/32."
}

variable "ami_id" {
  type        = string
  description = "Ubuntu 24.04 AMI ID for the selected region."
}

variable "key_name" {
  type = string
}
