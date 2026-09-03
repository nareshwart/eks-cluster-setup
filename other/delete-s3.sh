#!/bin/bash

TARGET_REGION="us-east-2"

for bucket in $(aws s3api list-buckets --query "Buckets[].Name" --output text); do
    # Get bucket region (us-east-1 returns "None")
    region=$(aws s3api get-bucket-location --bucket "$bucket" --output text)
    if [[ "$region" == "None" ]]; then region="us-east-1"; fi

    if [[ "$region" == "$TARGET_REGION" ]]; then
        echo "Deleting bucket: $bucket in region: $region"
        # Force-deletes the bucket by emptying all non-versioned objects first
        aws s3 rb "s3://$bucket" --force
    fi
done
