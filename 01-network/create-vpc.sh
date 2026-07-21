#!/usr/bin/env bash
set -euo pipefail

REGION="${1:-us-east-2}"
CLUSTER_NAME="${2:-eks-training}"
VPC_CIDR="${3:-10.50.0.0/16}"
SECONDARY_CIDR="${4:-100.64.0.0/16}"

OCTET="$(echo "$VPC_CIDR" | cut -d. -f2)"
VPC_NAME="${CLUSTER_NAME}-vpc"

echo "Creating VPC $VPC_NAME in $REGION"

VPC_ID="$(aws ec2 create-vpc --region "$REGION" --cidr-block "$VPC_CIDR" --query 'Vpc.VpcId' --output text)"
aws ec2 wait vpc-available --region "$REGION" --vpc-ids "$VPC_ID"

aws ec2 create-tags --region "$REGION" --resources "$VPC_ID" --tags \
  Key=Name,Value="$VPC_NAME" \
  Key=Project,Value=EKS-Training \
  Key=Cluster,Value="$CLUSTER_NAME"

aws ec2 modify-vpc-attribute --region "$REGION" --vpc-id "$VPC_ID" --enable-dns-support '{"Value":true}'
aws ec2 modify-vpc-attribute --region "$REGION" --vpc-id "$VPC_ID" --enable-dns-hostnames '{"Value":true}'

aws ec2 associate-vpc-cidr-block --region "$REGION" --vpc-id "$VPC_ID" --cidr-block "$SECONDARY_CIDR" >/dev/null

until [ "$(aws ec2 describe-vpcs --region "$REGION" --vpc-ids "$VPC_ID" --query "Vpcs[0].CidrBlockAssociationSet[?CidrBlock=='${SECONDARY_CIDR}'].CidrBlockState.State" --output text)" = "associated" ]; do
  sleep 5
done

mapfile -t AZS < <(aws ec2 describe-availability-zones --region "$REGION" --query "AvailabilityZones[?State=='available'].ZoneName" --output text | tr '\t' '\n' | head -3)

IGW_ID="$(aws ec2 create-internet-gateway --region "$REGION" --query 'InternetGateway.InternetGatewayId' --output text)"
aws ec2 attach-internet-gateway --region "$REGION" --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
aws ec2 create-tags --region "$REGION" --resources "$IGW_ID" --tags Key=Name,Value="${CLUSTER_NAME}-igw"

ROUTE_TABLE_ID="$(aws ec2 create-route-table --region "$REGION" --vpc-id "$VPC_ID" --query 'RouteTable.RouteTableId' --output text)"
aws ec2 create-route --region "$REGION" --route-table-id "$ROUTE_TABLE_ID" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" >/dev/null
aws ec2 create-tags --region "$REGION" --resources "$ROUTE_TABLE_ID" --tags Key=Name,Value="${CLUSTER_NAME}-public-rt"

PUBLIC_SUBNETS=()
POD_SUBNETS=()

for i in 0 1 2; do
  AZ="${AZS[$i]}"
  PUBLIC_CIDR="10.${OCTET}.$((i + 1)).0/24"
  POD_CIDR="100.64.$((i + 1)).0/24"

  PUBLIC_SUBNET_ID="$(aws ec2 create-subnet --region "$REGION" --vpc-id "$VPC_ID" --availability-zone "$AZ" --cidr-block "$PUBLIC_CIDR" --query 'Subnet.SubnetId' --output text)"
  aws ec2 modify-subnet-attribute --region "$REGION" --subnet-id "$PUBLIC_SUBNET_ID" --map-public-ip-on-launch
  aws ec2 associate-route-table --region "$REGION" --route-table-id "$ROUTE_TABLE_ID" --subnet-id "$PUBLIC_SUBNET_ID" >/dev/null
  aws ec2 create-tags --region "$REGION" --resources "$PUBLIC_SUBNET_ID" --tags \
    Key=Name,Value="${CLUSTER_NAME}-public-${AZ}" \
    Key=kubernetes.io/role/elb,Value=1 \
    Key=kubernetes.io/cluster/"$CLUSTER_NAME",Value=shared

  POD_SUBNET_ID="$(aws ec2 create-subnet --region "$REGION" --vpc-id "$VPC_ID" --availability-zone "$AZ" --cidr-block "$POD_CIDR" --query 'Subnet.SubnetId' --output text)"
  aws ec2 create-tags --region "$REGION" --resources "$POD_SUBNET_ID" --tags \
    Key=Name,Value="${CLUSTER_NAME}-pod-${AZ}" \
    Key=kubernetes.io/role/internal-elb,Value=1 \
    Key=kubernetes.io/cluster/"$CLUSTER_NAME",Value=shared

  PUBLIC_SUBNETS+=("$PUBLIC_SUBNET_ID")
  POD_SUBNETS+=("$POD_SUBNET_ID")
done

cat <<EOF
VPC_ID=$VPC_ID
REGION=$REGION
CLUSTER_NAME=$CLUSTER_NAME
PUBLIC_SUBNETS=${PUBLIC_SUBNETS[*]}
POD_SUBNETS=${POD_SUBNETS[*]}
ROUTE_TABLE_ID=$ROUTE_TABLE_ID
INTERNET_GATEWAY_ID=$IGW_ID
EOF
