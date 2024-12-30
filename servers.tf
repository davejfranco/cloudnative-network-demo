locals {

  my_ip           = "212.237.135.167/32"
  vpc_cidr_block  = "10.10.0.0/16"
  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnets  = ["10.10.101.0/24", "10.10.102.0/24", "10.10.103.0/24"]
  private_subnets = ["10.10.1.0/24", "10.10.2.0/24", "10.10.3.0/24"]

  ami = {
    name  = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-*"
    owner = "099720109477"
  }

  ami2 = {
    name  = "bird-router-ami"
    owner = "444106639146"
  }

  routers = {
    count         = 2
    instance_type = "t4g.small"
  }

  gre_tunnel_network = "192.168.1.0/30"

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }

}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.17.0"

  name = "vpc-a"
  cidr = local.vpc_cidr_block

  azs             = local.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  map_public_ip_on_launch = true
  enable_nat_gateway      = false

  tags = local.tags

}

// Generate SSH key pair
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ssh" {
  key_name   = "ssh"
  public_key = tls_private_key.ssh.public_key_openssh
}

// Security group for the routers\
resource "aws_security_group" "routers" {
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.my_ip]
  }

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = -1
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

// Ec2 Routers
data "aws_ami" "routers" {
  most_recent = true

  filter {
    name   = "name"
    values = [local.ami2.name]
  }


  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = [local.ami2.owner]
}

resource "aws_instance" "routers" {
  count = local.routers.count

  ami                    = data.aws_ami.routers.id
  instance_type          = local.routers.instance_type
  key_name               = aws_key_pair.ssh.key_name
  subnet_id              = element(module.vpc.public_subnets, count.index)
  vpc_security_group_ids = [aws_security_group.routers.id]

  #user_data = local.routers.user_data

  tags = merge(local.tags, {
    Name = "router-${count.index + 1}"
  })
}


resource "local_file" "bird_config" {
  count = length(aws_instance.routers)

  content  = templatefile("${path.module}/templates/bird.conf.tpl", { router_id = aws_instance.routers[count.index].private_ip })
  filename = "${path.module}/bird-${aws_instance.routers[count.index].id}.conf"

  depends_on = [aws_instance.routers]
}

resource "null_resource" "routers" {
  count = length(aws_instance.routers)

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.ssh.private_key_pem
    host        = aws_instance.routers[count.index].public_ip
  }

  provisioner "file" {
    source      = local_file.bird_config[count.index].filename
    destination = "/tmp/bird.conf"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo ip tunnel add gre1 mode gre remote ${aws_instance.routers[1 - count.index].private_ip} local ${aws_instance.routers[count.index].private_ip} ttl 255",
      "sudo ip link set gre1 up",
      "sudo ip addr add ${cidrhost(local.gre_tunnel_network, count.index + 1)}/30 dev gre1",

      "sudo cp /tmp/bird.conf /etc/bird/",
      "sudo systemctl restart bird"
    ]
  }

  depends_on = [
    aws_instance.routers,
    local_file.bird_config
  ]
}
