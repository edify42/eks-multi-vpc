data "aws_caller_identity" "current" {}

resource "aws_vpc_peering_connection" "yolo" {
  peer_owner_id = data.aws_caller_identity.current.account_id
  peer_vpc_id   = module.vpc-k8s.vpc_id
  vpc_id        = module.vpc-rando.vpc_id
  auto_accept   = true
}