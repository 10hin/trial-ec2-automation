terraform {
  required_version = "~> 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
  default_tags {
    tags = {
      "Purpose" = "EC2Automation"
    }
  }
}

provider "archive" {}


#
# NETWORK
#

locals {
  deploy_az_count = 1
  deploy_vpc_cidr = "10.0.0.0/16"
  deploy_subnet_types = [
    local.subnet_type_public,
    local.subnet_type_private,
  ]
  deploy_interface_endpoints = [
    "ssm",
    "ec2messages",
    "ssmmessages",
    "ec2",
    "monitoring",
    "logs",
  ]
  deploy_interface_endpoint_az_count = 1
  deploy_gateway_endpoints = [
    "s3",
  ]

  # computed variable (do not update unless you know what you are doing)
  deploy_dns_endpoint_cidr = cidrsubnet(local.deploy_vpc_cidr, 16, 2)
  deploy_az_ids            = slice(data.aws_availability_zones.available.zone_ids, 0, local.deploy_az_count)
  deploy_az_names          = slice(data.aws_availability_zones.available.names, 0, local.deploy_az_count)
  deploy_subnet_type_cidrs = {
    for idx, subnet_type in local.deploy_subnet_types :
    subnet_type => cidrsubnet(local.deploy_vpc_cidr, ceil(log(length(local.deploy_subnet_types), 2)), idx)
  }
  deploy_subnet_cidrs = {
    for subnet_type in local.deploy_subnet_types :
    subnet_type => {
      for idx, azid in local.deploy_az_ids :
      azid => cidrsubnet(local.deploy_subnet_type_cidrs[subnet_type], ceil(log(length(local.deploy_az_ids), 2)), idx)
    }
  }
  # /computed variable
}
module "deploy_network" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.2.0"

  name = "${local.project_name}-deploy"
  azs  = local.deploy_az_names
  cidr = local.deploy_vpc_cidr
  public_subnets = [
    for azid in local.deploy_az_ids :
    local.deploy_subnet_cidrs[local.subnet_type_public][azid]
  ]
  private_subnets = [
    for azid in local.deploy_az_ids :
    local.deploy_subnet_cidrs[local.subnet_type_private][azid]
  ]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false
}
resource "aws_vpc_endpoint" "deploy_ifep" {
  for_each = toset(local.deploy_interface_endpoints)

  service_name      = "com.amazonaws.${local.region}.${each.key}"
  vpc_endpoint_type = local.vpc_endpoint_type_interface
  vpc_id            = module.deploy_network.vpc_id
  # run
  # subnet_ids = slice(module.deploy_network.private_subnets, 0, min(local.deploy_interface_endpoint_az_count, local.deploy_az_count))
  # stop
  subnet_ids          = []
  security_group_ids  = [aws_security_group.deploy_ifep[each.key].id]
  private_dns_enabled = true
}
resource "aws_security_group" "deploy_ifep" {
  for_each = toset(local.deploy_interface_endpoints)

  name   = "deploy-vpce-${each.key}"
  vpc_id = module.deploy_network.vpc_id
}
resource "aws_vpc_endpoint" "deploy_gwep" {
  for_each = toset(local.deploy_gateway_endpoints)

  service_name      = "com.amazonaws.${local.region}.${each.key}"
  vpc_endpoint_type = local.vpc_endpoint_type_gateway
  vpc_id            = module.deploy_network.vpc_id
  route_table_ids   = module.deploy_network.private_route_table_ids
}

locals {
  build_az_count = 1
  build_vpc_cidr = "10.128.0.0/16"
  build_subnet_types = [
    local.subnet_type_public,
    local.subnet_type_private,
  ]
  # build_interface_endpoints = [
  #   "ssm",
  #   "ec2messages",
  #   "ssmmessages",
  # ]
  # build_gateway_endpoints = [
  #   "s3",
  # ]

  # computed variable (do not update unless you know what you are doing)
  #build_dns_endpoint_cidr = cidrsubnet(local.build_vpc_cidr, 16, 2)
  build_az_ids   = slice(data.aws_availability_zones.available.zone_ids, 0, local.build_az_count)
  build_az_names = slice(data.aws_availability_zones.available.names, 0, local.build_az_count)
  build_subnet_type_cidrs = {
    for idx, subnet_type in local.build_subnet_types :
    subnet_type => cidrsubnet(local.build_vpc_cidr, ceil(log(length(local.build_subnet_types), 2)), idx)
  }
  build_subnet_cidrs = {
    for subnet_type in local.build_subnet_types :
    subnet_type => {
      for idx, azid in local.build_az_ids :
      azid => cidrsubnet(local.build_subnet_type_cidrs[subnet_type], ceil(log(length(local.build_az_ids), 2)), idx)
    }
  }
  # /computed variable
}
module "build_network" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.2.0"

  name = "${local.project_name}-build"
  azs  = local.build_az_names
  cidr = local.build_vpc_cidr
  public_subnets = [
    for azid in local.build_az_ids :
    local.build_subnet_cidrs[local.subnet_type_public][azid]
  ]
  private_subnets = [
    for azid in local.build_az_ids :
    local.build_subnet_cidrs[local.subnet_type_private][azid]
  ]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false
}
# resource "aws_vpc_endpoint" "build_ifep" {
#   for_each = toset(local.build_interface_endpoints)
#
#   service_name = "com.amazonaws.${local.region}.${each.key}"
#   vpc_endpoint_type = local.vpc_endpoint_type_interface
#   vpc_id = module.build_network.vpc_id
#   subnet_ids = slice(module.build_network.private_subnets, 0, min(local.build_interface_endpoint_az_count, local.build_az_count))
#   private_dns_enabled = true
# }
# resource "aws_security_group" "build_ifep" {
#   for_each = toset(local.build_interface_endpoints)
#
#   name = "build-vpce-${each.key}"
#   vpc_id = module.build_network.vpc_id
# }
# resource "aws_vpc_endpoint" "build_gwep" {
#   for_each = toset(local.build_gateway_endpoints)
#
#   service_name = "com.amazonaws.${local.region}.${each.key}"
#   vpc_endpoint_type = local.vpc_endpoint_type_gateway
#   vpc_id = module.build_network.vpc_id
#   route_table_ids = module.build_network.private_route_table_ids
# }


#
# APPLICATION DEPLOYMENT
#

data "aws_imagebuilder_image" "al2" {
  arn = local.al2_arn_pattern
}

resource "aws_s3_bucket" "persistent_volume" {
  bucket = "persistent-volume-${local.aws_account_id}"
}
resource "aws_s3_bucket_public_access_block" "persistent_volume" {
  bucket = aws_s3_bucket.persistent_volume.bucket

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
data "aws_iam_policy_document" "mount_persistent_volume" {
  statement {
    sid = "MountpointFullBucketAccess"
    actions = [
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.persistent_volume.arn,
    ]
  }
  statement {
    sid = "MountpointFullObjectAccess"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
    ]
    resources = [
      "${aws_s3_bucket.persistent_volume.arn}/*",
    ]
  }
}


#
# Traffic management
#

locals {
  deploy_dns_access = {
    "bastion" = {
      security_group_id = aws_security_group.bastion.id
    }
    "proxy" = {
      security_group_id = aws_security_group.proxy.id
    }
  }
  deploy_s3_access = {
    "bastion" = {
      security_group_id = aws_security_group.bastion.id
    }
    "proxy" = {
      security_group_id = aws_security_group.proxy.id
    }
  }
  sg_to_sg_access = {
    "bastion_to_ssm" = {
      from     = aws_security_group.bastion.id
      to       = aws_security_group.deploy_ifep["ssm"].id
      protocol = local.protocol_https
    }
    "bastion_to_ec2messages" = {
      from     = aws_security_group.bastion.id
      to       = aws_security_group.deploy_ifep["ec2messages"].id
      protocol = local.protocol_https
    }
    "bastion_to_ssmmessages" = {
      from     = aws_security_group.bastion.id
      to       = aws_security_group.deploy_ifep["ssmmessages"].id
      protocol = local.protocol_https
    }
    "bastion_to_ec2" = {
      from     = aws_security_group.bastion.id
      to       = aws_security_group.deploy_ifep["ec2"].id
      protocol = local.protocol_https
    }
    "bastion_to_monitoring" = {
      from     = aws_security_group.bastion.id
      to       = aws_security_group.deploy_ifep["monitoring"].id
      protocol = local.protocol_https
    }
    "bastion_to_logs" = {
      from     = aws_security_group.bastion.id
      to       = aws_security_group.deploy_ifep["logs"].id
      protocol = local.protocol_https
    }
    "proxy_to_ssm" = {
      from     = aws_security_group.proxy.id
      to       = aws_security_group.deploy_ifep["ssm"].id
      protocol = local.protocol_https
    }
    "proxy_to_ec2messages" = {
      from     = aws_security_group.proxy.id
      to       = aws_security_group.deploy_ifep["ec2messages"].id
      protocol = local.protocol_https
    }
    "proxy_to_ssmmessages" = {
      from     = aws_security_group.proxy.id
      to       = aws_security_group.deploy_ifep["ssmmessages"].id
      protocol = local.protocol_https
    }
    "proxy_to_ec2" = {
      from     = aws_security_group.proxy.id
      to       = aws_security_group.deploy_ifep["ec2"].id
      protocol = local.protocol_https
    }
    "proxy_to_monitoring" = {
      from     = aws_security_group.proxy.id
      to       = aws_security_group.deploy_ifep["monitoring"].id
      protocol = local.protocol_https
    }
    "proxy_to_logs" = {
      from     = aws_security_group.proxy.id
      to       = aws_security_group.deploy_ifep["logs"].id
      protocol = local.protocol_https
    }
  }
}

# computed resources (do not update unless you know what you are doing)
# DNS(TCP/UDP)
resource "aws_vpc_security_group_egress_rule" "deploy_dns_tcp" {
  for_each = local.deploy_dns_access

  security_group_id = each.value.security_group_id
  ip_protocol       = local.protocol_dns_tcp.ip_protocol
  from_port         = local.protocol_dns_tcp.port_range.from
  to_port           = local.protocol_dns_tcp.port_range.to
  cidr_ipv4         = local.deploy_dns_endpoint_cidr
}
resource "aws_vpc_security_group_egress_rule" "deploy_dns_udp" {
  for_each = local.deploy_dns_access

  security_group_id = each.value.security_group_id
  ip_protocol       = local.protocol_dns_udp.ip_protocol
  from_port         = local.protocol_dns_udp.port_range.from
  to_port           = local.protocol_dns_udp.port_range.to
  cidr_ipv4         = local.deploy_dns_endpoint_cidr
}

# S3
resource "aws_vpc_security_group_egress_rule" "deploy_s3" {
  for_each = local.deploy_s3_access

  security_group_id = each.value.security_group_id
  ip_protocol       = local.protocol_https.ip_protocol
  from_port         = local.protocol_https.port_range.from
  to_port           = local.protocol_https.port_range.to
  prefix_list_id    = aws_vpc_endpoint.deploy_gwep["s3"].prefix_list_id
}

# SecurityGroup to SecurityGroup
resource "aws_vpc_security_group_egress_rule" "sg_to_sg" {
  for_each = local.sg_to_sg_access

  security_group_id            = each.value.from
  ip_protocol                  = each.value.protocol.ip_protocol
  from_port                    = each.value.protocol.port_range.from
  to_port                      = each.value.protocol.port_range.to
  referenced_security_group_id = each.value.to
}
resource "aws_vpc_security_group_ingress_rule" "sg_to_sg" {
  for_each = local.sg_to_sg_access

  security_group_id            = each.value.to
  ip_protocol                  = each.value.protocol.ip_protocol
  from_port                    = each.value.protocol.port_range.from
  to_port                      = each.value.protocol.port_range.to
  referenced_security_group_id = each.value.from
}
# /computed resources
