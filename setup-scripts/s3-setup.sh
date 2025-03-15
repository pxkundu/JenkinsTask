#!/bin/bash
# Create S3 bucket
aws s3 mb s3:// --region us-east-1

# Enable server-side encryption with KMS
aws s3api put-bucket-encryption --bucket  --server-side-encryption-configuration '{
  "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "aws:kms"}}]
}'

# Block public access
aws s3api put-public-access-block --bucket  --public-access-block-configuration '{
  "BlockPublicAcls": true, "IgnorePublicAcls": true, "BlockPublicPolicy": true, "RestrictPublicBuckets": true
}'

# Set bucket policy to allow JenkinsSlaveRole
aws s3api put-bucket-policy --bucket  --policy '{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"AWS": "arn:aws:iam::<account-id>:role/JenkinsSlaveRole"},
      "Action": ["s3:PutObject", "s3:GetObject"],
      "Resource": "arn:aws:s3:::/*"
    }
  ]
}'
