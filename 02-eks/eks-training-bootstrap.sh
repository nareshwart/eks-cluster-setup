#!/usr/bin/env bash
set -euo pipefail

REGION="us-east-2"

if [ $# -lt 3 ]; then
  cat <<EOF
Usage: $0 <cluster-name> <vpc-id|vpc-name> <kubernetes-version>

Example:
  $0 student1 student1-vpc 1.33
  $0 student1 vpc-xxxxxxxx 1.33

Region is hard-coded to: $REGION
EOF
  exit 1
fi

CLUSTER_NAME="$1"
VPC_REF="$2"
K8S_VERSION="$3"
OUTPUT_FILE="${4:-02-eks/cluster.generated.yaml}"

if [[ "$VPC_REF" == vpc-* ]]; then
  VPC_ID="$VPC_REF"
else
  mapfile -t MATCHING_VPCS < <(aws ec2 describe-vpcs \
    --region "$REGION" \
    --filters Name=tag:Name,Values="$VPC_REF" \
    --query 'Vpcs[].VpcId' \
    --output text | tr '\t' '\n')

  if [ "${#MATCHING_VPCS[@]}" -eq 0 ]; then
    echo "No VPC found in $REGION with Name tag: $VPC_REF"
    exit 1
  fi

  if [ "${#MATCHING_VPCS[@]}" -gt 1 ]; then
    echo "Multiple VPCs found in $REGION with Name tag '$VPC_REF':"
    printf '  %s\n' "${MATCHING_VPCS[@]}"
    echo "Use the VPC ID to avoid selecting the wrong VPC."
    exit 1
  fi

  VPC_ID="${MATCHING_VPCS[0]}"
  echo "Resolved VPC name '$VPC_REF' to $VPC_ID"
fi

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

Review the generated YAML before creating the cluster:
  less $OUTPUT_FILE

After review, create the cluster manually:
  eksctl create cluster -f $OUTPUT_FILE

After creation:
  ./02-eks/post-create.sh $CLUSTER_NAME $REGION
EOF
