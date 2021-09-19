module "vpc-rando" {
  source = "terraform-aws-modules/vpc/aws"

  name = "my-vpc-rando"
  cidr = "10.1.0.0/16"

  azs             = ["ap-southeast-2a", "ap-southeast-2b", "ap-southeast-2c"]
  public_subnets  = ["10.1.101.0/24", "10.1.102.0/24", "10.1.103.0/24"]

  enable_nat_gateway = false
  enable_vpn_gateway = false

  tags = {
    Terraform = "true"
    Environment = "dev"
    VPC = "rando"
  }
}