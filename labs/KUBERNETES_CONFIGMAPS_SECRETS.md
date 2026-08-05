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
