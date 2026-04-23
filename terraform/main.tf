# ---------------------------------------------------------------------------
# Simulation Infrastructure — Main Configuration
# ---------------------------------------------------------------------------
# Provisions a self-contained VPC with a simulation-ready EC2 instance.
# Designed for CAD/CFD workloads that need direct network access and
# predictable IP addresses for license server whitelisting.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "Simulation"
      Owner       = "DevTeam"
      ManagedBy   = "Terraform"
      Environment = var.environment
    }
  }
}

# ---------------------------------------------------------------------------
# Data Sources
# ---------------------------------------------------------------------------

# Latest Amazon Linux 2023 AMI — always pulls the most recent patched version
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# ---------------------------------------------------------------------------
# Networking — VPC, Subnet, IGW, Route Table
# ---------------------------------------------------------------------------

resource "aws_vpc" "simulation" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "simulation" {
  vpc_id = aws_vpc.simulation.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.simulation.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.simulation.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.simulation.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Security Group — Restricted access for simulation workloads
# ---------------------------------------------------------------------------

resource "aws_security_group" "simulation" {
  name_prefix = "${var.project_name}-sg-"
  description = "Security group for simulation EC2 instances"
  vpc_id      = aws_vpc.simulation.id

  # SSH access — restrict to known CIDR in production
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # Outbound — allow all (needed for package installs, S3 uploads)
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# EC2 Instance — Simulation-Ready Compute
# ---------------------------------------------------------------------------

resource "aws_instance" "simulation" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.simulation.id]
  key_name               = var.key_pair_name
  monitoring             = true # CKV_AWS_126 — detailed CloudWatch monitoring
  ebs_optimized          = true # CKV_AWS_135

  root_block_device {
    volume_size           = var.root_volume_size_gb
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_tokens   = "required" # IMDSv2 enforced — Checkov CKV_AWS_79
    http_endpoint = "enabled"
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail

    # Tag the instance with launch timestamp for cost-guard tracking
    INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id \
      --header "X-aws-ec2-metadata-token: $(curl -s -X PUT \
      http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')")

    # System updates
    dnf update -y
    dnf install -y python3 python3-pip htop

    echo "Simulation instance ready — $(date -u)" > /var/log/simulation-init.log
  EOF

  tags = {
    Name        = "${var.project_name}-instance"
    Project     = "Simulation"
    AutoStop    = "true"
    LaunchedVia = "Terraform"
  }
}

# ---------------------------------------------------------------------------
# Elastic IP — Stable address for license server whitelisting
# ---------------------------------------------------------------------------

resource "aws_eip" "simulation" {
  domain   = "vpc"
  instance = aws_instance.simulation.id

  tags = {
    Name = "${var.project_name}-eip"
  }

  depends_on = [aws_internet_gateway.simulation]
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "instance_id" {
  description = "EC2 Instance ID"
  value       = aws_instance.simulation.id
}

output "public_ip" {
  description = "Elastic IP assigned to the simulation instance"
  value       = aws_eip.simulation.public_ip
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.simulation.id
}

output "ssh_command" {
  description = "SSH command to connect"
  value       = "ssh -i ${var.key_pair_name}.pem ec2-user@${aws_eip.simulation.public_ip}"
}
