data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
}

# global constants
locals {
  aws_account_id = data.aws_caller_identity.current.account_id
  region         = data.aws_region.current.name
  # enum subnet_type
  subnet_type_public  = "public"
  subnet_type_private = "private"
  # enum ip_protocol
  ip_protocol_tcp = "tcp"
  ip_protocol_udp = "udp"
  ip_protocol_all = "all"
  # enum vpc_entpoind_type
  vpc_endpoint_type_interface = "Interface"
  vpc_endpoint_type_gateway   = "Gateway"
  # enum volume_type
  volume_type_gp3 = "gp3"
  #volume_type_gp2 = "gp2"
  #volume_type_io2 = "io2"
  # enu imagebuilder_component_platform
  imagebuilder_component_platform_linux = "Linux"
  #imagebuilder_component_platform_windows = "Windows"
  # enum autoscaling_group_healh_check_type
  autoscaling_group_healh_check_type_ec2 = "EC2"
  #autoscaling_group_healh_check_type_elb = "ELB"
  # enum ec2_instance_type
  ec2_instance_type_t2_nano  = "t2.nano"
  ec2_instance_type_t3_nano  = "t3.nano"
  ec2_instance_type_t3a_nano = "t3a.nano"
  # enum lambda_runtime
  lambda_runtime_python_3_11 = "python3.11"
  # enum sns_subscription_protocol
  sns_subscription_protocol_email = "email"
  # enum lambda_function_url_authorization_type
  #lambda_function_url_authorization_type_aws_iam = "AWS_IAM"
  lambda_function_url_authorization_type_none = "NONE"

  # well known protocol
  protocol_https = {
    ip_protocol = local.ip_protocol_tcp
    port_range = {
      from = 443
      to   = 443
    }
  }
  protocol_dns_tcp = {
    ip_protocol = local.ip_protocol_tcp
    port_range = {
      from = 53
      to   = 53
    }
  }
  protocol_dns_udp = {
    ip_protocol = local.ip_protocol_udp
    port_range = {
      from = 53
      to   = 53
    }
  }

  project_name = "ec2-automation"

  al2_arn_pattern = "arn:aws:imagebuilder:${local.region}:aws:image/amazon-linux-2-x86/x.x.x"
}
