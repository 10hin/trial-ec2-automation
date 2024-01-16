resource "aws_autoscaling_group" "proxy" {
  name = "${local.project_name}-proxy"

  vpc_zone_identifier = module.deploy_network.private_subnets

  max_size = 1
  min_size = 0
  # desired_capacity = 1 # run
  desired_capacity = 0 # stop

  health_check_type         = local.autoscaling_group_healh_check_type_ec2
  health_check_grace_period = 300

  force_delete = true

  launch_template {
    id      = aws_launch_template.proxy.id
    version = "$Default"
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
