terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.50.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# VPC
resource "aws_vpc" "kube_vpc" {
  cidr_block                       = var.vpc_cidr
  enable_dns_support               = "true"
  enable_dns_hostnames             = "true"
  instance_tenancy                 = "default"
  assign_generated_ipv6_cidr_block = "false"

  tags = {
    Name = "kube_vpc"
  }
}

# Subnet
resource "aws_subnet" "kube_subnet" {
  vpc_id                          = aws_vpc.kube_vpc.id
  assign_ipv6_address_on_creation = "false"
  availability_zone               = var.subnet_availability_zone
  cidr_block                      = var.subnet_cidr_block
  map_public_ip_on_launch         = "true"

  tags = {
    Name = "kube_subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "kube_igw" {
  vpc_id = aws_vpc.kube_vpc.id

  tags = {
    Name = "kube_igw"
  }
}

# Route Table
resource "aws_route_table" "kube_rt" {
  vpc_id = aws_vpc.kube_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.kube_igw.id
  }

  tags = {
    Name = "kube_rt"
  }
}

resource "aws_main_route_table_association" "kube_rt_vpc" {
  vpc_id         = aws_vpc.kube_vpc.id
  route_table_id = aws_route_table.kube_rt.id
}

resource "aws_route_table_association" "kube_rt_subnet" {
  subnet_id      = aws_subnet.kube_subnet.id
  route_table_id = aws_route_table.kube_rt.id
}

# security group for master
resource "aws_security_group" "kube_master-sg" {
  name        = "kube_master-sg"
  description = "kube_master-sg"
  vpc_id      = aws_vpc.kube_vpc.id

  tags = {
    Name = "kube_master-sg"
  }
}

# inbound ssh
resource "aws_security_group_rule" "master_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.ssh_to_master
  security_group_id = aws_security_group.kube_master-sg.id
}

# inbound 6443
resource "aws_security_group_rule" "kube_api" {
  type              = "ingress"
  from_port         = 6443
  to_port           = 6443
  protocol          = "tcp"
  cidr_blocks       = var.kubeapi_to_master
  security_group_id = aws_security_group.kube_master-sg.id
}

# inbound from same segment
resource "aws_security_group_rule" "master_ingress_from_same_seg" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "all"
  cidr_blocks       = [aws_subnet.kube_subnet.cidr_block]
  security_group_id = aws_security_group.kube_master-sg.id
}

# outbound
resource "aws_security_group_rule" "master_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "all"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.kube_master-sg.id
}

# security group for worker
resource "aws_security_group" "kube_worker-sg" {
  name        = "kube_worker-sg"
  description = "kube_worker-sg"
  vpc_id      = aws_vpc.kube_vpc.id

  tags = {
    Name = "kube_worker-sg"
  }
}

# inbound 22
resource "aws_security_group_rule" "worker_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.ssh_to_worker
  security_group_id = aws_security_group.kube_worker-sg.id
}

# inbound nodeport
resource "aws_security_group_rule" "worker_nodeport" {
  type              = "ingress"
  from_port         = 30000
  to_port           = 32767
  protocol          = "tcp"
  cidr_blocks       = var.nodeport_to_worker
  security_group_id = aws_security_group.kube_worker-sg.id
}

# inbound from same segment
resource "aws_security_group_rule" "worker_ingress_from_same_seg" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "all"
  cidr_blocks       = [aws_subnet.kube_subnet.cidr_block]
  security_group_id = aws_security_group.kube_worker-sg.id
}

# inbound from same segment
resource "aws_security_group_rule" "worker_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "all"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.kube_worker-sg.id
}

# key for ec2
resource "aws_key_pair" "kube_sshkey" {
  key_name   = "kube_sshkey"
  public_key = file(var.pubkey_path)
}

# make master ec2
resource "aws_instance" "master" {
  ami                         = var.instance_ami
  instance_type               = "t2.medium"
  key_name                    = aws_key_pair.kube_sshkey.id
  subnet_id                   = aws_subnet.kube_subnet.id
  private_ip                  = "10.0.1.100"
  security_groups             = [aws_security_group.kube_master-sg.id]
  associate_public_ip_address = true
  root_block_device {
    volume_size           = "10"
    volume_type           = "gp2"
    delete_on_termination = "true"
  }
  tags = {
    Name = "kube_master"
  }
}

# make worker ec2
resource "aws_instance" "worker" {
  count                       = var.worker_count
  ami                         = var.instance_ami
  instance_type               = "t2.medium"
  key_name                    = aws_key_pair.kube_sshkey.id
  subnet_id                   = aws_subnet.kube_subnet.id
  private_ip                  = format("10.0.1.10%g", count.index + 1)
  security_groups             = [aws_security_group.kube_worker-sg.id]
  associate_public_ip_address = true
  root_block_device {
    volume_size           = "10"
    volume_type           = "gp2"
    delete_on_termination = "true"
  }

  tags = {
    Name = format("kube_worker-%g", count.index + 1)
  }
}

output "master_public_ip" {
  value = aws_instance.master.public_ip
}

output "worker_public_ip" {
  value = aws_instance.worker[*].public_ip 
}
