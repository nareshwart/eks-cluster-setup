#!/bin/bash
set -euo pipefail
if [ $# -ne 2 ]; then echo "Usage: $0 <region> <vpc-id>"; exit 1; fi
REGION=$1; VPC_ID=$2
for S in $(aws ec2 describe-subnets --region "$REGION" --filters Name=vpc-id,Values=$VPC_ID --query "Subnets[].SubnetId" --output text); do aws ec2 delete-subnet --region "$REGION" --subnet-id "$S"; done
for RT in $(aws ec2 describe-route-tables --region "$REGION" --filters Name=vpc-id,Values=$VPC_ID --query "RouteTables[?Associations[?Main==\`false\`]].RouteTableId" --output text); do for A in $(aws ec2 describe-route-tables --region "$REGION" --route-table-ids "$RT" --query "RouteTables[0].Associations[].RouteTableAssociationId" --output text); do aws ec2 disassociate-route-table --region "$REGION" --association-id "$A"||true; done; aws ec2 delete-route-table --region "$REGION" --route-table-id "$RT"||true; done
for I in $(aws ec2 describe-internet-gateways --region "$REGION" --filters Name=attachment.vpc-id,Values=$VPC_ID --query "InternetGateways[].InternetGatewayId" --output text); do aws ec2 detach-internet-gateway --region "$REGION" --internet-gateway-id "$I" --vpc-id "$VPC_ID"; aws ec2 delete-internet-gateway --region "$REGION" --internet-gateway-id "$I"; done
ASSOC=$(aws ec2 describe-vpcs --region "$REGION" --vpc-ids "$VPC_ID" --query "Vpcs[0].CidrBlockAssociationSet[?CidrBlock=='100.64.0.0/16'].AssociationId" --output text)
[ "$ASSOC" != "None" ] && aws ec2 disassociate-vpc-cidr-block --region "$REGION" --association-id "$ASSOC"||true
aws ec2 delete-vpc --region "$REGION" --vpc-id "$VPC_ID"
