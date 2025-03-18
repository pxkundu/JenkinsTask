terraform {
  backend "s3" {
    bucket         = "partha-terraform-state-bucket"
    key            = "ec2/terraform.tfstate"   # Organize state file under ec2/ path
    region         = "us-east-1"
    encrypt        = true
    # If you create a lock table later, you can add:
    # dynamodb_table = "partha-terraform-lock-table"
  }
}
