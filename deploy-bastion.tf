resource "aws_autoscaling_group" "bastion" {
  name = "${local.project_name}-bastion"

  vpc_zone_identifier = module.deploy_network.private_subnets

  max_size         = 1
  min_size         = 0
  desired_capacity = var.status == "up" ? 1 : 0

  health_check_type         = local.autoscaling_group_healh_check_type_ec2
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
    id      = aws_launch_template.bastion.id
    version = "$Default"
  }
}
resource "aws_launch_template" "bastion" {
  name = "${local.project_name}-bastion"

  iam_instance_profile {
    arn = aws_iam_instance_profile.bastion.arn
  }

  instance_type = local.ec2_instance_type_t3_nano

  vpc_security_group_ids = [aws_security_group.bastion.id]

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
resource "aws_security_group" "bastion" {
  name   = "bastion"
  vpc_id = module.deploy_network.vpc_id
}
resource "aws_iam_role" "bastion" {
  name               = "${local.project_name}-bastion"
  assume_role_policy = data.aws_iam_policy_document.allow_assume_by_instance.json
}
resource "aws_iam_role_policy" "bastion_allow_s3_mount" {
  role   = aws_iam_role.bastion.name
  policy = data.aws_iam_policy_document.mount_persistent_volume.json
}
resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = data.aws_iam_policy.AmazonSSMManagedInstanceCore.arn
}
resource "aws_iam_role_policy_attachment" "bastion_metrics" {
  role       = aws_iam_role.bastion.name
  policy_arn = data.aws_iam_policy.CloudWatchAgentServerPolicy.arn
}
resource "aws_iam_instance_profile" "bastion" {
  role = aws_iam_role.bastion.name
  name = aws_iam_role.bastion.name
}
