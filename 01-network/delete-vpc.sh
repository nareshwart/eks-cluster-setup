#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 <region> <vpc-id>"
  exit 1
fi

REGION="$1"
VPC_ID="$2"

for SUBNET_ID in $(aws ec2 describe-subnets --region "$REGION" --filters Name=vpc-id,Values="$VPC_ID" --query 'Subnets[].SubnetId' --output text); do
  aws ec2 delete-subnet --region "$REGION" --subnet-id "$SUBNET_ID"
done

for ROUTE_TABLE_ID in $(aws ec2 describe-route-tables --region "$REGION" --filters Name=vpc-id,Values="$VPC_ID" --query 'RouteTables[?Associations[?Main==`false`]].RouteTableId' --output text); do
  for ASSOCIATION_ID in $(aws ec2 describe-route-tables --region "$REGION" --route-table-ids "$ROUTE_TABLE_ID" --query 'RouteTables[0].Associations[?Main==`false`].RouteTableAssociationId' --output text); do
    aws ec2 disassociate-route-table --region "$REGION" --association-id "$ASSOCIATION_ID" || true
  done
  aws ec2 delete-route-table --region "$REGION" --route-table-id "$ROUTE_TABLE_ID" || true
done

for IGW_ID in $(aws ec2 describe-internet-gateways --region "$REGION" --filters Name=attachment.vpc-id,Values="$VPC_ID" --query 'InternetGateways[].InternetGatewayId' --output text); do
  aws ec2 detach-internet-gateway --region "$REGION" --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" || true
  aws ec2 delete-internet-gateway --region "$REGION" --internet-gateway-id "$IGW_ID" || true
done

for ASSOCIATION_ID in $(aws ec2 describe-vpcs --region "$REGION" --vpc-ids "$VPC_ID" --query 'Vpcs[0].CidrBlockAssociationSet[?IsPrimary==`false`].AssociationId' --output text); do
  aws ec2 disassociate-vpc-cidr-block --region "$REGION" --association-id "$ASSOCIATION_ID" || true
done

aws ec2 delete-vpc --region "$REGION" --vpc-id "$VPC_ID"
echo "Deleted VPC $VPC_ID"
