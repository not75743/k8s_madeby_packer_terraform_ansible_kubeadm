packer {
  required_plugins {
    amazon = {
      version = ">= 0.0.1"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "amazon-ebs" "centos" {
  ami_name      = "${var.ami_prefix}-${local.timestamp}"
  instance_type = var.instance_type
  region        = var.region
  source_ami    = var.source_ami
  ssh_username  = var.ssh_username
  tags = {
    Name = "${var.ami_prefix}-${local.timestamp}"
  }
}

locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
}

build {
  sources = [
    "source.amazon-ebs.centos"
  ]

  provisioner "ansible" {
    playbook_file = "./ansible/playbook.yml"
    sftp_command = "/usr/libexec/openssh/sftp-server -e"
  }
}
