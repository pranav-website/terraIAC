terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "6.27.0"
    }
  }
}

provider "aws" {
  region = "us-west-1"
}

data "aws_vpc" "my_vpc" {
    default = true
}

module "ws_sg" {
  source = "terraform-aws-modules/security-group/aws"

  name        = "web_server_sg"
  description = "Security group for static site VPS"
  vpc_id      = data.aws_vpc.my_vpc.id

  ingress_with_cidr_blocks = [
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
      description = "SSH"
    },
    {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
      description = "HTTP"
    }
  ]

  egress_with_cidr_blocks = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = "0.0.0.0/0"
    }
  ]
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_instance" "web" {
    ami = data.aws_ami.amazon_linux.id
    instance_type = "t4g.nano"

    vpc_security_group_ids = [
        module.ws_sg.security_group_id
    ]

    user_data = <<-EOF
              #!/bin/bash
              dnf install -y nginx
              systemctl enable nginx
              systemctl start nginx
              EOF

    tags = {
        Name = "web-server"
  }
}

output "public_ip" {
  value = aws_instance.web.public_ip
}

terraform { 
  cloud { 
    
    organization = "pranav-personal" 

    workspaces { 
      name = "vps" 
    } 
  } 
}
