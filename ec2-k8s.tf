resource "aws_security_group" "nodes" {
  name        = "${local.cluster_name}-nodes"
  description = "Security group for all masters/nodes in the cluster"
  vpc_id      = module.vpc-k8s.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    "Name"                                      = local.cluster_name
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
  }
}

resource "aws_security_group_rule" "nodes-self" {
  description              = "Allow node to communicate with each other"
  from_port                = 0
  protocol                 = "-1"
  security_group_id        = aws_security_group.nodes.id
  source_security_group_id = aws_security_group.nodes.id
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "node-master" {
  description              = "Allow worker Kubelets and pods to receive communication from the cluster control plane"
  from_port                = 1025
  protocol                 = "tcp"
  security_group_id        = aws_security_group.nodes.id
  source_security_group_id = module.eks.cluster_primary_security_group_id
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "node-master-https" {
  description              = "Required for additional k8s services like metrics-server"
  from_port                = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.nodes.id
  source_security_group_id = module.eks.cluster_primary_security_group_id
  to_port                  = 443
  type                     = "ingress"
}

resource "aws_iam_instance_profile" "nodes" {
  name = "${local.cluster_name}-nodes"
  role = aws_iam_role.nodes-assume-role.name
}

resource "aws_iam_role" "nodes-assume-role" {
  name = "${local.cluster_name}-nodes"
  path = "/"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
               "Service": "ec2.amazonaws.com"
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF
}

resource "aws_iam_role_policy" "describe_spot" {
  name = "describe_spot_policy"
  role = aws_iam_role.nodes-assume-role.id

  policy = <<-EOF
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Action": [
          "ec2:DescribeSpotInstanceRequests",
          "ec2:CreateTags"
        ],
        "Effect": "Allow",
        "Resource": "*"
      }
    ]
  }
  EOF
}

resource "aws_iam_role_policy_attachment" "nodes-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.nodes-assume-role.name
}

resource "aws_iam_role_policy_attachment" "nodes-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.nodes-assume-role.name
}

resource "aws_iam_role_policy_attachment" "nodes-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.nodes-assume-role.name
}

resource "aws_iam_role_policy_attachment" "nodes-AmazonSSMManagedInstanceCore" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.nodes-assume-role.name
}

# EKS currently documents this required userdata for EKS worker nodes to
# properly configure Kubernetes applications on the EC2 instance.
# We implement a Terraform local here to simplify Base64 encoding this
# information into the AutoScaling Launch Configuration.
# More information: https://docs.aws.amazon.com/eks/latest/userguide/launch-workers.html
locals {
  default-node-userdata = <<USERDATA
#!/bin/bash
set -o xtrace

/etc/eks/bootstrap.sh --apiserver-endpoint '${module.eks.cluster_endpoint}' \
--b64-cluster-ca '${module.eks.cluster_certificate_authority_data}' '${local.cluster_name}'
USERDATA

}

resource "aws_launch_template" "default-nodes" {
  name_prefix                 = local.cluster_name
  image_id                    = var.node-ami
  instance_type               = var.node-type
  update_default_version      = true
  ebs_optimized               = true
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      encrypted = true
      volume_size = 40
      volume_type = "gp3"
    }
  }
  iam_instance_profile {
    name = aws_iam_instance_profile.nodes.name
  }
  user_data = base64encode(local.default-node-userdata)
  network_interfaces {
    associate_public_ip_address = true
    security_groups = [ aws_security_group.nodes.id ]
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "optional"
    http_put_response_hop_limit = 2
  }

  tags = {
    team = "platform"
  }
}

resource "aws_autoscaling_group" "default_nodes" {
  desired_capacity     = 1
  max_size             = var.node-max-amount
  min_size             = var.node-min-amount
  name                 = local.cluster_name
  vpc_zone_identifier  = module.vpc-k8s.public_subnets

  wait_for_elb_capacity = var.node-min-amount

  mixed_instances_policy {
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.default-nodes.id
        version = aws_launch_template.default-nodes.latest_version
      }
      override {
        instance_type = "m5.large"
      }
    }
    instances_distribution {
      on_demand_allocation_strategy = "prioritized"
      on_demand_base_capacity = "0"
      on_demand_percentage_above_base_capacity = "0"
      spot_allocation_strategy = "capacity-optimized"
      spot_max_price = "0.5"
    }
  }

  tag {
    key                 = "Name"
    value               = "${local.cluster_name}"
    propagate_at_launch = true
  }


  tag {
    key                 = "cluster_name"
    value               = local.cluster_name
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${local.cluster_name}"
    value               = "owned"
    propagate_at_launch = true
  }

  tag {
    key                 = "aws-node-termination-handler/managed"
    value               = ""
    propagate_at_launch = true
  }

}