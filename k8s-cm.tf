resource "kubernetes_config_map" "aws-auth" {
  metadata {
    name = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = local.config_map_aws_auth
  }
}

locals {
  config_map_aws_auth = yamlencode(
    [{
      "rolearn": aws_iam_role.nodes-assume-role.arn,
      "username": "system:node:{{EC2PrivateDNSName}}",
      "groups": [
        "system:bootstrappers",
        "system:nodes"
      ]
    }]
  )
}