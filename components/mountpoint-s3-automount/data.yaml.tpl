name: mountpoint-s3-automount
description: 'Configure s3 auto-mount at boot time'
schemaVersion: 1.0
phases:
  - name: build
    steps:
      - name: DownloadAutomountServiceUnitFile
        action: S3Download
        inputs:
          - source: 's3://${resource_bucket}/${service_unit_file_key}'
            destination: /etc/systemd/system/mount-s3.service
            expectedBucketOwner: '${aws_account_id}'
      - name: EnableAutomountService
        action: ExecuteBash
        inputs:
          commands:
            # including debug commands
            - ( echo; echo 'user_allow_other' ) | tee -a /etc/fuse.conf
            - mkdir -p /mnt/${mount_bucket}
            - systemctl status mount-s3.service
            - journalctl -n 25 -u mount-s3.service
            - systemctl daemon-reload
            - systemctl status mount-s3.service
            - journalctl -n 25 -u mount-s3.service
            - systemctl enable mount-s3.service
            - systemctl status mount-s3.service
            - journalctl -n 25 -u mount-s3.service
            - systemctl start mount-s3.service
            - systemctl status mount-s3.service
            - journalctl -n 25 -u mount-s3.service
