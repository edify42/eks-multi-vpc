data "aws_eks_cluster" "eks" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "eks" {
  name = module.eks.cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks.token
}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"

  cluster_version = "1.21"
  cluster_name    = "my-cluster"
  vpc_id          = module.vpc-k8s.vpc_id
  subnets         = module.vpc-k8s.public_subnets
  cluster_create_endpoint_private_access_sg_rule = true
  cluster_endpoint_private_access_cidrs = module.vpc-k8s.public_subnets
}