#!/usr/bin/env bash
set -euo pipefail

REGION="${1:-us-east-2}"
CLUSTER_NAME="${2:-eks-training}"
VPC_CIDR="${3:-10.50.0.0/16}"
SECONDARY_CIDR="${4:-100.64.0.0/16}"
ENABLE_NAT_GATEWAY="${ENABLE_NAT_GATEWAY:-false}"

if [[ ! "$VPC_CIDR" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.0\.0/16$ ]]; then
  echo "VPC_CIDR must be a /16 in the form x.y.0.0/16. Received: $VPC_CIDR"
  exit 1
fi

if [[ ! "$SECONDARY_CIDR" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.0\.0/16$ ]]; then
  echo "SECONDARY_CIDR must be a /16 in the form x.y.0.0/16. Received: $SECONDARY_CIDR"
  exit 1
fi

VPC_CIDR_PREFIX="$(echo "$VPC_CIDR" | cut -d. -f1,2)"
SECONDARY_CIDR_PREFIX="$(echo "$SECONDARY_CIDR" | cut -d. -f1,2)"
VPC_NAME="${CLUSTER_NAME}-vpc"

common_tags=(
  Key=Project,Value=EKS-Training
  Key=Cluster,Value="$CLUSTER_NAME"
  Key=ManagedBy,Value=eks-platform-scripts
)

echo "Creating VPC $VPC_NAME in $REGION"

VPC_ID="$(aws ec2 create-vpc --region "$REGION" --cidr-block "$VPC_CIDR" --query 'Vpc.VpcId' --output text)"
aws ec2 wait vpc-available --region "$REGION" --vpc-ids "$VPC_ID"

aws ec2 create-tags --region "$REGION" --resources "$VPC_ID" --tags \
  Key=Name,Value="$VPC_NAME" \
  Key=kubernetes.io/cluster/"$CLUSTER_NAME",Value=shared \
  "${common_tags[@]}"

aws ec2 modify-vpc-attribute --region "$REGION" --vpc-id "$VPC_ID" --enable-dns-support '{"Value":true}'
aws ec2 modify-vpc-attribute --region "$REGION" --vpc-id "$VPC_ID" --enable-dns-hostnames '{"Value":true}'

aws ec2 associate-vpc-cidr-block --region "$REGION" --vpc-id "$VPC_ID" --cidr-block "$SECONDARY_CIDR" >/dev/null

until [ "$(aws ec2 describe-vpcs --region "$REGION" --vpc-ids "$VPC_ID" --query "Vpcs[0].CidrBlockAssociationSet[?CidrBlock=='${SECONDARY_CIDR}'].CidrBlockState.State" --output text)" = "associated" ]; do
  sleep 5
done

mapfile -t AZS < <(aws ec2 describe-availability-zones --region "$REGION" --query "AvailabilityZones[?State=='available'].ZoneName" --output text | tr '\t' '\n' | head -3)

if [ "${#AZS[@]}" -lt 3 ]; then
  echo "Expected at least 3 available Availability Zones in $REGION, found ${#AZS[@]}"
  exit 1
fi

IGW_ID="$(aws ec2 create-internet-gateway --region "$REGION" --query 'InternetGateway.InternetGatewayId' --output text)"
aws ec2 attach-internet-gateway --region "$REGION" --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
aws ec2 create-tags --region "$REGION" --resources "$IGW_ID" --tags \
  Key=Name,Value="${CLUSTER_NAME}-igw" \
  "${common_tags[@]}"

PUBLIC_ROUTE_TABLE_ID="$(aws ec2 create-route-table --region "$REGION" --vpc-id "$VPC_ID" --query 'RouteTable.RouteTableId' --output text)"
aws ec2 create-route --region "$REGION" --route-table-id "$PUBLIC_ROUTE_TABLE_ID" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" >/dev/null
aws ec2 create-tags --region "$REGION" --resources "$PUBLIC_ROUTE_TABLE_ID" --tags \
  Key=Name,Value="${CLUSTER_NAME}-public-rt" \
  "${common_tags[@]}"

POD_ROUTE_TABLE_ID="$(aws ec2 create-route-table --region "$REGION" --vpc-id "$VPC_ID" --query 'RouteTable.RouteTableId' --output text)"
aws ec2 create-tags --region "$REGION" --resources "$POD_ROUTE_TABLE_ID" --tags \
  Key=Name,Value="${CLUSTER_NAME}-pod-rt" \
  "${common_tags[@]}"

PUBLIC_SUBNETS=()
POD_SUBNETS=()
NAT_GATEWAY_ID=""
NAT_EIP_ALLOCATION_ID=""

for i in 0 1 2; do
  AZ="${AZS[$i]}"
  PUBLIC_CIDR="${VPC_CIDR_PREFIX}.$((i + 1)).0/24"
  POD_CIDR="${SECONDARY_CIDR_PREFIX}.$((i + 1)).0/24"

  PUBLIC_SUBNET_ID="$(aws ec2 create-subnet --region "$REGION" --vpc-id "$VPC_ID" --availability-zone "$AZ" --cidr-block "$PUBLIC_CIDR" --query 'Subnet.SubnetId' --output text)"
  aws ec2 modify-subnet-attribute --region "$REGION" --subnet-id "$PUBLIC_SUBNET_ID" --map-public-ip-on-launch
  aws ec2 associate-route-table --region "$REGION" --route-table-id "$PUBLIC_ROUTE_TABLE_ID" --subnet-id "$PUBLIC_SUBNET_ID" >/dev/null
  aws ec2 create-tags --region "$REGION" --resources "$PUBLIC_SUBNET_ID" --tags \
    Key=Name,Value="${CLUSTER_NAME}-public-${AZ}" \
    Key=Network,Value=public \
    Key=kubernetes.io/role/elb,Value=1 \
    Key=kubernetes.io/cluster/"$CLUSTER_NAME",Value=shared \
    "${common_tags[@]}"

  POD_SUBNET_ID="$(aws ec2 create-subnet --region "$REGION" --vpc-id "$VPC_ID" --availability-zone "$AZ" --cidr-block "$POD_CIDR" --query 'Subnet.SubnetId' --output text)"
  aws ec2 associate-route-table --region "$REGION" --route-table-id "$POD_ROUTE_TABLE_ID" --subnet-id "$POD_SUBNET_ID" >/dev/null
  aws ec2 create-tags --region "$REGION" --resources "$POD_SUBNET_ID" --tags \
    Key=Name,Value="${CLUSTER_NAME}-pod-${AZ}" \
    Key=Network,Value=pod \
    Key=kubernetes.io/role/internal-elb,Value=1 \
    Key=kubernetes.io/cluster/"$CLUSTER_NAME",Value=shared \
    "${common_tags[@]}"

  PUBLIC_SUBNETS+=("$PUBLIC_SUBNET_ID")
  POD_SUBNETS+=("$POD_SUBNET_ID")
done

if [ "$ENABLE_NAT_GATEWAY" = "true" ]; then
  echo "Creating NAT Gateway for pod subnet egress. This creates billable AWS resources."
  NAT_EIP_ALLOCATION_ID="$(aws ec2 allocate-address --region "$REGION" --domain vpc --query 'AllocationId' --output text)"
  aws ec2 create-tags --region "$REGION" --resources "$NAT_EIP_ALLOCATION_ID" --tags \
    Key=Name,Value="${CLUSTER_NAME}-nat-eip" \
    "${common_tags[@]}"

  NAT_GATEWAY_ID="$(aws ec2 create-nat-gateway --region "$REGION" --subnet-id "${PUBLIC_SUBNETS[0]}" --allocation-id "$NAT_EIP_ALLOCATION_ID" --query 'NatGateway.NatGatewayId' --output text)"
  aws ec2 create-tags --region "$REGION" --resources "$NAT_GATEWAY_ID" --tags \
    Key=Name,Value="${CLUSTER_NAME}-nat" \
    "${common_tags[@]}"

  aws ec2 wait nat-gateway-available --region "$REGION" --nat-gateway-ids "$NAT_GATEWAY_ID"
  aws ec2 create-route --region "$REGION" --route-table-id "$POD_ROUTE_TABLE_ID" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT_GATEWAY_ID" >/dev/null
fi

cat <<EOF
VPC_ID=$VPC_ID
REGION=$REGION
CLUSTER_NAME=$CLUSTER_NAME
PUBLIC_SUBNETS=${PUBLIC_SUBNETS[*]}
POD_SUBNETS=${POD_SUBNETS[*]}
PUBLIC_ROUTE_TABLE_ID=$PUBLIC_ROUTE_TABLE_ID
POD_ROUTE_TABLE_ID=$POD_ROUTE_TABLE_ID
INTERNET_GATEWAY_ID=$IGW_ID
NAT_GATEWAY_ID=$NAT_GATEWAY_ID
NAT_EIP_ALLOCATION_ID=$NAT_EIP_ALLOCATION_ID
EOF
