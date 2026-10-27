# ============================================
# VPC
# ============================================
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "platform-lab-vpc" }
}

# ============================================
# Public Subnet
# ============================================
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"

  tags = { Name = "platform-lab-public-subnet" }
}

# ============================================
# Internet Gateway
# ============================================
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "platform-lab-igw" }
}

# ============================================
# Route Table
# ============================================
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "platform-lab-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
# ============================================
# Security Group
# ============================================
resource "aws_security_group" "lab" {
  name        = "platform-lab-sg"
  description = "Allow SSH, HTTP, and app port"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP for load balancer"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "App port for direct testing"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "MongoDB from internal VPC only"
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "platform-lab-sg" }
}

# ============================================
# Key Pair
# ============================================
resource "aws_key_pair" "lab" {
  key_name   = var.key_pair_name
  public_key = var.ssh_public_key != "" ? var.ssh_public_key : file(pathexpand(var.public_key_path))
}

# ============================================
# EC2 Instances
# ============================================
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's official owner ID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-resolute-26.04-amd64-server-*"]
  }
}

locals {
  instances = {
    lb   = { type = "t3.micro", private_ip = "10.0.1.10" }
    app1 = { type = "t3.micro", private_ip = "10.0.1.11" }
    app2 = { type = "t3.micro", private_ip = "10.0.1.12" }
    db   = { type = "t3.micro", private_ip = "10.0.1.13" }
  }
}

resource "aws_instance" "lab" {
  for_each = local.instances

  ami                    = data.aws_ami.ubuntu.id
  instance_type          = each.value.type
  key_name               = aws_key_pair.lab.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.lab.id]
  private_ip             = each.value.private_ip

  tags = { Name = each.key }
}
