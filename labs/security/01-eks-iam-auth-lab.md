# EKS IAM Authentication & Authorization (Access Entries & RBAC)

This guide walks you through configuring EKS authentication and authorization using AWS IAM identities (Users, Groups, and Roles):
1.  **Lab 1**: Direct IAM User mapping to Kubernetes User RBAC.
2.  **Lab 2**: IAM Group organization mapped to Kubernetes Group RBAC.
3.  **Lab 3**: AWS-managed EKS Access Policies (no custom Kubernetes RBAC).
4.  **Lab 4**: IAM Role mapping to Kubernetes Group RBAC.
5.  **Lab 5**: Legacy `aws-auth` ConfigMap mapping (Deprecated).

All verification is done directly from your admin session using Kubernetes **User Impersonation** (`kubectl --as` and `kubectl --as-group`).

---

## Lab 1 — Direct IAM User Mapping to Kubernetes User RBAC

In this lab, you will create a single IAM User, map it to a Kubernetes username using EKS Access Entries, and authorize it using a custom Kubernetes Role and RoleBinding.

### Step 1a: Identify or Create the Test IAM User
Choose **one** of the following options:

*   **Option A: Create a New User (Default)**:
    Run the following command as an AWS Administrator:
    ```bash
    aws iam create-user --user-name eks-user-john
    ```

*   **Option B: Use an Existing User**:
    Retrieve the ARN of your existing IAM user:
    ```bash
    aws iam get-user --user-name <existing-user-name> --query "User.Arn" --output text
    ```
    *(Take note of the ARN returned. Replace `eks-user-john` in later steps with your actual user name).*

Retrieve your AWS Account ID:
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

### Step 1b: Create EKS Access Entry (Map IAM User to Kubernetes Username)
Create the access entry mapping the IAM User ARN to the Kubernetes username `eks-user-john`:

```bash
aws eks create-access-entry \
  --cluster-name student1 \
  --principal-arn arn:aws:iam::${ACCOUNT_ID}:user/eks-user-john \
  --username eks-user-john \
  --region us-east-2
```

#### Test Authentication (Before Authorization):
At this point, the IAM User's identity is registered (authenticated) by EKS, but no authorization rules have been configured inside Kubernetes yet.

Test if the user can access pods using impersonation:
```bash
kubectl get pods -n default --as eks-user-john
```

**Expected Result**:
The request is rejected because the user has **no permissions**:
```
Error from server (Forbidden): pods is forbidden: User "eks-user-john" cannot list resource "pods" in API group "" in the namespace "default"
```

### Step 1c: Configure Kubernetes RBAC (Targeting Username)
Create a dedicated namespace `john-space` and bind the username `eks-user-john` directly to a `Role` allowing pod access:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: john-space
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: john-space
  name: john-developer
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log", "pods/exec"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: john-space
  name: bind-john-developer
subjects:
- kind: User
  name: eks-user-john   # <-- Maps directly to the Kubernetes username
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: john-developer
  apiGroup: rbac.authorization.k8s.io
EOF
```

### Step 1d: Verify Access
1.  **Verify access to the authorized namespace**:
    ```bash
    # 1. Create a pod (succeeds)
    kubectl run web --image=nginx -n john-space --as eks-user-john
    
    # 2. List the pods (succeeds)
    kubectl get pods -n john-space --as eks-user-john
    ```
2.  **Verify restriction from other namespaces**:
    ```bash
    kubectl get pods -n kube-system --as eks-user-john
    ```
    *Expected output: Error from server (Forbidden).*

### Step 1e: Clean Up Lab 1
Clean up the Access Entry and Kubernetes RBAC resources so we start Lab 2 with a clean slate (leave the IAM User `eks-user-john` intact):
```bash
# Delete namespace
kubectl delete namespace john-space

# Delete Access Entry
aws eks delete-access-entry \
  --cluster-name student1 \
  --principal-arn arn:aws:iam::${ACCOUNT_ID}:user/eks-user-john \
  --region us-east-2
```

---

## Lab 2 — IAM Group Mapping to Kubernetes Group RBAC

### ⚠️ EKS Limitation: No Direct IAM Group Support
AWS IAM Groups are **not cryptographic identities** and cannot sign API requests to the cluster. Because of this:
*   You **cannot** add an IAM Group ARN to EKS Access Entries or the `aws-auth` ConfigMap.
*   The EKS API will reject any attempt to use a group ARN as a `principal_arn`.

### The Solution: Kubernetes Group Mapping
To manage access for a team of users organized in an IAM Group without using IAM Roles:
1.  Organize your users into an AWS **IAM Group** (`eks-developers`) for administrative ease in AWS.
2.  Add EKS Access Entries for the **individual IAM Users** belonging to that group.
3.  Map these users' Access Entries to a shared Kubernetes group (**`developer-group`**) inside EKS.
4.  Bind the Kubernetes group to RBAC rules inside the cluster.

### Step 2a: Create the IAM Group and Add Membership
1.  Create the IAM Group `eks-developers`:
    ```bash
    aws iam create-group --group-name eks-developers
    ```
2.  Add the user `eks-user-john` to the group:
    ```bash
    aws iam add-user-to-group --user-name eks-user-john --group-name eks-developers
    ```

### Step 2b: Create EKS Access Entry with Group Mapping
Create the EKS Access Entry for the user, mapping their credentials to the Kubernetes group `developer-group`:

```bash
aws eks create-access-entry \
  --cluster-name student1 \
  --principal-arn arn:aws:iam::${ACCOUNT_ID}:user/eks-user-john \
  --kubernetes-groups developer-group \
  --region us-east-2
```

#### Test Authentication (Before Authorization):
At this point, EKS maps the user to the Kubernetes group `developer-group`, but no RBAC permissions have been applied to this group inside Kubernetes yet.

Test if the user can access pods in the `default` namespace using the group mapping:
```bash
kubectl get pods -n default --as eks-user-john --as-group developer-group
```

**Expected Result**:
The request is rejected because the group `developer-group` has no permissions:
```
Error from server (Forbidden): pods is forbidden: User "eks-user-john" cannot list resource "pods" in API group "" in the namespace "default"
```

### Step 2c: Configure Kubernetes RBAC (Targeting Kubernetes Group)
Configure `developer-space` namespace and grant pod access to the group `developer-group`:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: developer-space
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: developer-space
  name: pod-developer
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log", "pods/exec"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: developer-space
  name: bind-pod-developer
subjects:
- kind: Group
  name: developer-group   # <-- Maps to the EKS Access Entry group
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: pod-developer
  apiGroup: rbac.authorization.k8s.io
EOF
```

### Step 2d: Verify Group Access
Test namespace access by impersonating the user and their mapped group:
```bash
# 1. Verify access to developer-space works (impersonating both the user and their group)
kubectl run web --image=nginx -n developer-space --as eks-user-john --as-group developer-group

# 2. List the pods in developer-space (succeeds)
kubectl get pods -n developer-space --as eks-user-john --as-group developer-group

# 3. Verify access to other namespaces is blocked
kubectl get pods -n kube-system --as eks-user-john
```

### Step 2e: Clean Up Lab 2
Clean up the group-specific resources (leave the IAM User `eks-user-john` intact):
```bash
# Delete namespace
kubectl delete namespace developer-space

# Delete Access Entry
aws eks delete-access-entry \
  --cluster-name student1 \
  --principal-arn arn:aws:iam::${ACCOUNT_ID}:user/eks-user-john \
  --region us-east-2

# Remove user from group and delete group
aws iam remove-user-from-group --user-name eks-user-john --group-name eks-developers
aws iam delete-group --group-name eks-developers
```

---

## Lab 3 — AWS-Managed EKS Access Policies

Instead of managing Kubernetes Roles/Bindings manually, EKS Access Entries allow you to associate **AWS-managed Access Policies** directly with IAM Users or Roles.

### Existing EKS Access Policies Cheat Sheet
Here is a list of default EKS Access Policies provided by AWS, and the access level they grant on your cluster:

| Policy ARN Suffix | Kubernetes equivalent | Allowed Actions |
| :--- | :--- | :--- |
| **`AmazonEKSClusterAdminPolicy`** | `system:masters` | Full admin access to all resources across the entire cluster. |
| **`AmazonEKSAdminPolicy`** | `admin` clusterrole | Admin permissions within a scoped namespace or cluster-wide. |
| **`AmazonEKSEditPolicy`** | `edit` clusterrole | Read/Write access to most resources (excludes Roles/Bindings). |
| **`AmazonEKSViewerPolicy`** | `view` clusterrole | Read-only visibility to view resources. |

---

### Step 3a: Create the Base EKS Access Entry
Since we cleaned up the EKS Access Entry in Lab 2, recreate a clean Access Entry for `eks-user-john` without any custom Kubernetes groups:
```bash
aws eks create-access-entry \
  --cluster-name student1 \
  --principal-arn arn:aws:iam::${ACCOUNT_ID}:user/eks-user-john \
  --region us-east-2
```

#### Test Policy Access (Before Association):
Test if the user can query cluster-wide resources (like nodes) before associating the EKS access policy:
```bash
kubectl get nodes --as eks-user-john
```

**Expected Result**:
Access is denied because the user has no authorization mapping yet:
```
Error from server (Forbidden): nodes is forbidden: User "eks-user-john" cannot list resource "nodes" in API group "" at the cluster scope
```

### Step 3b: Associate the Viewer Access Policy
Associate `AmazonEKSViewerPolicy` to the user `eks-user-john` to grant cluster-wide read-only visibility:

```bash
aws eks associate-access-policy \
  --cluster-name student1 \
  --principal-arn arn:aws:iam::${ACCOUNT_ID}:user/eks-user-john \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewerPolicy \
  --access-scope type=cluster \
  --region us-east-2
```

### Step 3c: Verify Policy Access
Test if the user can now query nodes:
```bash
kubectl get nodes --as eks-user-john
```
**Expected Result**:
The command succeeds and returns the list of nodes.

### Step 3d: Clean Up Lab 3
Run the following teardown commands to delete the Access Entry and permanently remove the IAM User:
```bash
# Disassociate Access Policy
aws eks disassociate-access-policy \
  --cluster-name student1 \
  --principal-arn arn:aws:iam::${ACCOUNT_ID}:user/eks-user-john \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewerPolicy \
  --region us-east-2

# Delete Access Entry
aws eks delete-access-entry \
  --cluster-name student1 \
  --principal-arn arn:aws:iam::${ACCOUNT_ID}:user/eks-user-john \
  --region us-east-2

# Delete the IAM User
aws iam delete-user --user-name eks-user-john
```

---

## Lab 4 — IAM Role Mapping to Kubernetes Group RBAC

IAM Roles are the recommended authentication method for applications and users in production. Unlike IAM Users, IAM Roles provide short-lived credentials and can be assumed dynamically by AWS services, external identities, or specific IAM Users.

In this lab, you will create an IAM Role, map it to a Kubernetes group using EKS Access Entries, and authorize it using a Kubernetes Role and RoleBinding.

### Step 4a: Create the EKS IAM Role
1.  Create a trust relationship document allowing users in your AWS account to assume this role:
    ```bash
    cat <<EOF > trust-policy.json
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": {
            "AWS": "arn:aws:iam::${ACCOUNT_ID}:root"
          },
          "Action": "sts:AssumeRole"
        }
      ]
    }
    EOF
    ```

2.  Create the IAM Role named `EKSAdminRole`:
    ```bash
    aws iam create-role \
      --role-name EKSAdminRole \
      --assume-role-policy-document file://trust-policy.json
    ```

### Step 4b: Create EKS Access Entry for the IAM Role
Create the Access Entry mapping the IAM Role to the Kubernetes group `admin-group`.

> [!NOTE]  
> When EKS authenticates an assumed-role session, it maps the dynamic STS session ARN (`arn:aws:sts::<ACCOUNT_ID>:assumed-role/EKSAdminRole/<session-name>`) back to the base IAM Role ARN. Therefore, the `principal-arn` in the Access Entry must be the base IAM Role:

```bash
aws eks create-access-entry \
  --cluster-name student1 \
  --principal-arn arn:aws:iam::${ACCOUNT_ID}:role/EKSAdminRole \
  --kubernetes-groups admin-group \
  --region us-east-2
```

#### Test Authentication (Before Authorization):
Test if the assumed role has access to pods before configuring the RBAC mapping. We will use the impersonated assumed-role session format:
```bash
kubectl get pods -n default --as arn:aws:sts::${ACCOUNT_ID}:assumed-role/EKSAdminRole/admin-session --as-group admin-group
```

**Expected Result**:
Access is denied because the Kubernetes group `admin-group` has no permissions configured:
```
Error from server (Forbidden): pods is forbidden: User "arn:aws:sts::123456789012:assumed-role/EKSAdminRole/admin-session" cannot list resource "pods" in API group "" in the namespace "default"
```

### Step 4c: Configure Kubernetes RBAC (Targeting Kubernetes Group)
Configure the `admin-space` namespace and bind the `admin-group` to a `Role` allowing full pod access:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: admin-space
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: admin-space
  name: admin-developer
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log", "pods/exec"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: admin-space
  name: bind-admin-developer
subjects:
- kind: Group
  name: admin-group   # <-- Maps to the EKS Access Entry group
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: admin-developer
  apiGroup: rbac.authorization.k8s.io
EOF
```

### Step 4d: Verify Role Access
Test pod access in the `admin-space` namespace, impersonating the assumed-role session:

```bash
# 1. Verify access to admin-space works (impersonating both the role and its K8s group)
kubectl run web --image=nginx -n admin-space \
  --as arn:aws:sts::${ACCOUNT_ID}:assumed-role/EKSAdminRole/admin-session \
  --as-group admin-group

# 2. List the pods in admin-space (succeeds)
kubectl get pods -n admin-space \
  --as arn:aws:sts::${ACCOUNT_ID}:assumed-role/EKSAdminRole/admin-session \
  --as-group admin-group

# 3. Verify other namespaces are blocked
kubectl get pods -n kube-system \
  --as arn:aws:sts::${ACCOUNT_ID}:assumed-role/EKSAdminRole/admin-session
```

### Step 4e: Clean Up Lab 4
Clean up the role-specific resources:
```bash
# Delete namespace
kubectl delete namespace admin-space

# Delete Access Entry
aws eks delete-access-entry \
  --cluster-name student1 \
  --principal-arn arn:aws:iam::${ACCOUNT_ID}:role/EKSAdminRole \
  --region us-east-2

# Delete the IAM Role
aws iam delete-role --role-name EKSAdminRole

# Delete local files
rm -f trust-policy.json
```

---

## Lab 5 — Legacy `aws-auth` ConfigMap Mapping (Deprecated)

> [!WARNING]  
> **Deprecation and Version Support Warning**:  
> * **EKS 1.29 and earlier**: `aws-auth` ConfigMap was the standard and only native method for mapping IAM identities.
> * **EKS 1.30**: EKS introduced EKS Access Entries and supports a **Hybrid authentication mode** (`API_AND_CONFIG_MAP`), where both Access Entries and `aws-auth` ConfigMap mappings are evaluated.
> * **EKS 1.31 and newer**: **The `aws-auth` ConfigMap is deprecated and completely removed**. EKS clusters default to the `API` authentication mode, and the cluster completely ignores the `aws-auth` ConfigMap. You **must** use EKS Access Entries (Labs 1–4).

In this lab, you will configure authentication using the legacy `aws-auth` ConfigMap method (supported on EKS 1.30 and older).

### Step 5a: Identify or Create the Test IAM User
Choose **one** of the following options:

*   **Option A: Create a New User (Default)**:
    Run the following command as an AWS Administrator:
    ```bash
    aws iam create-user --user-name eks-user-john
    ```

*   **Option B: Use an Existing User**:
    Retrieve the ARN of your existing IAM user:
    ```bash
    aws iam get-user --user-name <existing-user-name> --query "User.Arn" --output text
    ```

Retrieve your AWS Account ID:
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

### Step 5b: Map IAM User via `aws-auth` ConfigMap (Authentication)
The `aws-auth` ConfigMap is located in the `kube-system` namespace. You must edit it to map your IAM User's ARN to a Kubernetes username and a Kubernetes group.

1.  Open the ConfigMap for editing:
    ```bash
    kubectl edit configmap aws-auth -n kube-system
    ```

2.  Add your user mapping under the `data.mapUsers` field (replace `123456789012` with your actual Account ID):
    ```yaml
    apiVersion: v1
    data:
      mapRoles: |
        - groups:
          - system:bootstrappers
          - system:nodes
          rolearn: arn:aws:iam::123456789012:role/eks-student1-node-role
          username: system:node:{{EC2PrivateDNSName}}
      # --- ADD THIS mapUsers SECTION ---
      mapUsers: |
        - userarn: arn:aws:iam::123456789012:user/eks-user-john
          username: eks-user-john
          groups:
            - developer-group
    ```
    *Save and exit the editor.*

#### Test Authentication (Before Authorization):
Verify EKS successfully authenticates the user but rejects them because Kubernetes RBAC is not yet configured for the group:
```bash
kubectl get pods -n default --as eks-user-john --as-group developer-group
```

**Expected Result**:
```
Error from server (Forbidden): pods is forbidden: User "eks-user-john" cannot list resource "pods" in API group "" in the namespace "default"
```

### Step 5c: Configure Kubernetes RBAC (Targeting Kubernetes Group)
Configure `developer-space` namespace and grant pod access to the group `developer-group`:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: developer-space
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: developer-space
  name: pod-developer
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log", "pods/exec"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: developer-space
  name: bind-pod-developer
subjects:
- kind: Group
  name: developer-group   # <-- Maps to the group in aws-auth mapUsers
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: pod-developer
  apiGroup: rbac.authorization.k8s.io
EOF
```

### Step 5d: Verify Access
Test namespace access by impersonating the user and their mapped group:
```bash
# 1. Verify access to developer-space works (impersonating both the user and their group)
kubectl run web --image=nginx -n developer-space --as eks-user-john --as-group developer-group

# 2. List the pods in developer-space (succeeds)
kubectl get pods -n developer-space --as eks-user-john --as-group developer-group

# 3. Verify other namespaces are blocked
kubectl get pods -n kube-system --as eks-user-john
```

### Step 5e: Clean Up Lab 5
Clean up the resources created during this lab:
```bash
# Delete namespace
kubectl delete namespace developer-space

# Remove the user mapping from the aws-auth ConfigMap
kubectl edit configmap aws-auth -n kube-system
# (Remove the mapUsers section you added under data)

# Delete the IAM User
aws iam delete-user --user-name eks-user-john
```
