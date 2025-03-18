provider "aws" {
  region = var.aws_region
}

resource "aws_instance" "partha_web_instance" {
	ami = var.ami_id
	instance_type = "t2.micro"
	subnet_id = var.subnet_id
	vpc_security_group_ids =[var.security_group_id]
	key_name = var.key_pair_name
	associate_public_ip_address = true

	tags = {
		Name = "Partha-ec2-terraform"
	}
}


