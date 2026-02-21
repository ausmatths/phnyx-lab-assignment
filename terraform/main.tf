terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_vpc" "phnyx" {
  id = "vpc-05f8ec76aeb1a1599"
}

data "aws_subnet" "public" {
  id = "subnet-0f670e7e023374a50"
}

data "aws_security_group" "ec2" {
  id = "sg-013546579e5bb1c03"
}

data "aws_lb_target_group" "service1" {
  name = "phnyx-tg-service1"
}

data "aws_lb_target_group" "service2" {
  name = "phnyx-tg-service2"
}

resource "aws_iam_role" "ec2_ecr_role" {
  name = "phnyx-ec2-ecr-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_access" {
  role       = aws_iam_role.ec2_ecr_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "phnyx-ec2-profile"
  role = aws_iam_role.ec2_ecr_role.name
}

resource "aws_launch_template" "phnyx" {
  name_prefix   = "phnyx-lt-"
  image_id      = "ami-0071174ad8cbb9e17"
  instance_type = "t2.micro"
  key_name      = "phnyx-key"

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [data.aws_security_group.ec2.id]
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y docker.io docker-compose-v2
    snap install aws-cli --classic
    systemctl start docker
    systemctl enable docker
    aws ecr get-login-password --region us-east-1 | docker login \
      --username AWS \
      --password-stdin 219711034407.dkr.ecr.us-east-1.amazonaws.com
    cat > /home/ubuntu/docker-compose.yml << 'COMPOSE'
services:
  service1:
    image: 219711034407.dkr.ecr.us-east-1.amazonaws.com/service1:latest
    ports:
      - "5000:5000"
    environment:
      - FLASK_ENV=production
    restart: always
  service2:
    image: 219711034407.dkr.ecr.us-east-1.amazonaws.com/service2:latest
    ports:
      - "5001:5001"
    environment:
      - FLASK_ENV=production
    restart: always
COMPOSE
    cd /home/ubuntu
    docker compose up -d
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = { Name = "phnyx-asg-instance" }
  }
}

resource "aws_autoscaling_group" "phnyx" {
  name                = "phnyx-asg"
  min_size            = 2
  desired_capacity    = 2
  max_size            = 4
  vpc_zone_identifier = [data.aws_subnet.public.id]

  launch_template {
    id      = aws_launch_template.phnyx.id
    version = "$Latest"
  }

  target_group_arns = [
    data.aws_lb_target_group.service1.arn,
    data.aws_lb_target_group.service2.arn
  ]

  health_check_type         = "ELB"
  health_check_grace_period = 120

  tag {
    key                 = "Name"
    value               = "phnyx-asg-instance"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "scale_out" {
  name                   = "phnyx-scale-out"
  autoscaling_group_name = aws_autoscaling_group.phnyx.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 40.0
  }
}

output "asg_name" {
  value = aws_autoscaling_group.phnyx.name
}

output "launch_template_id" {
  value = aws_launch_template.phnyx.id
}
