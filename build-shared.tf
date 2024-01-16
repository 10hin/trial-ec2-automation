resource "aws_imagebuilder_infrastructure_configuration" "shared" {
  name        = "${local.project_name}-shared"
  description = "AMIビルドパイプラインの標準的なインフラ設定"

  subnet_id = module.build_network.private_subnets[0]
  security_group_ids = [
    aws_security_group.build_shared_infra.id,
  ]

  instance_profile_name = aws_iam_instance_profile.build_shared.name
  instance_types = [
    local.ec2_instance_type_t2_nano,
    local.ec2_instance_type_t3_nano,
    local.ec2_instance_type_t3a_nano,
  ]
  terminate_instance_on_failure = true

  resource_tags = {
    Purpose = "EC2Automation"
  }
}
resource "aws_security_group" "build_shared_infra" {
  name   = "build-shared-infra"
  vpc_id = module.build_network.vpc_id
}
resource "aws_vpc_security_group_egress_rule" "build_shared_infra_allow_outbound" {
  security_group_id = aws_security_group.build_shared_infra.id
  ip_protocol       = local.ip_protocol_all
  cidr_ipv4         = "0.0.0.0/0"
}
resource "aws_iam_role" "build_shared" {
  name               = "${local.project_name}-build-shared"
  assume_role_policy = data.aws_iam_policy_document.allow_assume_by_instance.json
}
resource "aws_iam_role_policy_attachment" "build_shared_ssm" {
  role       = aws_iam_role.build_shared.name
  policy_arn = data.aws_iam_policy.AmazonSSMManagedInstanceCore.arn
}
resource "aws_iam_role_policy_attachment" "build_shared_imagebuilder" {
  role       = aws_iam_role.build_shared.name
  policy_arn = data.aws_iam_policy.EC2InstanceProfileForImageBuilder.arn
}
resource "aws_iam_role_policy" "build_shared_download_s3_resources" {
  role   = aws_iam_role.build_shared.name
  policy = data.aws_iam_policy_document.allow_access_configuration_resources_bucket.json
}
data "aws_iam_policy_document" "allow_access_configuration_resources_bucket" {
  statement {
    actions = [
      "s3:GetObject",
    ]
    resources = [
      "${aws_s3_bucket.configuration_resources.arn}/*",
    ]
  }
  statement {
    actions = [
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.configuration_resources.arn,
    ]
  }
}
resource "aws_iam_instance_profile" "build_shared" {
  name = aws_iam_role.build_shared.name
  role = aws_iam_role.build_shared.name
}

resource "aws_iam_role" "cicd" {
  name               = "${local.project_name}-cicd"
  assume_role_policy = data.aws_iam_policy_document.allow_assume_by_sfn.json
}
resource "aws_iam_role_policy" "allow_start_image_pipeline" {
  role   = aws_iam_role.cicd.name
  name   = "allow-start-image-pipeline"
  policy = data.aws_iam_policy_document.allow_start_image_pipeline.json
}
data "aws_iam_policy_document" "allow_start_image_pipeline" {
  statement {
    actions = [
      "imagebuilder:StartImagePipelineExecution",
    ]
    resources = sort([
      aws_imagebuilder_image_pipeline.bastion.arn,
      aws_imagebuilder_image_pipeline.proxy.arn,
    ])
  }
}
resource "aws_iam_role_policy" "allow_get_image" {
  role   = aws_iam_role.cicd.name
  name   = "allow-get-image"
  policy = data.aws_iam_policy_document.allow_get_image.json
}
data "aws_iam_policy_document" "allow_get_image" {
  statement {
    actions = [
      "imagebuilder:GetImage",
    ]
    resources = ["*"]
  }
}
resource "aws_iam_role_policy" "allow_invoke_send_notification_lambda" {
  role   = aws_iam_role.cicd.name
  name   = "allow-invoke-send-notification-lambda"
  policy = data.aws_iam_policy_document.allow_invoke_send_notification_lambda.json
}
data "aws_iam_policy_document" "allow_invoke_send_notification_lambda" {
  statement {
    actions = [
      "lambda:InvokeFunction",
    ]
    resources = sort([
      aws_lambda_function.user_notification_publish.arn,
    ])
  }
}
resource "aws_iam_role_policy" "allow_launch_template_update" {
  role   = aws_iam_role.cicd.name
  policy = data.aws_iam_policy_document.allow_launch_template_update.json
}
data "aws_iam_policy_document" "allow_launch_template_update" {
  statement {
    sid = "AllowSearchTemplateVersion"
    actions = [
      "ec2:DescribeLaunchTemplateVersions",
    ]
    resources = sort(["*"])
  }
  statement {
    sid = "AllowUpdateTemplteVersionDefault"
    actions = [
      "ec2:ModifyLaunchTemplate",
    ]
    resources = sort([
      aws_launch_template.bastion.arn,
      aws_launch_template.proxy.arn,
    ])
  }
}
resource "aws_iam_role_policy" "allow_refresh_instance" {
  role   = aws_iam_role.cicd.name
  policy = data.aws_iam_policy_document.allow_refresh_instance.json
}
data "aws_iam_policy_document" "allow_refresh_instance" {
  statement {
    actions = [
      "autoscaling:StartInstanceRefresh",
    ]
    resources = sort([
      aws_autoscaling_group.bastion.arn,
      aws_autoscaling_group.proxy.arn,
    ])
  }
}

data "archive_file" "user_notification_code" {
  type        = "zip"
  output_path = "${path.module}/functions/user-notification-publish.zip"
  source_file = "${path.module}/functions/user-notification-publish/handler.py"
}

resource "aws_lambda_function" "user_notification_publish" {
  function_name = "${local.project_name}-user-notification-publish"
  role          = aws_iam_role.user_notification_publish.arn

  runtime          = local.lambda_runtime_python_3_11
  filename         = data.archive_file.user_notification_code.output_path
  source_code_hash = data.archive_file.user_notification_code.output_base64sha256
  handler          = "handler.main"

  environment {
    variables = {
      SNS_TOPIC_TO_PUBLISH_ARN = aws_sns_topic.user_notification.arn
      CALLBACK_LAMBDA_URL      = aws_lambda_function_url.user_callback.function_url
    }
  }
}

resource "aws_iam_role" "user_notification_publish" {
  name               = "${local.project_name}-user-notification-publish"
  assume_role_policy = data.aws_iam_policy_document.allow_assume_by_lambda.json
}
resource "aws_iam_role_policy_attachment" "user_notification_publish_basic_permissin" {
  role       = aws_iam_role.user_notification_publish.name
  policy_arn = data.aws_iam_policy.AWSLambdaBasicExecutionRole.arn
}
data "aws_iam_policy_document" "allow_publish_to_user_notification" {
  statement {
    actions = [
      "sns:Publish",
    ]
    resources = sort([
      aws_sns_topic.user_notification.arn,
    ])
  }
}
resource "aws_iam_role_policy" "allow_send_message_from_sns" {
  role   = aws_iam_role.user_notification_publish.name
  policy = data.aws_iam_policy_document.allow_publish_to_user_notification.json
}

resource "aws_sns_topic" "user_notification" {
  name = "${local.project_name}-user-notification"
}
resource "aws_sns_topic_subscription" "user_notification_email_subscription" {
  topic_arn = aws_sns_topic.user_notification.arn
  protocol  = local.sns_subscription_protocol_email
  endpoint  = "10hin@outlook.com"
}

data "archive_file" "user_callback_code" {
  type        = "zip"
  output_path = "${path.module}/functions/user-callback.zip"
  source_file = "${path.module}/functions/user-callback/handler.py"
}

resource "aws_lambda_function" "user_callback" {
  function_name = "${local.project_name}-user-callback"
  role          = aws_iam_role.user_callback.arn

  runtime          = local.lambda_runtime_python_3_11
  filename         = data.archive_file.user_callback_code.output_path
  source_code_hash = data.archive_file.user_callback_code.output_base64sha256
  handler          = "handler.main"
}
resource "aws_iam_role" "user_callback" {
  name               = "${local.project_name}-user-callback"
  assume_role_policy = data.aws_iam_policy_document.allow_assume_by_lambda.json
}
resource "aws_iam_role_policy_attachment" "user_callback_basic_permission" {
  role       = aws_iam_role.user_callback.name
  policy_arn = data.aws_iam_policy.AWSLambdaBasicExecutionRole.arn
}
data "aws_iam_policy_document" "allow_report_task_status" {
  statement {
    actions = sort([
      "states:SendTaskSuccess",
      "states:SendTaskFailue",
      "states:SendTaskHeartbeat",
    ])
    resources = sort(["*"])
  }
}
resource "aws_iam_role_policy" "allow_report_task_status" {
  role   = aws_iam_role.user_callback.name
  policy = data.aws_iam_policy_document.allow_report_task_status.json
}
resource "aws_lambda_function_url" "user_callback" {
  function_name      = aws_lambda_function.user_callback.function_name
  authorization_type = local.lambda_function_url_authorization_type_none
}
resource "aws_lambda_permission" "user_callback" {
  action                 = "lambda:InvokeFunctionUrl"
  principal              = "*"
  function_name          = aws_lambda_function.user_callback.arn
  function_url_auth_type = local.lambda_function_url_authorization_type_none
}
