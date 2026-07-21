#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 <region> <vpc-id|vpc-name>"
  exit 1
fi

REGION="$1"
VPC_REF="$2"
MAX_WAIT_SECONDS="${MAX_WAIT_SECONDS:-900}"

if [[ "$VPC_REF" == vpc-* ]]; then
  VPC_ID="$VPC_REF"
else
  mapfile -t MATCHING_VPCS < <(aws ec2 describe-vpcs \
    --region "$REGION" \
    --filters Name=tag:Name,Values="$VPC_REF" \
    --query 'Vpcs[].VpcId' \
    --output text | tr '\t' '\n')

  if [ "${#MATCHING_VPCS[@]}" -eq 0 ]; then
    echo "No VPC found with Name tag: $VPC_REF"
    exit 1
  fi

  if [ "${#MATCHING_VPCS[@]}" -gt 1 ]; then
    echo "Multiple VPCs found with Name tag '$VPC_REF':"
    printf '  %s\n' "${MATCHING_VPCS[@]}"
    echo "Use the VPC ID to avoid deleting the wrong VPC."
    exit 1
  fi

  VPC_ID="${MATCHING_VPCS[0]}"
  echo "Resolved VPC name '$VPC_REF' to $VPC_ID"
fi

CLUSTER_TAG="$(aws ec2 describe-vpcs \
  --region "$REGION" \
  --vpc-ids "$VPC_ID" \
  --query "Vpcs[0].Tags[?Key=='Cluster'].Value | [0]" \
  --output text)"

if [ "$CLUSTER_TAG" = "None" ]; then
  CLUSTER_TAG=""
fi

report_dependencies() {
  echo
  echo "VPC deletion is still blocked. Remaining dependencies:"
  echo
  echo "Subnets:"
  aws ec2 describe-subnets --region "$REGION" --filters Name=vpc-id,Values="$VPC_ID" --query 'Subnets[].SubnetId' --output table || true
  echo
  echo "VPC CIDR associations:"
  aws ec2 describe-vpcs --region "$REGION" --vpc-ids "$VPC_ID" --query 'Vpcs[0].CidrBlockAssociationSet[].{Cidr:CidrBlock,Association:AssociationId,State:CidrBlockState.State,Primary:IsPrimary}' --output table || true
  echo
  echo "Internet gateways:"
  aws ec2 describe-internet-gateways --region "$REGION" --filters Name=attachment.vpc-id,Values="$VPC_ID" --query 'InternetGateways[].{Id:InternetGatewayId,State:Attachments[0].State}' --output table || true
  echo
  echo "Route tables:"
  aws ec2 describe-route-tables --region "$REGION" --filters Name=vpc-id,Values="$VPC_ID" --query 'RouteTables[].{Id:RouteTableId,Main:Associations[0].Main,Associations:length(Associations),Routes:length(Routes)}' --output table || true
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
  echo "Classic load balancers:"
  aws elb describe-load-balancers --region "$REGION" --query "LoadBalancerDescriptions[?VPCId=='${VPC_ID}'].{Name:LoadBalancerName,DNS:DNSName}" --output table || true
  echo
  echo "Non-default security groups:"
  aws ec2 describe-security-groups --region "$REGION" --filters Name=vpc-id,Values="$VPC_ID" --query 'SecurityGroups[?GroupName!=`default`].{Id:GroupId,Name:GroupName}' --output table || true
  echo
  echo "Non-default network ACLs:"
  aws ec2 describe-network-acls --region "$REGION" --filters Name=vpc-id,Values="$VPC_ID" --query 'NetworkAcls[?IsDefault==`false`].{Id:NetworkAclId}' --output table || true
  echo
  echo "VPC peering connections:"
  aws ec2 describe-vpc-peering-connections --region "$REGION" --filters Name=requester-vpc-info.vpc-id,Values="$VPC_ID" --query 'VpcPeeringConnections[].{Id:VpcPeeringConnectionId,Status:Status.Code}' --output table || true
  echo
  echo "Transit gateway attachments:"
  aws ec2 describe-transit-gateway-vpc-attachments --region "$REGION" --filters Name=vpc-id,Values="$VPC_ID" --query 'TransitGatewayVpcAttachments[].{Id:TransitGatewayAttachmentId,State:State}' --output table || true
  echo
  echo "VPN gateways:"
  aws ec2 describe-vpn-gateways --region "$REGION" --filters Name=attachment.vpc-id,Values="$VPC_ID" --query 'VpnGateways[].{Id:VpnGatewayId,State:State}' --output table || true
  echo
  echo "Tip: if this was used by EKS, delete the cluster and Kubernetes Services of type LoadBalancer first."
}

for NAT_GATEWAY_ID in $(aws ec2 describe-nat-gateways --region "$REGION" --filter Name=vpc-id,Values="$VPC_ID" --query 'NatGateways[?State!=`deleted`].NatGatewayId' --output text); do
  aws ec2 delete-nat-gateway --region "$REGION" --nat-gateway-id "$NAT_GATEWAY_ID" || true
done

while true; do
  NAT_GATEWAYS="$(aws ec2 describe-nat-gateways --region "$REGION" --filter Name=vpc-id,Values="$VPC_ID" --query 'NatGateways[?State!=`deleted`].NatGatewayId' --output text)"
  [ -z "$NAT_GATEWAYS" ] && break
  echo "Waiting for NAT Gateway deletion: $NAT_GATEWAYS"
  sleep 15
done

if [ -n "$CLUSTER_TAG" ]; then
  for ALLOCATION_ID in $(aws ec2 describe-addresses --region "$REGION" --filters Name=domain,Values=vpc Name=tag:Cluster,Values="$CLUSTER_TAG" --query 'Addresses[].AllocationId' --output text); do
    aws ec2 release-address --region "$REGION" --allocation-id "$ALLOCATION_ID" || true
  done
fi

for SUBNET_ID in $(aws ec2 describe-subnets --region "$REGION" --filters Name=vpc-id,Values="$VPC_ID" --query 'Subnets[].SubnetId' --output text); do
  aws ec2 delete-subnet --region "$REGION" --subnet-id "$SUBNET_ID" || true
done

MAIN_ROUTE_TABLE_ID="$(aws ec2 describe-route-tables --region "$REGION" --filters Name=vpc-id,Values="$VPC_ID" --query 'RouteTables[?Associations[?Main==`true`]].RouteTableId | [0]' --output text)"

for ROUTE_TABLE_ID in $(aws ec2 describe-route-tables --region "$REGION" --filters Name=vpc-id,Values="$VPC_ID" --query 'RouteTables[].RouteTableId' --output text); do
  [ "$ROUTE_TABLE_ID" = "$MAIN_ROUTE_TABLE_ID" ] && continue
  for ASSOCIATION_ID in $(aws ec2 describe-route-tables --region "$REGION" --route-table-ids "$ROUTE_TABLE_ID" --query 'RouteTables[0].Associations[?Main==`false`].RouteTableAssociationId' --output text); do
    aws ec2 disassociate-route-table --region "$REGION" --association-id "$ASSOCIATION_ID" || true
  done
  aws ec2 delete-route-table --region "$REGION" --route-table-id "$ROUTE_TABLE_ID" || true
done

for IGW_ID in $(aws ec2 describe-internet-gateways --region "$REGION" --filters Name=attachment.vpc-id,Values="$VPC_ID" --query 'InternetGateways[].InternetGatewayId' --output text); do
  aws ec2 detach-internet-gateway --region "$REGION" --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" || true
  aws ec2 delete-internet-gateway --region "$REGION" --internet-gateway-id "$IGW_ID" || true
done

PRIMARY_CIDR="$(aws ec2 describe-vpcs --region "$REGION" --vpc-ids "$VPC_ID" --query 'Vpcs[0].CidrBlock' --output text)"

for ASSOCIATION_ID in $(aws ec2 describe-vpcs --region "$REGION" --vpc-ids "$VPC_ID" --query "Vpcs[0].CidrBlockAssociationSet[?CidrBlock!='${PRIMARY_CIDR}'].AssociationId" --output text); do
  aws ec2 disassociate-vpc-cidr-block --region "$REGION" --association-id "$ASSOCIATION_ID" || true
done

WAIT_STARTED_AT="$(date +%s)"

while true; do
  SECONDARY_CIDRS="$(aws ec2 describe-vpcs --region "$REGION" --vpc-ids "$VPC_ID" --query "Vpcs[0].CidrBlockAssociationSet[?CidrBlock!='${PRIMARY_CIDR}' && CidrBlockState.State!='disassociated'].CidrBlock" --output text)"
  [ -z "$SECONDARY_CIDRS" ] && break
  NOW="$(date +%s)"
  ELAPSED="$((NOW - WAIT_STARTED_AT))"
  if [ "$ELAPSED" -ge "$MAX_WAIT_SECONDS" ]; then
    echo "Timed out after ${MAX_WAIT_SECONDS}s waiting for secondary CIDR disassociation: $SECONDARY_CIDRS"
    echo "AWS does not support force-deleting a VPC while secondary CIDRs are still disassociating."
    echo "Rerun this script later, or open an AWS Support case if the CIDR remains stuck for more than 30-60 minutes."
    report_dependencies
    exit 1
  fi
  echo "Waiting for secondary CIDR disassociation: $SECONDARY_CIDRS"
  sleep 10
done

if ! aws ec2 delete-vpc --region "$REGION" --vpc-id "$VPC_ID"; then
  report_dependencies
  exit 1
fi

echo "Deleted VPC $VPC_ID"
