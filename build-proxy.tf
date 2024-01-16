resource "aws_imagebuilder_image_pipeline" "proxy" {
  name                             = "${local.project_name}-proxy"
  image_recipe_arn                 = aws_imagebuilder_image_recipe.proxy.arn
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.proxy.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.shared.arn
}

resource "aws_imagebuilder_image_recipe" "proxy" {
  name         = "${local.project_name}-proxy"
  version      = "1.1.0"
  parent_image = "arn:aws:imagebuilder:${local.region}:aws:image/amazon-linux-2-x86/x.x.x"
  block_device_mapping {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 8
      volume_type           = local.volume_type_gp3
      throughput            = 125
      iops                  = 3000
      delete_on_termination = true
    }
  }

  component {
    component_arn = replace(aws_imagebuilder_component.hello.arn, "/\\/[0-9]+\\.[0-9]+\\.[0-9]+$/", "/x.x.x")
  }
  component {
    component_arn = "arn:aws:imagebuilder:ap-northeast-1:aws:component/amazon-cloudwatch-agent-linux/x.x.x"
  }
  component {
    component_arn = replace(aws_imagebuilder_component.cloudwatch_agent_proxy.arn, "/\\/[0-9]+\\.[0-9]+\\.[0-9]+$/", "/x.x.x")
  }
  component {
    component_arn = replace(aws_imagebuilder_component.squid.arn, "/\\/[0-9]+\\.[0-9]+\\.[0-9]+$/", "/x.x.x")
  }

  systems_manager_agent {
    uninstall_after_build = false
  }
}


resource "aws_imagebuilder_distribution_configuration" "proxy" {
  name = "${local.project_name}-proxy"

  distribution {
    region = local.region
    ami_distribution_configuration {
      name = "${local.project_name}-proxy-{{ imagebuilder:buildDate }}"
      ami_tags = {
        Purpose = "EC2Automation"
      }
      launch_permission {
        user_ids = [local.aws_account_id]
      }
    }
    launch_template_configuration {
      account_id         = local.aws_account_id
      launch_template_id = aws_launch_template.proxy.id
      default            = false
    }
  }
}

resource "aws_sfn_state_machine" "proxy_cicd" {
  name     = "${local.project_name}-cicd-proxy"
  role_arn = aws_iam_role.cicd.arn
  definition = jsonencode(
    {
      "Comment" : "ステートマシンの説明",
      "StartAt" : "StartImagePipelineExecution",
      "States" : {
        "StartImagePipelineExecution" : {
          "Type" : "Task",
          "Next" : "GetImage",
          "Parameters" : {
            "ClientToken.$" : "$$.Execution.Name",
            "ImagePipelineArn" : aws_imagebuilder_image_pipeline.proxy.arn
          },
          "Resource" : "arn:aws:states:::aws-sdk:imagebuilder:startImagePipelineExecution"
        },
        "Wait 1 min" : {
          "Type" : "Wait",
          "Seconds" : 60,
          "Next" : "GetImage"
        },
        "GetImage" : {
          "Type" : "Task",
          "Parameters" : {
            "ImageBuildVersionArn.$" : "$.ImageBuildVersionArn"
          },
          "ResultPath" : "$.getImageResult",
          "Resource" : "arn:aws:states:::aws-sdk:imagebuilder:getImage",
          "Next" : "Confirm AMI Build state"
        },
        "Confirm AMI Build state" : {
          "Type" : "Choice",
          "Choices" : [
            {
              "Variable" : "$.getImageResult.Image.State.Status",
              "StringMatches" : "AVAILABLE",
              "Next" : "SNS Publish succeed"
            },
            {
              "Variable" : "$.getImageResult.Image.State.Status",
              "StringMatches" : "FAILED",
              # "Next" : "SNS Publish failure"
              "Next" : "Fail"
            }
          ],
          "Default" : "Wait 1 min"
        },
        "SNS Publish succeed" : {
          "Type" : "Task",
          "Resource" : "arn:aws:states:::lambda:invoke.waitForTaskToken",
          "OutputPath" : "$.Payload",
          "Parameters" : {
            "FunctionName" : aws_lambda_function.user_notification_publish.function_name,
            "Payload" : {
              "Input.$" : "$",
              "ExecutionContext.$" : "$$"
            }
          },
          "HeartbeatSeconds" : (1 * 60 * 60),
          "Retry" : [
            {
              "ErrorEquals" : [
                "Lambda.ServiceException",
                "Lambda.AWSLambdaException",
                "Lambda.SdkClientException",
                "Lambda.TooManyRequestsException"
              ],
              "IntervalSeconds" : 1,
              "MaxAttempts" : 3,
              "BackoffRate" : 2
            }
          ],
          "Next" : "ManualApproval"
        },
        "ManualApproval" : {
          "Type" : "Choice",
          "Choices" : [
            {
              "Variable" : "$.decision",
              "StringEquals" : "approve",
              "Next" : "DescribeLaunchTemplateVersions"
            },
            {
              "Variable" : "$.decision",
              "StringEquals" : "reject"
              "Next" : "Success"
            },
          ],
          "Default" : "Fail"
        },
        "DescribeLaunchTemplateVersions" : {
          "Type" : "Task",
          "Parameters" : {
            "LaunchTemplateId" : aws_launch_template.proxy.id,
            "Filters" : [
              {
                "Name" : "image-id",
                "Values.$" : "$.imageID"
              }
            ]
          },
          "ResultPath" : "$.describeLaunchTemplateVersionsResult"
          "Resource" : "arn:aws:states:::aws-sdk:ec2:describeLaunchTemplateVersions",
          "Next" : "ModifyLaunchTemplate"
        }
        "ModifyLaunchTemplate" : {
          "Type" : "Task",
          "Parameters" : {
            "LaunchTemplateId" : aws_launch_template.proxy.id,
            # API Referenceでは`SetDefaultVersion`というパラメータだが`DefaultVersion`でないと受け付けられない(引数チェックで拒否される)
            # `VersionNumber`フィールドは数値を持ち、`DefaultVersion`フィールドは文字列でないと受け付けないので`States.Format`関数を通して文字列に変換する
            "DefaultVersion.$" : "States.Format('{}', $.describeLaunchTemplateVersionsResult.LaunchTemplateVersions[0].VersionNumber)"
          },
          "Resource" : "arn:aws:states:::aws-sdk:ec2:modifyLaunchTemplate",
          "Next" : "StartInstanceRefresh"
        },
        "StartInstanceRefresh" : {
          "Type" : "Task",
          "Parameters" : {
            "AutoScalingGroupName" : aws_autoscaling_group.proxy.name
          },
          "Resource" : "arn:aws:states:::aws-sdk:autoscaling:startInstanceRefresh",
          "Next" : "Success"
        },
        /*
        "SNS Publish failure": {
          "Type": "Task",
          "Resource": "arn:aws:states:::sns:publish",
          "Parameters": {
            "TopicArn": aws_sns_topic.user_notification.arn,
            "Message.$": "$"
          },
          "Next": "Fail"
        },
        */
        "Success" : {
          "Type" : "Succeed"
        },
        "Fail" : {
          "Type" : "Fail"
        }
      },
      "TimeoutSeconds" : 3600
    }
  )
}
