# ---------------------------------------------------------------------------
# Variables — Parameterized inputs for the simulation infrastructure
# ---------------------------------------------------------------------------
# Defaults are set for a PoC environment in ap-south-1 (Mumbai).
# Override via CLI, tfvars, or GitHub Actions workflow_dispatch inputs.
# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Environment tag (poc, staging, production)"
  type        = string
  default     = "poc"

  validation {
    condition     = contains(["poc", "staging", "production"], var.environment)
    error_message = "Environment must be one of: poc, staging, production."
  }
}

variable "project_name" {
  description = "Project name used as prefix for all resource names"
  type        = string
  default     = "sim-infra"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type for the simulation workload"
  type        = string
  default     = "t3.medium"

  validation {
    condition = contains([
      "t3.medium",
      "t3.large",
      "t3.xlarge",
      "c5.xlarge",   # Compute-optimized for CFD
      "c5.2xlarge",  # Heavy simulation workloads
      "r5.large",    # Memory-optimized for large CAD assemblies
    ], var.instance_type)
    error_message = "Instance type must be from the approved simulation instance list."
  }
}

variable "key_pair_name" {
  description = "Name of the EC2 key pair for SSH access"
  type        = string
  default     = "simulation-keypair"
}

variable "root_volume_size_gb" {
  description = "Size of the root EBS volume in GB"
  type        = number
  default     = 50

  validation {
    condition     = var.root_volume_size_gb >= 20 && var.root_volume_size_gb <= 500
    error_message = "Root volume must be between 20 and 500 GB."
  }
}

variable "allowed_ssh_cidrs" {
  description = "List of CIDR blocks allowed to SSH into the instance"
  type        = list(string)
  default     = ["0.0.0.0/0"] # RESTRICT THIS in production

  validation {
    condition     = length(var.allowed_ssh_cidrs) > 0
    error_message = "At least one SSH CIDR must be specified."
  }
}
