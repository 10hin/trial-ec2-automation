resource "aws_autoscaling_group" "bastion" {
  name = "${local.project_name}-bastion"

  vpc_zone_identifier = module.deploy_network.private_subnets

  max_size         = 1
  min_size         = 0
  desired_capacity = 0

  health_check_type         = local.autoscaling_group_healh_check_type_ec2
  health_check_grace_period = 300

  force_delete = true

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

  update_default_version = true
}
resource "aws_security_group" "bastion" {
  name   = "bastion"
  vpc_id = module.deploy_network.vpc_id
}
resource "aws_iam_role" "bastion" {
  name               = "${local.project_name}-bastion"
  assume_role_policy = data.aws_iam_policy_document.allow_assume_by_instance.json
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
