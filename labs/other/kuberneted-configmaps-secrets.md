# Architectural Guide: Kubernetes ConfigMaps & Secrets

This document explains how to decouple configuration data and sensitive parameters from application code using Kubernetes **ConfigMaps** and **Secrets**. It covers injection methods (environment variables vs. mounted volumes) and security best practices with real-time YAML examples.

---

## 🗺️ ConfigMaps vs. Secrets: Core Concepts

```
┌─────────────────────────────────────────────────────────────────────────┐
│ APPLICATION CODE (Pre-built container image, e.g., my-app:v1.0)         │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │ Reads config at runtime
                                     ▼
      ┌─────────────────────────────────────────────────────────────┐
      │  DECOUPLED CONFIGURATION LAYERS                             │
      │                                                             │
      │   ConfigMap (Plain Text)       Secret (Sensitive Data)       │
      │   - DB Connection URL          - Database Passwords          │
      │   - Port numbers               - API Tokens                  │
      │   - Log levels (DEBUG/INFO)    - SSL/TLS Private Keys        │
      └─────────────────────────────────────────────────────────────┘
```

*   **ConfigMap**: Stores non-confidential configuration settings in key-value pairs or complete configuration files.
*   **Secret**: Stores sensitive parameters. The keys are automatically **Base64-encoded** in the API. 
    > [!CAUTION]
    > **Base64 is NOT encryption!** Base64 is simple obfuscation that can be decoded by anyone with access to the namespace. For production security, enable AWS KMS envelope encryption for Kubernetes Secrets in your EKS cluster settings.

---

## ⚙️ Ingress Injection Methods

Kubernetes allows pods to consume ConfigMaps and Secrets in two ways:

1.  **Environment Variables**:
    *   Values are loaded when the container starts.
    *   *Drawback*: If you change the ConfigMap/Secret value, the running pod **does not** automatically receive the update; you must restart/rollout the deployment to fetch new values.
2.  **Mounted Volumes (Files)**:
    *   Values are projected as files inside a folder (e.g. `/etc/config/db-url`).
    *   *Advantage*: The Kubelet automatically syncs updates. If you modify the ConfigMap/Secret on the cluster, Kubelet updates the mounted files on disk within a minute **without restarting the container**.

---

## 🛠️ Real-Time Production Examples

---

### Step 1: Create the ConfigMap (`app-configmap.yaml`)
This ConfigMap stores a simple database URL variable and a complete custom config file.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-settings
  namespace: default
data:
  # 1. Simple key-value variables
  DB_HOST: "db.platform.internal"
  DB_PORT: "5432"
  LOG_LEVEL: "INFO"
  
  # 2. Entire configuration file block
  app-config.json: |
    {
      "cache": {
        "enabled": true,
        "ttl": 3600
      },
      "features": {
        "signup": true,
        "beta_search": false
      }
    }
```

---

### Step 2: Create the Secret (`app-secret.yaml`)
To register keys in a Secret, the values must be **Base64 encoded** in the YAML definition.

```bash
# How to encode strings on your terminal:
echo -n "super-secure-pg-password" | base64
# Output: c3VwZXItc2VjdXJlLXBnLXBhc3N3b3Jk

echo -n "prod-api-token-xyz123" | base64
# Output: cHJvZC1hcGktdG9rZW4teHl6MTIz
```

Write the values into the manifest:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-credentials
  namespace: default
type: Opaque # Standard generic secret type
data:
  DB_PASSWORD: c3VwZXItc2VjdXJlLXBnLXBhc3N3b3Jk # base64 encoded password
  API_KEY: cHJvZC1hcGktdG9rZW4teHl6MTIz         # base64 encoded token
```

---

### Step 3: Deploy the Pod consuming both (`app-deployment.yaml`)
This deployment demonstrates:
*   Loading variables as **Environment Variables** (from both ConfigMap & Secret).
*   Mounting the configuration file block as a **Volume Mount** on the filesystem.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-app
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      matchLabels:
        app: backend
    spec:
      containers:
      - name: application
        image: alpine:latest
        command: ["sh", "-c", "env && cat /etc/config/app-config.json && sleep 3600"]
        
        # 1. Inject as Environment Variables
        env:
        - name: DATABASE_HOST
          valueFrom:
            configMapKeyRef:
              name: app-settings
              key: DB_HOST
        - name: DATABASE_PORT
          valueFrom:
            configMapKeyRef:
              name: app-settings
              key: DB_PORT
        - name: DATABASE_PASSWORD
          valueFrom:
            keyRef:
              name: app-credentials
              key: DB_PASSWORD
              
        # 2. Mount file parameters as Volumes
        volumeMounts:
        - name: config-volume
          mountPath: /etc/config
          readOnly: true
      volumes:
      - name: config-volume
        configMap:
          name: app-settings
          items:
          - key: app-config.json
            path: app-config.json # Projected at /etc/config/app-config.json
```

---

## 🔎 Verification & Troubleshooting Commands

1.  **Read and inspect the resources**:
    ```bash
    # View ConfigMap details
    kubectl describe configmap app-settings
    
    # View Secret details (values will be redacted/hidden by default)
    kubectl get secret app-credentials -o yaml
    ```
2.  **Decode Secret values on command line**:
    If you have permission to read the secret, you can decode it using `jsonpath` and `base64`:
    ```bash
    kubectl get secret app-credentials -o jsonpath="{.data.DB_PASSWORD}" | base64 --decode
    # Returns: super-secure-pg-password
    ```
3.  **Confirm files are updated dynamically on disk**:
    If you update the ConfigMap `app-settings` key `app-config.json` using `kubectl edit configmap app-settings`, you can run a shell command in the container to check if it synced without restarting:
    ```bash
    kubectl exec -it <pod-name> -- cat /etc/config/app-config.json
    ```
    *(The sync loop takes around 10-60 seconds depending on the Kubelet sync period configurations).*

---

## 🔒 4. Production Standard: AWS Secrets Manager Integration (ESO Pattern)

In production environments, hardcoding Base64 secrets in Git is a security risk. Instead, you store sensitive values inside **AWS Secrets Manager** and use the **External Secrets Operator (ESO)** to fetch them dynamically at runtime and automatically generate the native Kubernetes Secret.

```
┌──────────────────────┐        1. Read JWT         ┌────────────────────────┐
│ External Secrets SA  ├───────────────────────────►│ IAM Role (via IRSA)    │
└──────────┬───────────┘                            └───────────┬────────────┘
           │                                                    │ 2. Assume Role &
           │ 3. Fetch Secret Values                             ▼    Get Secret
           │                                        ┌────────────────────────┐
           ▼                                        │ AWS Secrets Manager    │
┌──────────────────────┐                            └────────────────────────┘
│ ExternalSecrets      │
│ Controller           ├───────────────────────────► Creates Native K8s Secret
└──────────────────────┘                             (Reduces git leakage risk)
```

### Step 4a: Create the AWS Secret
1. Store your credentials in AWS Secrets Manager:
   * **Secret name**: `student/database/credentials`
   * **Keys**: `password = my-rds-secure-pw`, `apikey = my-production-token`

### Step 4b: Setup EKS IAM Trust (IRSA)
Create an IAM Policy with permissions to read the specific secret, and bind it to a Kubernetes ServiceAccount using IRSA:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:us-east-2:ACCOUNT_ID:secret:student/database/credentials-*"
    }
  ]
}
```

### Step 4c: Define the SecretStore (Connecting to AWS)
A `SecretStore` acts as a bridge between the Kubernetes namespace and your AWS backend, using the IAM Role-bound ServiceAccount:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secretsmanager-store
  namespace: default
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-2
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa # ServiceAccount linked with the IAM Role
```

### Step 4d: Define the ExternalSecret (The Generator)
The `ExternalSecret` manifest declares the keys you want to fetch and the name of the Kubernetes Secret you want ESO to create automatically:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials-sync
  namespace: default
spec:
  refreshInterval: 1h # Automatically poll AWS Secrets Manager for rotations every hour
  secretStoreRef:
    name: aws-secretsmanager-store
    kind: SecretStore
  target:
    name: app-credentials # Dynamic native Kubernetes Secret generated on-the-fly!
    creationPolicy: Owner
  data:
    - secretKey: DB_PASSWORD # Native K8s secret key
      remoteRef:
        key: student/database/credentials
        property: password   # Key in AWS JSON
    - secretKey: API_KEY     # Native K8s secret key
      remoteRef:
        key: student/database/credentials
        property: apikey     # Key in AWS JSON
```

### How it operates:
* When you apply this manifest, ESO connects to AWS Secrets Manager using the IAM role, pulls the raw values, Base64-encodes them, and **creates a native Kubernetes Secret** named `app-credentials` dynamically.
* If you rotate the password in AWS Secrets Manager, ESO automatically detects the change within the refresh interval (1 hour) and updates the native Kubernetes Secret on disk, completely eliminating manual secret maintenance!

---

## 🛠️ 5. EKS Addon Installation: How to Enable Secrets Manager access

To enable these integrations inside your EKS cluster, you must install the corresponding controller driver. You can choose between EKS Managed Addons or custom Helm installations:

### Option A: AWS Managed Addon (For CSI Driver)
AWS officially packages the **Secrets Store CSI Driver** as a managed EKS addon. This is the simplest way to install it as AWS manages upgrades and patches automatically.

*   **AWS CLI Installation**:
    ```bash
    aws eks create-addon \
      --cluster-name my-cluster \
      --addon-name aws-secrets-store-csi-driver \
      --region us-east-2
    ```
*   **Terraform Installation**:
    ```hcl
    resource "aws_eks_addon" "secrets_csi" {
      cluster_name = var.cluster_name
      addon_name   = "aws-secrets-store-csi-driver"
    }
    ```

### Option B: Helm / Manual Installation (For External Secrets Operator)
AWS does **not** host the External Secrets Operator (ESO) as a managed addon. If you prefer to use the ESO pattern (to dynamically generate native Kubernetes Secret resources), you must install it via Helm:

```bash
# 1. Register the repository
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# 2. Deploy the Operator with Custom Resource Definitions (CRDs) enabled
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true
```

