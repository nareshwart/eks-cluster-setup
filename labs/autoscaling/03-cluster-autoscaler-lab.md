# Scaling EKS with Cluster Autoscaler

This guide walks you through deploying the **Cluster Autoscaler** to dynamically adjust the size of your EKS node group in response to pending pods.

---

## Prerequisites

Before starting, ensure your cluster worker nodes are tagged with the following auto-discovery tags.  
*(These are already included by default in your `cluster.yaml` and Terraform node group setups)*:

*   `k8s.io/cluster-autoscaler/enabled` = `true`
*   `k8s.io/cluster-autoscaler/<cluster-name>` = `owned`

---

## Step 1 — Create IAM Role for Service Account (IRSA)

The Cluster Autoscaler pod requires AWS permissions to modify the desired capacity of Auto Scaling Groups. We will associate an IAM Role with the Kubernetes ServiceAccount (`cluster-autoscaler` in namespace `kube-system`).

Choose **one** of the following options to bind the IAM policy permissions to the Cluster Autoscaler service account.

#### Option A: Create Automatically via `eksctl`
This is the fastest method. `eksctl` will create the IAM role, set up the OIDC trust relationship, and deploy the annotated Kubernetes ServiceAccount in a single step:

```bash
eksctl create iamserviceaccount \
  --cluster=student1 \
  --namespace=kube-system \
  --name=cluster-autoscaler \
  --role-name=ClusterAutoscalerRole-student1 \
  --attach-policy-arn=arn:aws:iam::aws:policy/AutoScalingFullAccess \
  --override-existing-serviceaccounts \
  --approve
```

---

#### Option B: Manual IAM Creation & YAML Manifest (Standard Kubernetes Method)
Use this option to manually create the AWS resources and bind them using a Kubernetes YAML manifest.

1.  **Retrieve EKS cluster OIDC Provider and Account Details**:
    ```bash
    OIDC_PROVIDER=$(aws eks describe-cluster --name student1 --query "cluster.identity.oidc.issuer" --output text | sed -e "s/https:\/\///")
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    ```

2.  **Create the Trust Relationship policy document**:
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
              "${OIDC_PROVIDER}:sub": "system:serviceaccount:kube-system:cluster-autoscaler",
              "${OIDC_PROVIDER}:aud": "sts.amazonaws.com"
            }
          }
        }
      ]
    }
    EOF
    ```

3.  **Create the IAM Role & Attach the Policy**:
    ```bash
    # Create the IAM role using the trust policy
    aws iam create-role \
      --role-name ClusterAutoscalerRole-student1 \
      --assume-role-policy-document file://trust-policy.json

    # Attach the Auto Scaling policy to the role
    aws iam attach-role-policy \
      --role-name ClusterAutoscalerRole-student1 \
      --policy-arn arn:aws:iam::aws:policy/AutoScalingFullAccess
    ```

4.  **Create the ServiceAccount YAML file (`autoscaler-sa.yaml`)**:
    Create a file named `autoscaler-sa.yaml` with the following content (replace `ACCOUNT_ID` with your actual AWS Account ID):
    ```yaml
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: cluster-autoscaler
      namespace: kube-system
      annotations:
        eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/ClusterAutoscalerRole-student1
    ```

5.  **Apply the manifest**:
    ```bash
    kubectl apply -f autoscaler-sa.yaml
    ```

> **Note**: In a production environment, you should use a scoped custom IAM Policy instead of `AutoScalingFullAccess` for better security (least privilege).

---

## Step 2 — Deploy Cluster Autoscaler

Choose **one** of the following options to deploy the Cluster Autoscaler.

### Option A — Deploy via Helm (Recommended)

1.  Add the official Kubernetes Autoscaler Helm repository:
    ```bash
    helm repo add autoscaler https://kubernetes.github.io/autoscaler
    helm repo update
    ```

2.  Deploy the release (replace `student1` with your cluster name and `us-east-2` with your region):
    ```bash
    helm install cluster-autoscaler autoscaler/cluster-autoscaler \
      --namespace kube-system \
      --set autoDiscovery.clusterName=student1 \
      --set awsRegion=us-east-2 \
      --set rbac.serviceAccount.create=false \
      --set rbac.serviceAccount.name=cluster-autoscaler
    ```

---

### Option B — Deploy via YAML Manifest

1.  Download the official deployment manifest:
    ```bash
    curl -o cluster-autoscaler-autodiscover.yaml https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml
    ```

2.  Open the file and find the string `<YOUR CLUSTER NAME>`. Replace it with your actual cluster name (e.g. `student1`).

3.  Apply the manifest:
    ```bash
    kubectl apply -f cluster-autoscaler-autodiscover.yaml
    ```

4.  Annotate the manifest's service account to use the IAM Role created by eksctl (replace `<ACCOUNT_ID>` with your actual AWS Account ID):
    ```bash
    kubectl annotate serviceaccount cluster-autoscaler \
      -n kube-system \
      eks.amazonaws.com/role-arn=arn:aws:iam::<ACCOUNT_ID>:role/ClusterAutoscalerRole-student1
    ```

---

## Step 3 — Verify the Autoscaler

Ensure the autoscaler pod is running and inspect the logs. Use the correct label selector depending on your deployment method:

```bash
# If installed via Helm (Option A):
kubectl get pods -n kube-system -l "app.kubernetes.io/name=aws-cluster-autoscaler"
kubectl logs -n kube-system -l "app.kubernetes.io/name=aws-cluster-autoscaler" --tail=50

# If installed via YAML manifest (Option B):
kubectl get pods -n kube-system -l "k8s-app=cluster-autoscaler"
kubectl logs -n kube-system -l "k8s-app=cluster-autoscaler" --tail=50
```

Look for logs indicating that the Auto Scaling Groups were successfully parsed:
```
I0802 04:55:12.123456       1 static_autoscaler.go:210] Starting Cluster Autoscaler
I0802 04:55:13.234567       1 auto_scaling_groups.go:340] Refreshed ASG list: [eks-student1-managed-ng-xxx]
```

---

## Step 4 — Test Scale-Up (Trigger Scaling)

Let's deploy a large workload to exceed the current capacity of your 2 worker nodes.

1.  Create a deployment with 40 replicas, specifying CPU requests to guarantee we exceed node capacities and trigger the autoscaler:
    ```bash
    kubectl create deployment scale-test --image=public.ecr.aws/ecs-sample-image/amazon-ecs-sample:latest
    kubectl set resources deployment scale-test --requests=cpu=200m
    kubectl scale deployment scale-test --replicas=40
    ```

2.  Watch the pod statuses. Some pods will remain in `Pending` state because the nodes are out of CPU/Memory capacity:
    ```bash
    kubectl get pods -o wide -w
    ```

3.  Monitor the autoscaler log. It will detect the `Pending` pods and request a scale-up from AWS (use the correct label selector for your deployment method):
    ```bash
    # For Helm (Option A):
    kubectl logs -n kube-system -l "app.kubernetes.io/name=aws-cluster-autoscaler" -f

    # For YAML Manifest (Option B):
    kubectl logs -n kube-system -l "k8s-app=cluster-autoscaler" -f
    ```
    Look for: `Triggering scale up for group eks-student1-managed-ng-xxx`.

4.  Check the EC2 Instance count. Within 1-2 minutes, you will see a third worker node register and join the cluster:
    ```bash
    kubectl get nodes -w
    ```

---

## Step 5 — Test Scale-Down (Cleanup)

1.  Scale down or delete the test deployment:
    ```bash
    kubectl delete deployment scale-test
    ```

2.  Watch the logs. After a few minutes of inactivity (usually 10 minutes default cooldown), the Cluster Autoscaler will detect that the third node is underutilized and terminate it:
    ```bash
    kubectl get nodes -w
    ```

---

## Troubleshooting & Common Issues

### 1. Autoscaler Pod Fails to Start or Fails to Discover ASGs
* **Symptom**: Logs show `Failed to regenerate ASG cache` or `Refreshed ASG list: []`.
* **Causes**:
  * **Incorrect AWS Tags**: Ensure your worker node Auto Scaling Groups have the tags `k8s.io/cluster-autoscaler/enabled = true` and `k8s.io/cluster-autoscaler/<cluster-name> = owned`. In EKS Managed Node Groups, these tags must be applied to both the Node Group and the underlying EC2 instances (typically managed via the Launch Template).
  * **Incorrect Region or Cluster Name**: Double-check the `--set autoDiscovery.clusterName=` and `--set awsRegion=` values in your Helm command or YAML manifest.
  * **IAM Permissions (IRSA)**: The `cluster-autoscaler` ServiceAccount must have the correct IAM Role annotation: `eks.amazonaws.com/role-arn`. Verify this by running:
    ```bash
    kubectl get sa cluster-autoscaler -n kube-system -o yaml
    ```

### 2. Node Group Fails to Scale Up
* **Symptom**: Pods remain in `Pending` state, but no new nodes are added.
* **Causes**:
  * **Autoscaler Log Access Denied**: Look at the autoscaler pod logs. If you see `AccessDenied: User ... is not authorized to perform: autoscaling:DescribeAutoScalingGroups`, the IAM role doesn't have the necessary autoscaling policy attached, or the trust relationship is misconfigured.
  * **Insufficient Resource Requests**: Cluster Autoscaler relies on pod **resource requests** (not limits) to calculate required capacity. If your pending pods do not have `resources.requests.cpu` or `resources.requests.memory` defined, the autoscaler might ignore them.
  * **ASG Limits Reached**: Check if the Auto Scaling Group has already reached its `max_size`. If `max_size` is 2 and you have 2 nodes, it won't scale further.

### 3. Nodes Do Not Scale Down
* **Symptom**: Nodes remain idle or underutilized, but the node count does not decrease.
* **Causes**:
  * **Default Scale-Down Delay**: By default, Cluster Autoscaler waits 10 minutes after a node becomes unneeded before terminating it.
  * **Unremovable Pods**: A node will not be scaled down if it contains:
    * Pods with local storage (e.g., `emptyDir` or `hostPath`), unless they have the `"cluster-autoscaler.kubernetes.io/safe-to-evict": "true"` annotation.
    * Pods that are not managed by a controller (like a Deployment, StatefulSet, or ReplicaSet).
    * Pods running in the `kube-system` namespace that do not have a PodDisruptionBudget configured.
    * Pods with restrictive PodDisruptionBudgets that would be violated by the eviction.

---

## Best Practices

### 1. Use Scoped IAM Policy (Least Privilege)
Instead of using `AutoScalingFullAccess`, use a custom IAM Policy that restricts permissions to EKS-managed Auto Scaling Groups. Here is a recommended production policy template:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeScalingActivities",
        "autoscaling:DescribeTags",
        "ec2:DescribeImages",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:GetInstanceTypesFromInstanceRequirements"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:ResourceTag/k8s.io/cluster-autoscaler/enabled": "true"
        }
      }
    }
  ]
}
```

### 2. Define CPU and Memory Requests
Always define `resources.requests` for all deployments. The autoscaler uses these requests to determine if a node has enough capacity to schedule new pods. Without requests, the autoscaler cannot determine if a node is over-provisioned or needs to scale.

### 3. Prevent Eviction of Critical Pods
If you have a batch job or a long-running process that shouldn't be interrupted by a scale-down event, annotate the pod with:
```yaml
metadata:
  annotations:
    cluster-autoscaler.kubernetes.io/safe-to-evict: "false"
```

### 4. Configure Pod Disruption Budgets (PDBs)
Define PDBs for your critical applications to prevent the autoscaler from draining too many replicas of your application at once during scale-down operations.

### 5. Match ASG Configurations
Ensure all instances inside a single Auto Scaling Group have the same CPU, memory, and storage specifications. The Cluster Autoscaler assumes all nodes in a group are identical; differing node sizes within a group will lead to unpredictable scaling behavior.

---

## Clean Up Everything

To prevent incurring AWS charges and restore your cluster and AWS account to their baseline states, run the following cleanup steps in order:

### 1. Delete the Test Deployment
```bash
kubectl delete deployment scale-test
```

### 2. Uninstall Cluster Autoscaler
Depending on how you installed Cluster Autoscaler in Step 2, run the corresponding command:

* **If you used Option A (Helm)**:
  ```bash
  helm uninstall cluster-autoscaler --namespace kube-system
  ```

* **If you used Option B (YAML Manifest)**:
  ```bash
  kubectl delete -f cluster-autoscaler-autodiscover.yaml
  ```

### 3. Delete the IAM ServiceAccount and Role
* **If you used Option A (eksctl)**:
  ```bash
  eksctl delete iamserviceaccount \
    --cluster=student1 \
    --namespace=kube-system \
    --name=cluster-autoscaler
  ```

* **If you used Option B (Manual)**:
  ```bash
  # Delete the ServiceAccount
  kubectl delete serviceaccount cluster-autoscaler --namespace kube-system

  # Detach the policy and delete the IAM Role
  aws iam detach-role-policy --role-name ClusterAutoscalerRole-student1 --policy-arn arn:aws:iam::aws:policy/AutoScalingFullAccess
  aws iam delete-role --role-name ClusterAutoscalerRole-student1
  ```

