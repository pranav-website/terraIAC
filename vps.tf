terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.27.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }
  }

  cloud {
    organization = "pranav-personal"
    workspaces {
      name = "vps"
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
    },
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
      description = "HTTPS"
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
    values = ["al2023-ami-*-arm64"]
  }
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t4g.nano"
  key_name      = "vpsKey"

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
  value     = aws_instance.web.public_ip
  sensitive = true
}

resource "aws_iam_role" "github_terraform" {
  name = "github-terraform"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = { # who is assuming? Github OIDC provider.
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity" # assume role given a web identity (OIDC) token
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" # audience val set by Github
            "token.actions.githubusercontent.com:sub" = [                   # subject: in this case id of caller
              "repo:pranav-website/terraIAC:ref:refs/heads/main",
              "repo:pranav-website/terraIAC:pull_request"
            ]
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "terraform_admin" {
  role       = aws_iam_role.github_terraform.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_role" "github_sscode_deploy" {
  name = "github-sscode-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = [
              "repo:pranav-website/sscode:ref:refs/heads/main",
            ]
          }
        }
      }
    ]
  })
}

data "aws_iam_policy_document" "github_sscode_deploy" {
  statement {
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "github_sscode_deploy" {
  name        = "GitHubSscodeDeployPolicy"
  description = "Allows the sscode GitHub Actions deploy workflow to discover the EC2 host."
  policy      = data.aws_iam_policy_document.github_sscode_deploy.json
}

resource "aws_iam_role_policy_attachment" "github_sscode_deploy" {
  role       = aws_iam_role.github_sscode_deploy.name
  policy_arn = aws_iam_policy.github_sscode_deploy.arn
}

output "github_sscode_deploy_role_arn" {
  value = aws_iam_role.github_sscode_deploy.arn
}
