#!/bin/bash
set -euo pipefail

REGION="${1:-us-east-2}"
VPC_NAME="${2:-eks-training-vpc}"

echo "Using region: $REGION"

# Find an unused 10.x.0.0/16
while true; do
  OCTET=$((RANDOM % 200 + 20))
  VPC_CIDR="10.${OCTET}.0.0/16"
  EXISTING=$(aws ec2 describe-vpcs \
    --region "$REGION" \
    --query "Vpcs[?CidrBlock=='${VPC_CIDR}'].VpcId" \
    --output text)
  [ -z "$EXISTING" ] && break
done

echo "Selected VPC CIDR: $VPC_CIDR"

VPC_ID=$(aws ec2 create-vpc \
  --region "$REGION" \
  --cidr-block "$VPC_CIDR" \
  --query 'Vpc.VpcId' \
  --output text)

aws ec2 create-tags --region "$REGION" \
  --resources "$VPC_ID" \
  --tags Key=Name,Value="$VPC_NAME"

aws ec2 modify-vpc-attribute --region "$REGION" --vpc-id "$VPC_ID" --enable-dns-support '{"Value":true}'
aws ec2 modify-vpc-attribute --region "$REGION" --vpc-id "$VPC_ID" --enable-dns-hostnames '{"Value":true}'

echo "Associating secondary CIDR 100.64.0.0/16..."
aws ec2 associate-vpc-cidr-block \
  --region "$REGION" \
  --vpc-id "$VPC_ID" \
  --cidr-block 100.64.0.0/16 >/dev/null

echo "Waiting for secondary CIDR..."
while true; do
  STATE=$(aws ec2 describe-vpcs --region "$REGION" --vpc-ids "$VPC_ID" \
    --query "Vpcs[0].CidrBlockAssociationSet[?CidrBlock=='100.64.0.0/16'].CidrBlockState.State" \
    --output text)
  [ "$STATE" = "associated" ] && break
  sleep 5
done

mapfile -t AZS < <(aws ec2 describe-availability-zones \
  --region "$REGION" \
  --query "AvailabilityZones[?State=='available'].ZoneName" \
  --output text | tr '\t' '\n' | head -3)

IGW=$(aws ec2 create-internet-gateway --region "$REGION" \
  --query InternetGateway.InternetGatewayId --output text)

aws ec2 attach-internet-gateway --region "$REGION" \
  --internet-gateway-id "$IGW" --vpc-id "$VPC_ID"

RTB=$(aws ec2 create-route-table --region "$REGION" \
  --vpc-id "$VPC_ID" \
  --query RouteTable.RouteTableId --output text)

aws ec2 create-route --region "$REGION" \
  --route-table-id "$RTB" \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id "$IGW" >/dev/null

echo
echo "Creating subnets..."

PUB_SUBNETS=()
POD_SUBNETS=()

for i in 0 1 2; do
  az=${AZS[$i]}
  pub="10.${OCTET}.$((i+1)).0/24"
  pod="100.64.$((i+1)).0/24"

  PUB=$(aws ec2 create-subnet \
      --region "$REGION" \
      --vpc-id "$VPC_ID" \
      --availability-zone "$az" \
      --cidr-block "$pub" \
      --query Subnet.SubnetId \
      --output text)

  aws ec2 modify-subnet-attribute \
      --region "$REGION" \
      --subnet-id "$PUB" \
      --map-public-ip-on-launch

  aws ec2 associate-route-table \
      --region "$REGION" \
      --route-table-id "$RTB" \
      --subnet-id "$PUB" >/dev/null

  aws ec2 create-tags --region "$REGION" \
      --resources "$PUB" \
      --tags Key=Name,Value=public-$az

  POD=$(aws ec2 create-subnet \
      --region "$REGION" \
      --vpc-id "$VPC_ID" \
      --availability-zone "$az" \
      --cidr-block "$pod" \
      --query Subnet.SubnetId \
      --output text)

  aws ec2 create-tags --region "$REGION" \
      --resources "$POD" \
      --tags Key=Name,Value=pod-$az

  PUB_SUBNETS+=("$PUB")
  POD_SUBNETS+=("$POD")
done

cat <<EOF

=========================================
VPC CREATED
=========================================
VPC ID            : $VPC_ID
Primary CIDR      : $VPC_CIDR
Secondary CIDR    : 100.64.0.0/16
Internet Gateway  : $IGW
Route Table       : $RTB

Public Subnets
${PUB_SUBNETS[0]}
${PUB_SUBNETS[1]}
${PUB_SUBNETS[2]}

Pod Subnets
${POD_SUBNETS[0]}
${POD_SUBNETS[1]}
${POD_SUBNETS[2]}

Next:
1. Tag subnets for EKS if required.
2. Create your EKS cluster using these subnet IDs.
EOF
