# High-Performance Scaling with Karpenter

This guide walks you through deploying **Karpenter v1.x**, a modern, high-performance Kubernetes node provisioning engine designed for AWS. Unlike the legacy Cluster Autoscaler (which works by scaling EC2 Auto Scaling Groups), Karpenter communicates directly with the EC2 API to launch correctly sized instances in under 30 seconds.

> **Note**: This lab targets **Karpenter v1.14.1** (latest stable). Karpenter v1.0 promoted the API version from `v1beta1` to the stable `v1`. If you have older YAML files using `karpenter.sh/v1beta1`, update them to `karpenter.sh/v1`.

---

## Overview

```
Step 1 → Tag Node Subnets & Security Groups for Discovery
Step 2 → Create IAM Roles, Register Node Role with EKS, and ServiceAccount (IRSA)
Step 3 → Install Karpenter via Helm (v1.14.1)
Step 4 → Configure NodePool & EC2NodeClass CRDs (v1 API)
Step 5 → Test Fast Scale-Up
Step 6 → Test Consolidation (Cost Optimization)
Step 7 → Advanced Scaling: Spot Instances with Taints and Tolerations
```

---

## Step 1 — Tag Subnets and Security Groups for Discovery

Karpenter dynamically discovers which subnets and security groups to use for new nodes by scanning AWS resources for specific discovery tags.

First, set your cluster name and region as variables — you'll reuse these throughout the lab:
```bash
CLUSTER_NAME=<your-cluster-name>   # e.g. eks-nareshwar-cluster
REGION=us-east-2
```

> **Important — Node Subnets vs Pod Subnets**: If your EKS cluster uses **custom networking** (separate pod CIDRs / secondary VPC CIDRs), you have two types of subnets:
>
> | Subnet Type | Purpose | Has NAT Gateway? | Use for Karpenter? |
> |---|---|---|---|
> | **Node subnets** | EC2 instance ENI (primary NIC) | ✅ Yes | ✅ **Yes** |
> | **Pod subnets** | VPC CNI secondary IP allocation | ❌ No | ❌ **No** |
>
> Karpenter **must tag node subnets only**. Tagging pod subnets causes new nodes to launch in subnets without internet access — the node bootstrap agent (`nodeadm`) will fail with repeated `EC2/DescribeInstances` retry loops and the node will never join the cluster.

### 1a. Identify and tag the correct Node Subnets

List all subnets and identify your **node subnets** (typically named `*node*`, `*private*`, or `*worker*` — **not** `*pods*` or `*secondary*`):
```bash
aws ec2 describe-subnets \
  --query "Subnets[*].{ID:SubnetId,Name:Tags[?Key=='Name']|[0].Value,CIDR:CidrBlock}" \
  --output table \
  --region $REGION
```

Before tagging, **verify the node subnet has a NAT gateway route** (required for EC2 API access during bootstrap):
```bash
# Replace <subnet-id> with one of your node subnet IDs from above
SUBNET_ID=<subnet-id>
RT_ID=$(aws ec2 describe-route-tables \
  --filters "Name=association.subnet-id,Values=$SUBNET_ID" \
  --query "RouteTables[*].RouteTableId" --output text --region $REGION)

# Look for a route with NatGatewayId (nat-xxx) or GatewayId (igw-xxx)
aws ec2 describe-route-tables --route-table-ids $RT_ID \
  --query "RouteTables[*].Routes[*].{Dest:DestinationCidrBlock,Gateway:GatewayId,NAT:NatGatewayId}" \
  --output table --region $REGION
```

If the output shows a `nat-xxx` or `igw-xxx` entry for `0.0.0.0/0` — this is the correct subnet. Now tag your node subnets:
```bash
# Replace *node* with your actual node subnet name pattern
aws ec2 create-tags \
  --resources $(aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=*node*" \
    --query "Subnets[*].SubnetId" --output text) \
  --tags Key=karpenter.sh/discovery,Value=$CLUSTER_NAME \
  --region $REGION
```

### 1b. Discover and tag the EKS Cluster Security Group

First, retrieve and confirm the cluster's primary security group ID:
```bash
# Get the cluster security group ID
CLUSTER_SG=$(aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" \
  --output text \
  --region $REGION)

echo "Cluster Security Group ID: $CLUSTER_SG"
```

Apply the discovery tag:
```bash
aws ec2 create-tags \
  --resources $CLUSTER_SG \
  --tags Key=karpenter.sh/discovery,Value=$CLUSTER_NAME \
  --region $REGION
```

### 1c. Verify both tags are applied

> **Important**: If either of these commands returns an empty table, Karpenter's `EC2NodeClass` will fail with `SubnetsNotFound` or `SecurityGroupsNotFound`. Do not proceed to Step 2 until both return results.

```bash
# Verify subnet tags
echo "--- Tagged Subnets ---"
aws ec2 describe-subnets \
  --filters "Name=tag:karpenter.sh/discovery,Values=$CLUSTER_NAME" \
  --query "Subnets[*].{ID:SubnetId,Name:Tags[?Key=='Name']|[0].Value}" \
  --output table --region $REGION

# Verify security group tags
echo "--- Tagged Security Groups ---"
aws ec2 describe-security-groups \
  --filters "Name=tag:karpenter.sh/discovery,Values=$CLUSTER_NAME" \
  --query "SecurityGroups[*].{ID:GroupId,Name:GroupName}" \
  --output table --region $REGION
```

---

## Step 2 — Create IAM Roles and Service Account (IRSA)

Karpenter requires two IAM roles:
1.  **Karpenter Node Role**: Attached to the EC2 instances launched by Karpenter.
2.  **Karpenter Controller Role**: Attached to the Karpenter pod to authorize it to call EC2 APIs.

### 2a. Create the Karpenter Node IAM Role
Create a node role named `KarpenterNodeRole-student1` and attach the required EKS/EC2 managed policies:

```bash
# 1. Create the base IAM Role with EC2 trust policy
aws iam create-role --role-name KarpenterNodeRole-student1 --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}'

# 2. Attach EKS node policies
aws iam attach-role-policy --role-name KarpenterNodeRole-student1 --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
aws iam attach-role-policy --role-name KarpenterNodeRole-student1 --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
aws iam attach-role-policy --role-name KarpenterNodeRole-student1 --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
aws iam attach-role-policy --role-name KarpenterNodeRole-student1 --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
```

### 2b. Register the Karpenter Node Role with EKS (Mandatory)

> **This step is mandatory.** Without it, Karpenter will successfully launch EC2 instances, but those nodes will never be able to authenticate to the Kubernetes API server and will never appear in `kubectl get nodes`.

First, check which authentication mode your cluster uses:
```bash
aws eks describe-cluster \
  --name $CLUSTER_NAME \
  --query "cluster.accessConfig.authenticationMode" \
  --output text --region $REGION
```

#### If the output is `API` or `API_AND_CONFIG_MAP` — use EKS Access Entries:
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws eks create-access-entry \
  --cluster-name $CLUSTER_NAME \
  --principal-arn arn:aws:iam::${ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME} \
  --type EC2_LINUX \
  --region $REGION
```

Verify it was created:
```bash
aws eks list-access-entries \
  --cluster-name $CLUSTER_NAME \
  --region $REGION \
  --query "accessEntries" --output table
```

#### If the output is `CONFIG_MAP` — use aws-auth ConfigMap:
```bash
# View current aws-auth to confirm the role is not already there
kubectl describe configmap aws-auth -n kube-system
```

Add the Karpenter Node Role under `mapRoles`:
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

kubectl edit configmap aws-auth -n kube-system
```

Add this block under `mapRoles:` (keep existing entries, just append):
```yaml
    - rolearn: arn:aws:iam::<ACCOUNT_ID>:role/KarpenterNodeRole-<your-cluster-name>
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
```

### 2c. Create the Karpenter Controller IAM ServiceAccount (IRSA)

Choose **one** of the following options to bind EKS permissions to the Karpenter controller.

#### Option A: Create Automatically via `eksctl`
This is the fastest method. `eksctl` will create the IAM role, set up the OIDC trust relationship, and deploy the annotated Kubernetes ServiceAccount in a single step:

```bash
# Create the karpenter namespace
kubectl create namespace karpenter

# Create the service account and role with EKSCTL
eksctl create iamserviceaccount \
  --cluster=student1 \
  --namespace=karpenter \
  --name=karpenter \
  --role-name=KarpenterControllerRole-student1 \
  --attach-policy-arn=arn:aws:iam::aws:policy/AmazonEC2FullAccess \
  --override-existing-serviceaccounts \
  --approve

# Attach EKS Cluster Describe inline policy for cluster discovery
aws iam put-role-policy \
  --role-name KarpenterControllerRole-student1 \
  --policy-name KarpenterEKSClusterDiscovery \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["eks:DescribeCluster"],"Resource":"*"}]}'

# Attach IAM, PassRole, Pricing & SSM inline policy for node launch config
aws iam put-role-policy \
  --role-name KarpenterControllerRole-student1 \
  --policy-name KarpenterIAMOperations \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["iam:GetInstanceProfile","iam:CreateInstanceProfile","iam:AddRoleToInstanceProfile","iam:RemoveRoleFromInstanceProfile","iam:DeleteInstanceProfile","iam:TagInstanceProfile","iam:ListInstanceProfiles","iam:PassRole","pricing:GetProducts","ssm:GetParameter"],"Resource":"*"}]}'
```

---

#### Option B: Manual IAM Creation & YAML Manifest (Standard Kubernetes Method)
Use this option to manually set up OIDC identity federation and deploy the ServiceAccount using a standard Kubernetes YAML manifest.

1.  **Retrieve EKS OIDC Provider and AWS Account Details**:
    ```bash
    OIDC_PROVIDER=$(aws eks describe-cluster --name student1 --query "cluster.identity.oidc.issuer" --output text | sed -e "s/https:\/\///")
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    ```

2.  **Create the Trust Relationship JSON file**:
    ```bash
    cat <<EOF > trust-policy.json
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": {
            "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
          },
          "Action": "sts:AssumeRoleWithWebIdentity",
          "Condition": {
            "StringEquals": {
              "${OIDC_PROVIDER}:sub": "system:serviceaccount:karpenter:karpenter",
              "${OIDC_PROVIDER}:aud": "sts.amazonaws.com"
            }
          }
        }
      ]
    }
    EOF
    ```

3.  **Create the IAM Role & Attach Policy**:
    ```bash
    # Create the IAM role using the trust policy
    aws iam create-role \
      --role-name KarpenterControllerRole-student1 \
      --assume-role-policy-document file://trust-policy.json

    # Attach the EC2 full access policy to the role
    aws iam attach-role-policy \
      --role-name KarpenterControllerRole-student1 \
      --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess

    # Attach EKS Cluster Describe inline policy for cluster discovery
    aws iam put-role-policy \
      --role-name KarpenterControllerRole-student1 \
      --policy-name KarpenterEKSClusterDiscovery \
      --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["eks:DescribeCluster"],"Resource":"*"}]}'

    # Attach IAM, PassRole, Pricing & SSM inline policy for node launch config
    aws iam put-role-policy \
      --role-name KarpenterControllerRole-student1 \
      --policy-name KarpenterIAMOperations \
      --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["iam:GetInstanceProfile","iam:CreateInstanceProfile","iam:AddRoleToInstanceProfile","iam:RemoveRoleFromInstanceProfile","iam:DeleteInstanceProfile","iam:TagInstanceProfile","iam:ListInstanceProfiles","iam:PassRole","pricing:GetProducts","ssm:GetParameter"],"Resource":"*"}]}'
    ```

4.  **Create the Namespace**:
    ```bash
    kubectl create namespace karpenter
    ```

5.  **Create the ServiceAccount YAML file (`karpenter-sa.yaml`)**:
    Create a file named `karpenter-sa.yaml` with the following content (replace `ACCOUNT_ID` with your actual AWS Account ID):
    ```yaml
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: karpenter
      namespace: karpenter
      annotations:
        eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/KarpenterControllerRole-student1
    ```

6.  **Apply the manifest**:
    ```bash
    kubectl apply -f karpenter-sa.yaml
    ```

> **Note**: In a production environment, you should use a scoped custom IAM Policy instead of `AmazonEC2FullAccess` for better security (least privilege).

---

## Step 3 — Install Karpenter via Helm (v1.14.1)

1.  Log in to the public Amazon ECR registry to retrieve the Helm chart:
    ```bash
    aws ecr-public get-login-password --region us-east-1 | helm registry login --username AWS --password-stdin public.ecr.aws
    ```

2.  Install the Karpenter Helm chart (v1.14.1 — latest stable):
    ```bash
    helm install karpenter oci://public.ecr.aws/karpenter/karpenter \
      --namespace karpenter \
      --version 1.14.1 \
      --set serviceAccount.create=false \
      --set serviceAccount.name=karpenter \
      --set settings.clusterName=student1 \
      --set replicas=1 \
      --wait
    ```

3.  Verify Karpenter is running:
    ```bash
    kubectl get pods -n karpenter
    kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=20
    ```

    **Expected Output:**
    ```
    NAME                         READY   STATUS    RESTARTS   AGE
    karpenter-7d9f8c7bcd-x8kjp   1/1     Running   0          45s
    ```

---

## Step 4 — Configure NodePool & EC2NodeClass CRDs (v1 API)

Karpenter v1 uses stable `v1` API versions (replacing the older `v1beta1`). The two key resources are:
*   **`EC2NodeClass`** (`karpenter.k8s.aws/v1`): Defines AWS-specific node configuration — subnets, security groups, AMI alias, and storage.
*   **`NodePool`** (`karpenter.sh/v1`): Defines scheduling constraints, instance types, CPU/memory limits, and consolidation policy.

Apply the following manifest to define the default provisioning rules.

> **Important**: The `karpenter.sh/discovery` tag value in `subnetSelectorTerms` and `securityGroupSelectorTerms` **must exactly match** the `$CLUSTER_NAME` value you used when tagging in Step 1. Similarly, the `role` field must reference the Karpenter Node IAM Role name that includes your cluster name.

```bash
cat <<EOF | kubectl apply -f -
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  # Uses the latest EKS-optimized Amazon Linux 2023 AMI for your cluster version
  amiSelectorTerms:
    - alias: al2023@latest
  # Replace with your actual Karpenter Node Role name
  role: KarpenterNodeRole-<your-cluster-name>
  subnetSelectorTerms:
    - tags:
        # Must match the tag value used in Step 1
        karpenter.sh/discovery: <your-cluster-name>
  securityGroupSelectorTerms:
    - tags:
        # Must match the tag value used in Step 1
        karpenter.sh/discovery: <your-cluster-name>
---
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
        - key: karpenter.k8s.aws/instance-family
          operator: In
          values: ["t3", "t3a", "c6i"]
        - key: karpenter.k8s.aws/instance-size
          operator: In
          values: ["small", "medium", "large"]
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
  limits:
    cpu: 100
  disruption:
    # WhenEmptyOrUnderutilized replaces the old v1beta1 "WhenUnderutilized"
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 30s
EOF
```

Verify the CRDs were created:
```bash
kubectl get ec2nodeclass
kubectl get nodepool
```

**Expected Output:**
```
NAME      READY   AGE
default   True    15s

NAME      NODECLASSREF   NODES   READY   AGE
default   default        0       True    15s
```

---

## Step 5 — Test Fast Scale-Up

Let's verify Karpenter's rapid scaling by deploying a workload that exceeds the cluster's current node capacity.

### 5a. Open a live log watcher (use a second terminal window)
```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f
```

### 5b. Open a live node watcher (use a third terminal window)
```bash
kubectl get nodes -w
```

### 5c. Deploy a resource-hungry test workload
In your main terminal, deploy a CPU-constrained deployment that will immediately trigger new node provisioning:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: karpenter-scale-test
  namespace: default
spec:
  replicas: 20
  selector:
    matchLabels:
      app: scale-test
  template:
    metadata:
      labels:
        app: scale-test
    spec:
      containers:
      - name: app
        image: nginx:alpine
        resources:
          requests:
            cpu: "500m"
            memory: "256Mi"
          limits:
            cpu: "500m"
            memory: "256Mi"
EOF
```

### 5d. Observe what happens

**In the Karpenter log window**, look for output like:
```
found 15 provisionable pod(s)
computed new nodeclaim(s) to fit pod(s) ...
created nodeclaim: default ...
launched nodeclaim, creating instance ...
registered nodeclaim, launched instance i-0abc123def456 ...
initialized nodeclaim, node is Ready
```

**In the nodes window**, a new node will join the cluster in approximately **20–30 seconds**:
```
NAME                         STATUS   ROLES    AGE   VERSION
ip-10-50-1-100.ec2.internal  Ready    <none>   5m    v1.30.x
ip-10-50-2-45.ec2.internal   Ready    <none>   28s   v1.30.x   # <-- New Karpenter node!
```

### 5e. Check pod scheduling
```bash
kubectl get pods -l app=scale-test -o wide
```
Watch all 20 pods schedule across both the original nodes and the new Karpenter-provisioned node.

---

## Step 6 — Test Consolidation (Cost Optimization)

One of Karpenter's key advantages is **consolidation** — automatically defragmenting workloads and terminating idle/underutilized nodes to save costs. The `consolidateAfter: 30s` setting we configured means Karpenter starts consolidating 30 seconds after a node becomes consolidatable.

### 6a. Delete the test deployment
```bash
kubectl delete deployment karpenter-scale-test
```

### 6b. Watch the Karpenter consolidation in action

**In the Karpenter log window**, within ~30 seconds you will see:
```
disrupting node via consolidation delete, ... terminating node ip-10-50-2-45...
```

**In the nodes window**:
```
ip-10-50-2-45.ec2.internal   Ready    <none>   2m    v1.30.x
ip-10-50-2-45.ec2.internal   NotReady <none>   2m    v1.30.x   # draining...
# Node disappears from the list...
```

### 6c. Verify cluster returned to baseline
```bash
kubectl get nodes
```
Only your original managed node group nodes should remain.

---

## Step 7 — Advanced Scaling: Spot Instances with Taints and Tolerations

Karpenter makes it easy to scale workloads on Spot instances (up to 90% cheaper than On-Demand) using a dedicated NodePool with taints.

### 7a. Deploy a Spot NodePool

```bash
cat <<EOF | kubectl apply -f -
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: spot
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
        - key: karpenter.k8s.aws/instance-family
          operator: In
          values: ["t3", "t3a", "c6i", "m6i"]
        - key: karpenter.k8s.aws/instance-size
          operator: In
          values: ["small", "medium", "large"]
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      taints:
        - key: spot-only
          value: "true"
          effect: NoSchedule
  limits:
    cpu: 100
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 30s
EOF
```

### 7b. Deploy a Test Workload with Tolerations

Deploy an application that tolerates the `spot-only` taint. Karpenter will spin up a new Spot instance specifically for this deployment:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: karpenter-spot-test
spec:
  replicas: 5
  selector:
    matchLabels:
      app: spot-test
  template:
    metadata:
      labels:
        app: spot-test
    spec:
      containers:
      - name: web
        image: nginx:alpine
        resources:
          requests:
            cpu: "250m"
            memory: "256Mi"
      tolerations:
      - key: "spot-only"
        operator: "Equal"
        value: "true"
        effect: "NoSchedule"
EOF
```

### 7c. Verify Spot Instance Launch

1. Observe the controller logs:
   ```bash
   kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f
   ```
   You should see Karpenter selecting a spot instance (e.g. `t3.medium` or `c6i.large`) and spinning it up.

2. Check the new node's labels:
   ```bash
   kubectl get nodes -l karpenter.sh/capacity-type=spot -o wide
   ```

3. Clean up the Spot test deployment:
   ```bash
   kubectl delete deployment karpenter-spot-test
   ```
   *Within 30 seconds, Karpenter will automatically terminate the Spot instance because the workload is gone.*

---

## Troubleshooting & Common Issues

### 1. Karpenter Controller Pod Fails to Start (CrashLoopBackOff)
* **Symptom**: Pod logs show access denied errors or fail to authenticate with AWS.
* **Causes**:
  * **IRSA Role Mismatch**: The IAM Role `KarpenterControllerRole-student1` trust policy must contain the correct OIDC provider ID and service account namespace/name (`karpenter/karpenter`).
  * **Missing ServiceAccount Annotation**: Verify the `karpenter` ServiceAccount has the correct annotation:
    ```bash
    kubectl get serviceaccount karpenter -n karpenter -o yaml
    ```
    Ensure it matches `eks.amazonaws.com/role-arn: arn:aws:iam::<ACCOUNT_ID>:role/KarpenterControllerRole-student1`.

### 2. Pods Remain Pending and Karpenter Does Not Scale Up
* **Symptom**: Pods are `Pending` with scheduling failure events, but no EC2 instances are provisioned.
* **Causes**:
  * **Missing Subnet/Security Group Tags**: Karpenter discovers subnets and security groups using tags. Verify that you ran the `aws ec2 create-tags` commands in Step 1.
    Run these commands to verify the tags exist:
    ```bash
    aws ec2 describe-subnets --filters "Name=tag:karpenter.sh/discovery,Values=student1" --query "Subnets[*].SubnetId" --region us-east-2
    aws ec2 describe-security-groups --filters "Name=tag:karpenter.sh/discovery,Values=student1" --query "SecurityGroups[*].GroupId" --region us-east-2
    ```
  * **Incorrect nodeClassRef**: In Karpenter v1, the `nodeClassRef` requires all three fields — `group`, `kind`, and `name`. If you only specify `name:`, it will not resolve.
    ```yaml
    # Correct v1 format:
    nodeClassRef:
      group: karpenter.k8s.aws
      kind: EC2NodeClass
      name: default
    ```
  * **Resource Request Limits**: Check the Karpenter logs. If you see `limits exceeded`, the node launch would violate the `limits.cpu` or `limits.memory` configured on the NodePool.

### 3. Controller Logs Show `UnauthorizedOperation` or `AccessDenied`
* **Symptom**: Logs show `UnauthorizedOperation: You are not authorized to perform this operation.` when calling `ec2:RunInstances` or `ec2:DescribeAvailabilityZones`.
* **Causes**:
  * **IAM Policy Permissions**: The `KarpenterControllerRole-student1` requires EC2 permissions. If you didn't use Option A (`eksctl` with `AmazonEC2FullAccess` policy), verify that the manual IAM role has the `AmazonEC2FullAccess` policy (or equivalent scoped policy) attached.
  * **Instance Profile Missing**: Ensure the instance profile configured in Karpenter's Helm values/settings matches the Karpenter Node Role.

### 4. CRD Version Error (v1beta1 not found)
* **Symptom**: `error: no matches for kind "NodePool" in version "karpenter.sh/v1beta1"`.
* **Cause**: You are using old `v1beta1` API YAML files. Karpenter v1.0+ dropped `v1beta1` support.
* **Fix**: Update your manifests to use `karpenter.sh/v1` and `karpenter.k8s.aws/v1`. Also update the `nodeClassRef` to include the `group` and `kind` fields as shown in Step 4 above.

### 5. NodeClaim Fails with `no amis exist given constraints`
* **Symptom**: Karpenter controller logs show `launching nodeclaim, creating instance, getting launch template configs, getting launch templates, no amis exist given constraints`.
* **Fix**: Use the `alias` field in `amiSelectorTerms` to let Karpenter automatically resolve the correct EKS-optimized AMI for your cluster version:
    ```yaml
    amiSelectorTerms:
      - alias: al2023@latest
    ```

### 6. Node Launches But Never Joins the Cluster (`nodeadm` retries `EC2/DescribeInstances`)
* **Symptom**: EC2 instances appear in the AWS Console with Karpenter tags (`karpenter.sh/nodepool=default`), but `kubectl get nodes` never shows them. The node console output shows repeated log lines like:
  ```
  nodeadm[1950]: SDK retrying request EC2/DescribeInstances, attempt 7
  nodeadm[1950]: SDK retrying request EC2/DescribeInstances, attempt 8
  ```
* **Cause**: Karpenter launched the EC2 instance into a **pod subnet** (secondary CIDR) instead of a **node subnet**. Pod subnets in EKS custom networking setups have no NAT gateway route, so the node cannot reach the EC2 or EKS API endpoints needed to bootstrap itself.
* **Fix**:
  1. Remove the `karpenter.sh/discovery` tag from the pod subnets:
      ```bash
      POD_SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=tag:karpenter.sh/discovery,Values=$CLUSTER_NAME" \
        --query "Subnets[*].SubnetId" --output text --region $REGION)
      aws ec2 delete-tags \
        --resources $POD_SUBNET_IDS \
        --tags Key=karpenter.sh/discovery \
        --region $REGION
      ```
  2. Tag the **node subnets** instead (subnets whose route table has a `0.0.0.0/0 -> nat-xxx` or `igw-xxx` route). See Step 1a for how to identify and verify node subnets.
  3. Terminate the stuck EC2 instances and let Karpenter re-provision on the correct subnets.

---

## Clean Up Everything

To prevent incurring AWS charges and restore your cluster and AWS account to their baseline states, run the following cleanup steps in order:

### 1. Delete Karpenter Custom Resources
Deleting the NodePool and EC2NodeClass first is **critical**. This triggers Karpenter to gracefully drain and terminate all EC2 instances it launched before the controller itself is uninstalled.

```bash
# Delete all NodePools
kubectl delete nodepool --all

# Delete all EC2NodeClasses
kubectl delete ec2nodeclass --all

# Wait for Karpenter-managed instances to terminate
kubectl get nodes -w
```

### 2. Uninstall Karpenter Helm Chart
Once all Karpenter-managed nodes have terminated, uninstall the Karpenter controller:

```bash
helm uninstall karpenter --namespace karpenter
```

### 3. Delete Karpenter Controller IAM ServiceAccount and Role
* **If you used Option A (eksctl)**:
  ```bash
  # Delete the IAM ServiceAccount
  eksctl delete iamserviceaccount \
    --cluster=student1 \
    --namespace=karpenter \
    --name=karpenter

  # Delete the namespace
  kubectl delete namespace karpenter
  ```

* **If you used Option B (Manual)**:
  ```bash
  # Delete the ServiceAccount and namespace
  kubectl delete namespace karpenter

  # Delete inline policies, detach managed policies, and delete the Controller IAM Role
  aws iam delete-role-policy --role-name KarpenterControllerRole-student1 --policy-name KarpenterEKSClusterDiscovery
  aws iam delete-role-policy --role-name KarpenterControllerRole-student1 --policy-name KarpenterIAMOperations
  aws iam detach-role-policy --role-name KarpenterControllerRole-student1 --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess
  aws iam delete-role --role-name KarpenterControllerRole-student1
  ```

### 4. Delete the Karpenter Node IAM Role
Remove the policy attachments and delete the node IAM role:

```bash
aws iam detach-role-policy --role-name KarpenterNodeRole-student1 --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
aws iam detach-role-policy --role-name KarpenterNodeRole-student1 --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
aws iam detach-role-policy --role-name KarpenterNodeRole-student1 --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
aws iam detach-role-policy --role-name KarpenterNodeRole-student1 --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

aws iam delete-role --role-name KarpenterNodeRole-student1
```

### 5. Remove AWS Discovery Tags
Remove the discovery tags from your subnets and EKS cluster primary security group to clean up your AWS metadata:

```bash
# Remove tags from Subnets
aws ec2 delete-tags \
  --resources $(aws ec2 describe-subnets --filters "Name=tag:Name,Values=*pods*" --query "Subnets[*].SubnetId" --output text) \
  --tags Key=karpenter.sh/discovery \
  --region us-east-2

# Remove tags from Primary Security Group
aws ec2 delete-tags \
  --resources $(aws eks describe-cluster --name student1 --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text) \
  --tags Key=karpenter.sh/discovery \
  --region us-east-2
```
