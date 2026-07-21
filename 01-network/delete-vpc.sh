#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 <region> <vpc-id>"
  exit 1
fi

REGION="$1"
VPC_ID="$2"

report_dependencies() {
  echo
  echo "VPC deletion is still blocked. Remaining dependencies:"
  echo
  echo "Subnets:"
  aws ec2 describe-subnets --region "$REGION" --filters Name=vpc-id,Values="$VPC_ID" --query 'Subnets[].SubnetId' --output table || true
  echo
  echo "Network interfaces:"
  aws ec2 describe-network-interfaces --region "$REGION" --filters Name=vpc-id,Values="$VPC_ID" --query 'NetworkInterfaces[].{Id:NetworkInterfaceId,Status:Status,Description:Description,Attachment:Attachment.InstanceId}' --output table || true
  echo
  echo "NAT gateways:"
  aws ec2 describe-nat-gateways --region "$REGION" --filter Name=vpc-id,Values="$VPC_ID" --query 'NatGateways[?State!=`deleted`].{Id:NatGatewayId,State:State,Subnet:SubnetId}' --output table || true
  echo
  echo "VPC endpoints:"
  aws ec2 describe-vpc-endpoints --region "$REGION" --filters Name=vpc-id,Values="$VPC_ID" --query 'VpcEndpoints[].{Id:VpcEndpointId,State:State,Service:ServiceName}' --output table || true
  echo
  echo "Load balancers:"
  aws elbv2 describe-load-balancers --region "$REGION" --query "LoadBalancers[?VpcId=='${VPC_ID}'].{Name:LoadBalancerName,Arn:LoadBalancerArn,State:State.Code}" --output table || true
  echo
  echo "Non-default security groups:"
  aws ec2 describe-security-groups --region "$REGION" --filters Name=vpc-id,Values="$VPC_ID" --query 'SecurityGroups[?GroupName!=`default`].{Id:GroupId,Name:GroupName}' --output table || true
  echo
  echo "Non-default network ACLs:"
  aws ec2 describe-network-acls --region "$REGION" --filters Name=vpc-id,Values="$VPC_ID" --query 'NetworkAcls[?IsDefault==`false`].{Id:NetworkAclId}' --output table || true
  echo
  echo "Tip: if this was used by EKS, delete the cluster and Kubernetes Services of type LoadBalancer first."
}

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

while true; do
  SECONDARY_CIDRS="$(aws ec2 describe-vpcs --region "$REGION" --vpc-ids "$VPC_ID" --query 'Vpcs[0].CidrBlockAssociationSet[?IsPrimary==`false`].CidrBlock' --output text)"
  [ -z "$SECONDARY_CIDRS" ] && break
  echo "Waiting for secondary CIDR disassociation: $SECONDARY_CIDRS"
  sleep 10
done

if ! aws ec2 delete-vpc --region "$REGION" --vpc-id "$VPC_ID"; then
  report_dependencies
  exit 1
fi

echo "Deleted VPC $VPC_ID"
