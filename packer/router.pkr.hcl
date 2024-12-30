packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.8"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "amazon-ebs" "ubuntu" {
  ami_name      = "bird-router-ami"
  instance_type = "t4g.micro"
  region        = "us-east-1"

  vpc_id    = "vpc-06dbf74882e61cf77"
  subnet_id = "subnet-0ebcf9b60015c34f1"

  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"]
  }
  ssh_username = "ubuntu"
}

build {
  name = "bird-router-ami"
  sources = [
    "source.amazon-ebs.ubuntu"
  ]
  provisioner "shell" {
    inline = [
      "sudo apt update",
      "sudo apt install -y bird2",
      "sudo systemctl enable bird",
      "sudo systemctl start bird"
    ]
  }
}

