resource "aws_imagebuilder_component" "hello" {
  name     = "${local.project_name}-hello"
  platform = local.imagebuilder_component_platform_linux
  version  = "1.0.0"
  data     = file("./components/hello/data.yaml")

  skip_destroy = true
}

resource "aws_imagebuilder_component" "mariadb_client" {
  name     = "${local.project_name}-mariadb-client"
  platform = local.imagebuilder_component_platform_linux
  version  = "1.0.1"
  data     = file("./components/mariadb-client/data.yaml")

  skip_destroy = true
}

resource "aws_imagebuilder_component" "squid" {
  name     = "${local.project_name}-squid"
  platform = local.imagebuilder_component_platform_linux
  version  = "1.0.0"
  data     = file("./components/squid/data.yaml")

  skip_destroy = true
}

resource "aws_s3_bucket" "configuration_resources" {
  bucket = "${local.project_name}-configuration-resources-${local.aws_account_id}"
}
resource "aws_s3_bucket_public_access_block" "configuration_resources" {
  bucket = aws_s3_bucket.configuration_resources.bucket

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

locals {
  cloudwatch_agent_bastion_config_basename = "amazon-cloudwatch-agent/bastion/config"
  cloudwatch_agent_proxy_config_basename   = "amazon-cloudwatch-agent/proxy/config"
}
resource "aws_s3_object" "cloudwatch_agent_bastion" {
  bucket = aws_s3_bucket.configuration_resources.bucket
  key    = "${local.cloudwatch_agent_bastion_config_basename}.json"

  content = jsonencode(yamldecode(file("${path.module}/configurations/${local.cloudwatch_agent_bastion_config_basename}.yaml")))
}
resource "aws_imagebuilder_component" "cloudwatch_agent_bastion" {
  name     = "${local.project_name}-cwagent-config-bastion"
  platform = local.imagebuilder_component_platform_linux
  version  = "1.0.0"
  data = templatefile(
    "./components/amazon-cloudwatch-agent-config/bastion/data.yaml.tpl",
    {
      aws_account_id     = local.aws_account_id
      resource_bucket    = aws_s3_bucket.configuration_resources.bucket
      cwagent_config_key = aws_s3_object.cloudwatch_agent_bastion.key
    }
  )

  skip_destroy = true
}

resource "aws_s3_object" "cloudwatch_agent_proxy" {
  bucket = aws_s3_bucket.configuration_resources.bucket
  key    = "${local.cloudwatch_agent_proxy_config_basename}.json"

  content = jsonencode(yamldecode(file("${path.module}/configurations/${local.cloudwatch_agent_proxy_config_basename}.yaml")))
}
resource "aws_imagebuilder_component" "cloudwatch_agent_proxy" {
  name     = "${local.project_name}-cwagent-config-proxy"
  platform = local.imagebuilder_component_platform_linux
  version  = "1.0.0"
  data = templatefile(
    "./components/amazon-cloudwatch-agent-config/proxy/data.yaml.tpl",
    {
      aws_account_id     = local.aws_account_id
      resource_bucket    = aws_s3_bucket.configuration_resources.bucket
      cwagent_config_key = aws_s3_object.cloudwatch_agent_proxy.key
    }
  )

  skip_destroy = true
}
