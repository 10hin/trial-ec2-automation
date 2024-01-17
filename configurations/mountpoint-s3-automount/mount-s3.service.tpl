[Unit]
Description=Mountpoint for Amazon S3 mount
Wants=network.target
AssertPathIsDirectory=/mnt/${bucket}

[Service]
Type=forking
User=root
Group=root
ExecStart=/usr/bin/mount-s3 --expected-bucket-owner ${aws_account_id} --allow-delete --allow-other --file-mode 666 --dir-mode 777 ${bucket} /mnt/${bucket}
ExecStop=/usr/bin/fusermount -u /mnt/${bucket}
Restart=on-failure
RestartSec=1s

[Install]
WantedBy=remote-fs.target
