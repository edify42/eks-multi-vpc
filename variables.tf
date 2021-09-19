locals {
  cluster_name = "my-cluster"
}

variable "node-ami" {
  default = "ami-015f906ef3e2123c0"
  type    = string
}

variable "node-type" {
  default = "c5.medium"
  type    = string
}

variable "node-max-amount" {
  default = "1"
  type    = string
}

variable "node-min-amount" {
  default = "1"
  type    = string
}
