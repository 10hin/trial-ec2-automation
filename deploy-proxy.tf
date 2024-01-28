resource "aws_autoscaling_group" "proxy" {
  name = "${local.project_name}-proxy"

  vpc_zone_identifier = module.deploy_network.private_subnets

  max_size         = 1
  min_size         = 0
  desired_capacity = var.status == "up" ? 1 : 0

  health_check_type         = local.autoscaling_group_healh_check_type_elb
  health_check_grace_period = 300

  force_delete = true

  dynamic "tag" {
    for_each = data.aws_default_tags.current.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  launch_template {
    id      = aws_launch_template.proxy.id
    version = "$Default"
  }

  traffic_source {
    identifier = aws_lb_target_group.proxy.arn
    type       = local.autoscaling_group_traffic_source_type_elbv2
  }
}
resource "aws_launch_template" "proxy" {
  name = "${local.project_name}-proxy"

  iam_instance_profile {
    arn = aws_iam_instance_profile.proxy.arn
  }

  instance_type = local.ec2_instance_type_t3_nano

  vpc_security_group_ids = [aws_security_group.proxy.id]

  image_id = flatten([
    for output in data.aws_imagebuilder_image.al2.output_resources :
    [
      for ami in output.amis :
      ami.image if ami.region == local.region
    ] if contains(keys(output), "amis")
  ])[0]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    http_protocol_ipv6          = "disabled"
    instance_metadata_tags      = "enabled"
  }

  private_dns_name_options {
    enable_resource_name_dns_a_record    = true
    enable_resource_name_dns_aaaa_record = false
    hostname_type                        = "ip-name"
  }

  tag_specifications {
    resource_type = "instance"
    tags          = data.aws_default_tags.current.tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = data.aws_default_tags.current.tags
  }

  tag_specifications {
    resource_type = "network-interface"
    tags          = data.aws_default_tags.current.tags
  }

  update_default_version = true

  lifecycle {
    ignore_changes = [
      image_id,
      description,
      tags,
      tags_all,
    ]
  }
}
resource "aws_security_group" "proxy" {
  name   = "proxy"
  vpc_id = module.deploy_network.vpc_id
}
resource "aws_vpc_security_group_egress_rule" "to_internet" {
  security_group_id = aws_security_group.proxy.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = local.protocol_https.ip_protocol
  from_port         = local.protocol_https.port_range.from
  to_port           = local.protocol_https.port_range.to
}

resource "aws_iam_role" "proxy" {
  name               = "${local.project_name}-proxy"
  assume_role_policy = data.aws_iam_policy_document.allow_assume_by_instance.json
}
resource "aws_iam_role_policy_attachment" "proxy_ssm" {
  role       = aws_iam_role.proxy.name
  policy_arn = data.aws_iam_policy.AmazonSSMManagedInstanceCore.arn
}
resource "aws_iam_role_policy_attachment" "proxy_metrics" {
  role       = aws_iam_role.proxy.name
  policy_arn = data.aws_iam_policy.CloudWatchAgentServerPolicy.arn
}
resource "aws_iam_instance_profile" "proxy" {
  role = aws_iam_role.proxy.name
  name = aws_iam_role.proxy.name
}

resource "aws_lb" "proxy" {
  for_each           = var.status == "up" ? toset(["this"]) : toset([])
  name               = "${local.project_name}-proxy"
  load_balancer_type = local.load_balancer_type_network
  internal           = true
  security_groups    = [aws_security_group.proxy_lb.id]

  subnets = module.deploy_network.private_subnets
}

resource "aws_lb_listener" "proxy" {
  for_each          = aws_lb.proxy
  load_balancer_arn = aws_lb.proxy[each.key].arn
  port              = local.tcp_port_squid
  protocol          = local.lb_protocol_tcp
  default_action {
    type             = local.lb_listener_action_type_forward
    target_group_arn = aws_lb_target_group.proxy.arn
  }
}

resource "aws_lb_target_group" "proxy" {
  name     = "${local.project_name}-proxy"
  port     = local.tcp_port_squid
  protocol = local.lb_protocol_tcp
  vpc_id   = module.deploy_network.vpc_id
  health_check {
    enabled             = true
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    port                = local.tcp_port_squid
    protocol            = local.lb_protocol_http
    path                = "/"
    matcher             = "400"
    timeout             = 3
  }
}

resource "aws_security_group" "proxy_lb" {
  name   = "${local.project_name}-proxy-lb"
  vpc_id = module.deploy_network.vpc_id
}

resource "aws_route53_record" "proxy_lb" {
  for_each = aws_lb.proxy

  zone_id = aws_route53_zone.deploy_internal.zone_id
  name    = "proxy.vpc.internal"
  type    = local.dns_record_type_A
  alias {
    name                   = aws_lb.proxy[each.key].dns_name
    zone_id                = aws_lb.proxy[each.key].zone_id
    evaluate_target_health = true
  }
}
