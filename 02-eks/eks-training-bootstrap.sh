#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 4 ]; then
  cat <<EOF
Usage: $0 <region> <cluster-name> <vpc-id> <kubernetes-version>

Example:
  $0 us-east-2 student1 vpc-xxxxxxxx 1.33
EOF
  exit 1
fi

REGION="$1"
CLUSTER_NAME="$2"
VPC_ID="$3"
K8S_VERSION="$4"
OUTPUT_FILE="${5:-02-eks/cluster.generated.yaml}"

mapfile -t PUBLIC_SUBNET_ROWS < <(aws ec2 describe-subnets \
  --region "$REGION" \
  --filters Name=vpc-id,Values="$VPC_ID" Name=tag:kubernetes.io/role/elb,Values=1 \
  --query 'sort_by(Subnets,&AvailabilityZone)[].[AvailabilityZone,SubnetId]' \
  --output text)

if [ "${#PUBLIC_SUBNET_ROWS[@]}" -lt 3 ]; then
  echo "Expected at least 3 public EKS subnets tagged kubernetes.io/role/elb=1 in $VPC_ID"
  exit 1
fi

AZS=()
PUBLIC_SUBNETS=()
for ROW in "${PUBLIC_SUBNET_ROWS[@]}"; do
  AZS+=("$(echo "$ROW" | awk '{print $1}')")
  PUBLIC_SUBNETS+=("$(echo "$ROW" | awk '{print $2}')")
done

sed \
  -e "s/CLUSTER_NAME/${CLUSTER_NAME}/g" \
  -e "s/us-east-2/${REGION}/g" \
  -e "s/1.33/${K8S_VERSION}/g" \
  -e "s/VPC_ID/${VPC_ID}/g" \
  -e "s/AZ_1/${AZS[0]}/g" \
  -e "s/AZ_2/${AZS[1]}/g" \
  -e "s/AZ_3/${AZS[2]}/g" \
  -e "s/PUBLIC_SUBNET_1/${PUBLIC_SUBNETS[0]}/g" \
  -e "s/PUBLIC_SUBNET_2/${PUBLIC_SUBNETS[1]}/g" \
  -e "s/PUBLIC_SUBNET_3/${PUBLIC_SUBNETS[2]}/g" \
  02-eks/cluster.yaml > "$OUTPUT_FILE"

cat <<EOF
Generated $OUTPUT_FILE

Create the cluster:
  eksctl create cluster -f $OUTPUT_FILE

After creation:
  ./02-eks/post-create.sh $CLUSTER_NAME $REGION
EOF
