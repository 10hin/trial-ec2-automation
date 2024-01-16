name: amazon-cloudwatch-agent-config-proxy
description: 'Configure Amazon CloudWatch Agent for proxy'
schemaVersion: 1.0
phases:
  - name: build
    steps:
      - name: DownloadCWAgentConfig
        action: S3Download
        inputs:
          - source: 's3://${resource_bucket}/${cwagent_config_key}'
            destination: /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
            expectedBucketOwner: '${aws_account_id}'
      - name: EnableAndStartCWAgentService
        action: ExecuteBash
        inputs:
          commands:
            - systemctl enable amazon-cloudwatch-agent.service
            - /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
