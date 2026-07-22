#!/bin/bash
# EKS Training Environment Builder
# Creates: VPC, IGW, Route Table, Public Subnets, Secondary CIDR,
# Pod Subnets, cluster.yaml, OIDC association script.
set -euo pipefail

if [ $# -lt 4 ]; then
cat <<EOF
Usage:
$0 <region> <cluster-name> <vpc-cidr> <k8s-version>

Example:
$0 us-east-2 student1 10.10.0.0/16 1.33
EOF
exit 1
fi

REGION=$1
CLUSTER=$2
VPC_CIDR=$3
K8S=$4
SECONDARY_CIDR=100.64.0.0/16
VPC_NAME=${CLUSTER}-vpc
OCTET=$(echo "$VPC_CIDR"|cut -d. -f2)

echo "Creating VPC..."
VPC_ID=$(aws ec2 create-vpc --region "$REGION" --cidr-block "$VPC_CIDR" --query Vpc.VpcId --output text)
aws ec2 wait vpc-available --region "$REGION" --vpc-ids "$VPC_ID"

aws ec2 create-tags --region "$REGION" --resources "$VPC_ID" \
 --tags Key=Name,Value=$VPC_NAME

aws ec2 modify-vpc-attribute --region "$REGION" --vpc-id "$VPC_ID" --enable-dns-support '{"Value":true}'
aws ec2 modify-vpc-attribute --region "$REGION" --vpc-id "$VPC_ID" --enable-dns-hostnames '{"Value":true}'

echo "Associating secondary CIDR..."
aws ec2 associate-vpc-cidr-block --region "$REGION" --vpc-id "$VPC_ID" --cidr-block $SECONDARY_CIDR >/dev/null

until [ "$(aws ec2 describe-vpcs --region "$REGION" --vpc-ids "$VPC_ID" --query "Vpcs[0].CidrBlockAssociationSet[?CidrBlock=='100.64.0.0/16'].CidrBlockState.State" --output text)" = "associated" ]; do
 sleep 5
done

mapfile -t AZS < <(aws ec2 describe-availability-zones --region "$REGION" --query "AvailabilityZones[?State=='available'].ZoneName" --output text|tr '\t' '\n'|head -3)

IGW=$(aws ec2 create-internet-gateway --region "$REGION" --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --region "$REGION" --internet-gateway-id "$IGW" --vpc-id "$VPC_ID"

RT=$(aws ec2 create-route-table --region "$REGION" --vpc-id "$VPC_ID" --query RouteTable.RouteTableId --output text)
aws ec2 create-route --region "$REGION" --route-table-id "$RT" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW" >/dev/null

PUB_IDS=()
POD_IDS=()

for i in 0 1 2; do
 AZ=${AZS[$i]}
 PUB_CIDR="10.${OCTET}.$((i+1)).0/24"
 POD_CIDR="100.64.$((i+1)).0/24"

 PUB=$(aws ec2 create-subnet --region "$REGION" --vpc-id "$VPC_ID" --availability-zone "$AZ" --cidr-block "$PUB_CIDR" --query Subnet.SubnetId --output text)
 aws ec2 modify-subnet-attribute --region "$REGION" --subnet-id "$PUB" --map-public-ip-on-launch
 aws ec2 associate-route-table --region "$REGION" --route-table-id "$RT" --subnet-id "$PUB" >/dev/null
 aws ec2 create-tags --region "$REGION" --resources "$PUB" --tags \
   Key=Name,Value=public-$AZ \
   Key=kubernetes.io/role/elb,Value=1 \
   Key=kubernetes.io/cluster/$CLUSTER,Value=shared

 POD=$(aws ec2 create-subnet --region "$REGION" --vpc-id "$VPC_ID" --availability-zone "$AZ" --cidr-block "$POD_CIDR" --query Subnet.SubnetId --output text)
 aws ec2 create-tags --region "$REGION" --resources "$POD" --tags \
   Key=Name,Value=pod-$AZ \
   Key=kubernetes.io/role/internal-elb,Value=1 \
   Key=kubernetes.io/cluster/$CLUSTER,Value=shared

 PUB_IDS+=("$PUB")
 POD_IDS+=("$POD")
done

cat > cluster.yaml <<EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: $CLUSTER
  region: $REGION
  version: "$K8S"

vpc:
  id: $VPC_ID
  subnets:
    public:
      ${AZS[0]}:
        id: ${PUB_IDS[0]}
      ${AZS[1]}:
        id: ${PUB_IDS[1]}
      ${AZS[2]}:
        id: ${PUB_IDS[2]}

managedNodeGroups:
- name: workers
  instanceType: t3.medium
  desiredCapacity: 2
  minSize: 2
  maxSize: 3

addons:
- name: vpc-cni
- name: coredns
- name: kube-proxy
- name: eks-pod-identity-agent
EOF

cat > post-create.sh <<EOF
#!/bin/bash
set -e
eksctl utils associate-iam-oidc-provider --cluster $CLUSTER --region $REGION --approve
echo "Next:"
echo "1. Create ENIConfig objects using pod subnets:"
echo "   ${POD_IDS[0]}"
echo "   ${POD_IDS[1]}"
echo "   ${POD_IDS[2]}"
EOF
chmod +x post-create.sh

cat <<EOF

==========================
Environment Ready
==========================
VPC: $VPC_ID
IGW: $IGW
RouteTable: $RT

Generated:
  cluster.yaml
  post-create.sh

Create cluster:
  eksctl create cluster -f cluster.yaml

After cluster creation:
  ./post-create.sh
==========================
EOF
