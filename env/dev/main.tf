provider "aws" {
  region = var.region
}

module "ec2" {
  source            = "../../modules/ec2"
  env               = var.env
  ami               = var.ami
  instance_type     = var.instance_type
  subnet_id         = var.subnet_id
  security_group_id = var.security_group_id
  key_name          = var.key_name
}
