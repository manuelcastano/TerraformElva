# First, I need to say I'm sorry because I didn't use modules to encapsulate the different resources for time problems.
# Second, It's a bad practice to hard code the credentials, but I will do it this time because it's more practical for the purpose of this challenge.

provider "aws" {
  region = "eu-west-3"
    access_key = "AKIA3FIMMF7HBZ2HXDMA"
	secret_key = "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"
}

# To begin with the exercise, firt we create a virtual private network where will all the resources.
resource "aws_vpc" "vpc" {
  cidr_block       = "${var.vpc_cidr}"
  instance_tenancy = "default"
  tags = {
    Name = "VPC"
  }
}

# This gateway is for access from the internet
resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.vpc.id
}

# Then, I resume all the security rules in just one, where will be applicable to all the resources.
resource "aws_security_group" "sg" {
  name        = "lb-security-group"
  description = "Security group for load balancer"
  vpc_id      = aws_vpc.vpc.id
  # Inbound Rules
  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # HTTPS access from anywhere
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # This is to permit access to the database only from the ec2 instances.
  ingress {
    from_port   = 3306  # Assuming MySQL database
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["${var.subnet_cidr}", "${var.subnet1_cidr}"]
  }
# Outbound Rules
  # Internet access to anywhere
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#Then, we create two subnets for the resources.
resource "aws_subnet" "subnet" {
  vpc_id                  = "${aws_vpc.vpc.id}"
  cidr_block             = "${var.subnet_cidr}"
  map_public_ip_on_launch = true
  availability_zone = "eu-west-3a"
}
# Creating 2nd subnet 
resource "aws_subnet" "subnet1" {
  vpc_id                  = "${aws_vpc.vpc.id}"
  cidr_block             = "${var.subnet1_cidr}"
  map_public_ip_on_launch = true
  availability_zone = "eu-west-3b"
}

#Creating Route Table
#This route table is to redirect the traffic from the internet to the subnets
resource "aws_route_table" "route" {
    vpc_id = "${aws_vpc.vpc.id}"
route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.example.id}"
    }
tags = {
        Name = "Route to internet"
    }
}
resource "aws_route_table_association" "rt1" {
    subnet_id = "${aws_subnet.subnet.id}"
    route_table_id = "${aws_route_table.route.id}"
}
resource "aws_route_table_association" "rt2" {
    subnet_id = "${aws_subnet.subnet1.id}"
    route_table_id = "${aws_route_table.route.id}"
}

# Then we add the load balancer
resource "aws_lb" "lb" {
  name               = "lb"
  internal           = false
  load_balancer_type = "${var.load_balancer_type}"
  security_groups    = [aws_security_group.sg.id]
  subnets            = ["${aws_subnet.subnet.id}", "${aws_subnet.subnet1.id}"]
}

# This is the image for the virtual machines for ec2 instances.
data "aws_ami" "linux" {
   most_recent = true
   owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
#The launch configuration for the ec2 instances
resource "aws_launch_configuration" "lc" {
  name                   = "launch-configuration"
  image_id               = data.aws_ami.linux.id
  instance_type          = "${var.instance_type}"
  key_name               = "my-key-pair"
  security_groups = [aws_security_group.sg.id]
  user_data = <<-EOT
    #!/bin/bash
    echo "Hello, World" > /var/www/html/index.html
    nohup python -m SimpleHTTPServer 80 &
    EOT
}
#The autoscaling group
resource "aws_autoscaling_group" "asg" {
  name                      = "asg"
  min_size                  = 2
  max_size                  = 4
  desired_capacity          = 2
  launch_configuration = "${aws_launch_configuration.lc.name}"
  target_group_arns = [aws_lb_target_group.tg.arn]
  vpc_zone_identifier = ["${aws_subnet.subnet.id}", "${aws_subnet.subnet1.id}"]
}

resource "aws_lb_target_group" "tg" {
  name     = "example-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "${aws_vpc.vpc.id}"
}

resource "aws_lb_listener" "example" {
  load_balancer_arn = aws_lb.lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

output "dns_name" {
  description = "The DNS name of the load balancer."
  value       = aws_lb.lb.dns_name
}

#Desde aqui empieza la configuración de la base de datos
resource "aws_db_subnet_group" "example" {
  name       = "example-subnet-group"
  subnet_ids = ["${aws_subnet.subnet.id}", "${aws_subnet.subnet1.id}"]
}

resource "aws_rds_cluster_parameter_group" "example" {
  name        = "example-parameter-group"
  family      = "aurora-postgresql14"
  description = "Example parameter group for Aurora"
}

resource "aws_rds_cluster" "example" {
  cluster_identifier      = "example-cluster"
  engine                  = "aurora-postgresql"
  engine_version          = "14.5"
  master_username         = "manuel"
  master_password         = "${var.master_password}"
  database_name           = "example_db"
  backup_retention_period = 7
  preferred_backup_window = "02:00-03:00"
  db_subnet_group_name    = aws_db_subnet_group.example.name
  vpc_security_group_ids  = [aws_security_group.sg.id]

  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.example.name
}

resource "aws_rds_cluster_instance" "example" {
  cluster_identifier = aws_rds_cluster.example.id
  identifier         = "example-instance"
  engine         = "aurora-postgresql"
  instance_class     = "${var.instance_class_rds}"  # Update with your desired instance type
}

#Por último, esta es la información de conexión a la base de datos
output "rds_endpoint" {
  value = aws_rds_cluster.example.endpoint
}

output "rds_username" {
  value = aws_rds_cluster.example.master_username
}

output "rds_password" {
  sensitive = true
  value = aws_rds_cluster.example.master_password
}

output "rds_database_name" {
  value = aws_rds_cluster.example.database_name
}