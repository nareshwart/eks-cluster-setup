# High-Performance Scaling with Karpenter

This guide walks you through deploying **Karpenter**, a modern, high-performance Kubernetes node provisioning engine designed for AWS. Unlike the legacy Cluster Autoscaler (which works by scaling EC2 Auto Scaling Groups), Karpenter communicates directly with the EC2 API to launch correctly sized instances in under 30 seconds.

---

## Overview

```
Step 1 → Tag Subnets & Security Groups for Discovery
Step 2 → Create IAM Roles and ServiceAccount (IRSA)
Step 3 → Install Karpenter via Helm
Step 4 → Configure NodePool & EC2NodeClass CRDs
Step 5 → Test Fast Scale-Up
Step 6 → Test Consolidation (Cost Optimization)
```

---

## Step 1 — Tag Subnets and Security Groups for Discovery

Karpenter dynamically discovers which subnets and security groups to use for new nodes by scanning AWS resources for specific discovery tags.

Run the following commands to tag your cluster's resources (replace `student1` with your cluster name and `us-east-2` with your region):

### 1a. Discover Subnets and tag them:
```bash
# Tag the pod subnets
aws ec2 create-tags \
  --resources $(aws ec2 describe-subnets --filters "Name=tag:Name,Values=*pods*" --query "Subnets[*].SubnetId" --output text) \
  --tags Key=karpenter.sh/discovery,Value=student1 \
  --region us-east-2
```

### 1b. Discover EKS Node Security Group and tag it:
```bash
# Tag the EKS Cluster Primary Security Group
aws ec2 create-tags \
  --resources $(aws eks describe-cluster --name student1 --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text) \
  --tags Key=karpenter.sh/discovery,Value=student1 \
  --region us-east-2
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

### 2b. Create the Karpenter Controller IAM ServiceAccount (IRSA)

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
            "Federated": "arn:aws:iam://${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
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

## Step 3 — Install Karpenter via Helm

1.  Log in to the public Amazon ECR registry to retrieve the Helm chart:
    ```bash
    aws ecr-public get-login-password --region us-east-1 | helm registry login --username AWS --password-stdin public.ecr.aws
    ```

2.  Install the Karpenter Helm chart:
    ```bash
    helm install karpenter oci://public.ecr.aws/karpenter/karpenter \
      --namespace karpenter \
      --version v0.35.1 \
      --set serviceAccount.create=false \
      --set serviceAccount.name=karpenter \
      --set settings.aws.clusterName=student1 \
      --set settings.aws.defaultInstanceProfile=KarpenterNodeRole-student1 \
      --set settings.aws.interconnect=private \
      --wait
    ```

---

## Step 4 — Configure NodePool & EC2NodeClass CRDs

Karpenter uses custom resources to control node provisioning:
*   **`EC2NodeClass`**: Configures AWS-specific details like subnets, security groups, AMIs, and block devices.
*   **`NodePool`**: Configures general scheduler limits, taints, and instance type choices.

Apply the following manifest to define the default provisioning rules:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: default
  namespace: karpenter
spec:
  amiFamily: AL2023
  role: KarpenterNodeRole-student1
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: student1
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: student1
---
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
  namespace: karpenter
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
        name: default
  limits:
    cpu: 100
  disruption:
    consolidationPolicy: WhenUnderutilized
    expireAfter: 720h
EOF
```

---

## Step 5 — Test Fast Scale-Up

Let's verify Karpenter's rapid scaling by launching a heavy deployment.

1.  Monitor the Karpenter controller logs in a separate terminal:
    ```bash
    kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f
    ```

2.  Create a test deployment and scale it up to 20 replicas:
    ```bash
    kubectl create deployment karpenter-test --image=public.ecr.aws/ecs-sample-image/amazon-ecs-sample:latest
    kubectl scale deployment karpenter-test --replicas=20
    ```

3.  Observe Karpenter's controller logs. You will see Karpenter calculate the required compute capacity and directly trigger instance creation:
    ```
    found provisionable pod(s)... launching node... 
    ```

4.  Check the nodes. A new node will join the cluster in approximately 30 seconds:
    ```bash
    kubectl get nodes -w
    ```

---

## Step 6 — Test Consolidation (Cost Optimization)

One of Karpenter's key advantages is **consolidation** (automatically defragmenting workloads and terminating idle/underutilized nodes to save costs).

1.  Delete the test deployment:
    ```bash
    kubectl delete deployment karpenter-test
    ```

2.  Watch the Karpenter logs. Within 15-30 seconds, Karpenter will detect that the node it launched is now empty and underutilized, scale the node down, and terminate the underlying EC2 instance automatically:
    ```
    disrupting node default/ip-10-50-x-x... terminating node...
    ```

3.  Verify the cluster has returned to its baseline state (only the two original worker nodes):
    ```bash
    kubectl get nodes
    ```

---

## Step 7 — Advanced Scaling: Spot Instances with Taints and Tolerations

Karpenter allows you to easily scale workloads on Spot instances to save up to 90% off On-Demand pricing. In this exercise, we will create a dedicated Spot NodePool with a custom taint, ensuring only workloads that tolerate Spot instances can run on them.

### 7a. Deploy a Spot NodePool

Create a new NodePool resource that targets Spot instances and has a `spot-only=true:NoSchedule` taint:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: spot
  namespace: karpenter
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
        name: default
      taints:
        - key: spot-only
          value: "true"
          effect: NoSchedule
  limits:
    cpu: 100
  disruption:
    consolidationPolicy: WhenUnderutilized
    expireAfter: 720h
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
        image: public.ecr.aws/ecs-sample-image/amazon-ecs-sample:latest
        resources:
          requests:
            cpu: "250m"
            memory: "512Mi"
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
   *Within 15-30 seconds, Karpenter will automatically terminate the Spot instance because the workload is gone.*

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
  * **Incorrect NodeClass Reference**: Check your `NodePool` definition. `spec.nodeClassRef.name` must exactly match the `metadata.name` of your `EC2NodeClass` (e.g., `default`).
  * **Resource Request Limits**: Check the Karpenter logs. If you see `limits exceeded`, the node launch would violate the `limits.cpu` or `limits.memory` configured on the NodePool.

### 3. Controller Logs Show `UnauthorizedOperation` or `AccessDenied`
* **Symptom**: Logs show `UnauthorizedOperation: You are not authorized to perform this operation.` when calling `ec2:RunInstances` or `ec2:DescribeAvailabilityZones`.
* **Causes**:
  * **IAM Policy Permissions**: The `KarpenterControllerRole-student1` requires EC2 permissions. If you didn't use Option A (`eksctl` with `AmazonEC2FullAccess` policy), verify that the manual IAM role has the `AmazonEC2FullAccess` policy (or equivalent scoped policy) attached.
  * **Instance Profile Missing**: Ensure the instance profile configured in Karpenter's Helm values/settings matches the Karpenter Node Role.

### 4. CRD Verification Failures
* **Symptom**: `error: resource mapping not found for name: "default" namespace: "" from "STDIN": no matches for kind "NodePool" in version "karpenter.sh/v1beta1"`.
* **Causes**:
  * **CRDs Not Installed**: When installing Karpenter using Helm, make sure you did not skip CRD installation. Karpenter CRDs are required to support `NodePool` and `EC2NodeClass` resources. You can apply them manually if missing:
    ```bash
    kubectl apply -f https://raw.githubusercontent.com/aws/karpenter-provider-aws/v0.35.1/pkg/apis/crds/karpenter.sh_nodepools.yaml
    kubectl apply -f https://raw.githubusercontent.com/aws/karpenter-provider-aws/v0.35.1/pkg/apis/crds/karpenter.k8s.aws_ec2nodeclasses.yaml
    ```

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

  # Detach policies and delete the Controller IAM Role
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
