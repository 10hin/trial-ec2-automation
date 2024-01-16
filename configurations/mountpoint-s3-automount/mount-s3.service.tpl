[Unit]
Description=Mountpoint for Amazon S3 mount
Wants=network.target
AssertPathIsDirectory=/mnt/${bucket}

[Service]
Type=forking
User=ec2-user
Group=ec2-user
ExecStart=/usr/bin/mount-s3 ${bucket} /mnt/${bucket}
ExecStop=/usr/bin/fusermount -u /mnt/${bucket}

[Install]
WantedBy=remote-fs.target
