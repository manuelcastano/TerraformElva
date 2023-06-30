variable "instance_type" {
  description="The instance type for the ec2 instances"
  default = "t2.micro"
  type = string
}

# Defining CIDR Block for VPC
variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

# Defining CIDR Block for Subnet
variable "subnet_cidr" {
  default = "10.0.1.0/24"
}
# Defining CIDR Block for 2d Subnet
variable "subnet1_cidr" {
  default = "10.0.2.0/24"
}

variable "load_balancer_type" {
  default = "application"
}

variable "master_password" {
  default = "castano123"
}

variable "instance_class_rds" {
  default = "db.t3.medium"
}