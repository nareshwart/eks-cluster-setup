#!/bin/bash
set -euo pipefail
if [ $# -lt 2 ]; then echo "Usage: $0 <region> <vpc-cidr> [vpc-name]"; exit 1; fi
REGION=$1; VPC_CIDR=$2; VPC_NAME=${3:-eks-training-vpc}; SECONDARY_CIDR=100.64.0.0/16
OCTET=$(echo "$VPC_CIDR"|cut -d. -f2)
VPC_ID=$(aws ec2 create-vpc --region "$REGION" --cidr-block "$VPC_CIDR" --query Vpc.VpcId --output text)
aws ec2 wait vpc-available --region "$REGION" --vpc-ids "$VPC_ID"
aws ec2 create-tags --region "$REGION" --resources "$VPC_ID" --tags Key=Name,Value="$VPC_NAME"
aws ec2 modify-vpc-attribute --region "$REGION" --vpc-id "$VPC_ID" --enable-dns-support '{"Value":true}'
aws ec2 modify-vpc-attribute --region "$REGION" --vpc-id "$VPC_ID" --enable-dns-hostnames '{"Value":true}'
aws ec2 associate-vpc-cidr-block --region "$REGION" --vpc-id "$VPC_ID" --cidr-block "$SECONDARY_CIDR" >/dev/null
until [ "$(aws ec2 describe-vpcs --region "$REGION" --vpc-ids "$VPC_ID" --query "Vpcs[0].CidrBlockAssociationSet[?CidrBlock=='100.64.0.0/16'].CidrBlockState.State" --output text)" = associated ]; do sleep 5; done
mapfile -t AZS < <(aws ec2 describe-availability-zones --region "$REGION" --query "AvailabilityZones[?State=='available'].ZoneName" --output text|tr '	' '
'|head -3)
IGW=$(aws ec2 create-internet-gateway --region "$REGION" --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --region "$REGION" --internet-gateway-id "$IGW" --vpc-id "$VPC_ID"
RT=$(aws ec2 create-route-table --region "$REGION" --vpc-id "$VPC_ID" --query RouteTable.RouteTableId --output text)
aws ec2 create-route --region "$REGION" --route-table-id "$RT" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW" >/dev/null
for i in 0 1 2; do AZ=${AZS[$i]}; aws ec2 create-subnet --region "$REGION" --vpc-id "$VPC_ID" --availability-zone "$AZ" --cidr-block "10.$OCTET.$((i+1)).0/24" >/tmp/pub$i.json; PUB=$(jq -r .Subnet.SubnetId </tmp/pub$i.json); aws ec2 modify-subnet-attribute --region "$REGION" --subnet-id "$PUB" --map-public-ip-on-launch; aws ec2 associate-route-table --region "$REGION" --route-table-id "$RT" --subnet-id "$PUB" >/dev/null; aws ec2 create-subnet --region "$REGION" --vpc-id "$VPC_ID" --availability-zone "$AZ" --cidr-block "100.64.$((i+1)).0/24" >/dev/null; done
echo "VPC_ID=$VPC_ID"
