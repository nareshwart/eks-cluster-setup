# Lab Guide: Disaster Recovery with Velero (Backup & Restore)

This lab guide walks you through setting up **Velero**, the industry-standard tool for backing up, restoring, and migrating Kubernetes cluster resources and persistent volumes. You will simulate a disaster scenario by deleting an active namespace and recovering it completely from an AWS S3-stored backup.

---

## Overview

```
Step 1 → Provision S3 Bucket & IAM Permissions (IRSA)
Step 2 → Install Velero CLI and Helm Chart
Step 3 → Deploy a Sample Stateful Application (Persistent Volume)
Step 4 → Create a Backup with Velero
Step 5 → Simulate a Disaster (Accidental Deletion)
Step 6 → Restore and Verify Data Recovery
Step 7 → Production Best Practices
```

---

## Step 1 — Provision S3 Bucket & IAM Permissions (IRSA)

Velero stores cluster state metadata and volume snapshots in an AWS S3 bucket.

### 1a. Create the S3 Backup Bucket
Run the following commands to create a private S3 bucket (replace `student1` with your name to ensure global bucket uniqueness):

1. **Create the S3 bucket in us-east-2**:
```bash
aws s3api create-bucket \
  --bucket student1-velero-backups \
  --region us-east-2 \
  --create-bucket-configuration LocationConstraint=us-east-2
```

2. **Block all public access (Security Best Practice)**:
```bash
aws s3api put-public-access-block \
  --bucket student1-velero-backups \
  --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

### 1b. Create the IAM Policy for Velero
Create a policy that grants Velero permission to read/write from your S3 bucket and manage EC2 EBS volume snapshots:

1. **Generate the IAM policy document locally**:
```bash
cat <<EOF > velero-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeVolumes",
                "ec2:DescribeSnapshots",
                "ec2:CreateTags",
                "ec2:CreateVolume",
                "ec2:CreateSnapshot",
                "ec2:DeleteSnapshot"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::student1-velero-backups",
                "arn:aws:s3:::student1-velero-backups/*"
            ]
        }
    ]
}
EOF
```

2. **Create the policy in AWS**:
```bash
aws iam create-policy \
  --policy-name VeleroBackupPolicy-student1 \
  --policy-document file://velero-policy.json
```

### 1c. Create the IAM Service Account (IRSA)

Choose **one** of the following options to bind the IAM policy permissions to the Velero service account.

#### Option A: Create Automatically via `eksctl`
This is the fastest method. `eksctl` will create the IAM role, set up the OIDC trust relationship, and deploy the annotated Kubernetes ServiceAccount in a single step:

1. **Create Velero Namespace**:
```bash
kubectl create namespace velero
```

2. **Create ServiceAccount and associate the IAM Role**:
```bash
eksctl create iamserviceaccount \
  --cluster=student1 \
  --namespace=velero \
  --name=velero-server \
  --role-name=VeleroControllerRole-student1 \
  --attach-policy-arn=arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/VeleroBackupPolicy-student1 \
  --override-existing-serviceaccounts \
  --approve
```

---

#### Option B: Manual IAM Creation & YAML Manifest (Standard Kubernetes Method)
Use this option to understand how IAM OIDC trust relationships and Kubernetes service account annotations work under the hood.

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
              "${OIDC_PROVIDER}:sub": "system:serviceaccount:velero:velero-server",
              "${OIDC_PROVIDER}:aud": "sts.amazonaws.com"
            }
          }
        }
      ]
    }
    EOF
    ```

3.  **Create the IAM Role**:
    ```bash
    aws iam create-role \
      --role-name VeleroControllerRole-student1 \
      --assume-role-policy-document file://trust-policy.json
    ```

4.  **Attach the Velero backup policy to the role**:
    ```bash
    aws iam attach-role-policy \
      --role-name VeleroControllerRole-student1 \
      --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/VeleroBackupPolicy-student1
    ```

5.  **Create the Namespace**:
    ```bash
    kubectl create namespace velero
    ```

6.  **Create the ServiceAccount YAML file (`velero-sa.yaml`)**:
    Create a file named `velero-sa.yaml` with the following content (replace `${ACCOUNT_ID}` with your actual AWS Account ID):
    ```yaml
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: velero-server
      namespace: velero
      annotations:
        eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/VeleroControllerRole-student1
    ```

7.  **Apply the manifest**:
    ```bash
    kubectl apply -f velero-sa.yaml
    ```

---

## Step 2 — Install Velero CLI and Helm Chart

### 2a. Install Velero CLI
Install the Velero CLI tool on your jumpbox (macOS/Linux):

```bash
# Download the latest release
curl -L -o velero.tar.gz https://github.com/vmware-tanzu/velero/releases/download/v1.13.0/velero-v1.13.0-linux-amd64.tar.gz
tar -xvf velero.tar.gz
sudo mv velero-v1.13.0-linux-amd64/velero /usr/local/bin/
velero version --client-only
```

### 2b. Install Velero Server using Helm
Use Helm to install Velero with the AWS provider plugin enabled:

```bash
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update

helm install velero vmware-tanzu/velero \
  --namespace velero \
  --set configuration.backupStorageLocation[0].name=aws \
  --set configuration.backupStorageLocation[0].provider=aws \
  --set configuration.backupStorageLocation[0].bucket=<use-your-bucket-name> \
  --set configuration.backupStorageLocation[0].config.region=us-east-2 \
  --set configuration.volumeSnapshotLocation[0].name=aws \
  --set configuration.volumeSnapshotLocation[0].provider=aws \
  --set configuration.volumeSnapshotLocation[0].config.region=us-east-2 \
  --set initContainers[0].name=velero-plugin-for-aws \
  --set initContainers[0].image=velero/velero-plugin-for-aws:v1.9.0 \
  --set initContainers[0].volumeMounts[0].mountPath=/target \
  --set initContainers[0].volumeMounts[0].name=plugins \
  --set serviceAccount.server.create=false \
  --set serviceAccount.server.name=velero-server \
  --set snapshotsEnabled=true \
  --set credentials.useSecret=false \
  --set deployNodeAgent=false
```

Verify that the Velero pods are active:
```bash
kubectl get pods -n velero
```

---

## Step 3 — Deploy a Sample Stateful Application

To demonstrate data restoration, we will deploy a stateful application that requests a Persistent Volume (EBS volume) and writes a data file to it.

1.  Create a namespace for the demo application:
    ```bash
    kubectl create namespace demo-app
    ```

2.  Apply the following YAML to create a PersistentVolumeClaim, a Deployment, and a script that periodically writes to the volume:
    ```yaml
    cat <<EOF | kubectl apply -f -
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: demo-pvc
      namespace: demo-app
    spec:
      accessModes:
        - ReadWriteOnce
      storageClassName: gp3
      resources:
        requests:
          storage: 2Gi
    ---
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: demo-writer
      namespace: demo-app
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: writer
      template:
        metadata:
          matchLabels:
            app: writer
        spec:
          containers:
          - name: writer
            image: alpine
            command: ["/bin/sh", "-c"]
            args:
              - |
                echo "=== Backup Demo Session Starting ===" > /data/backup-token.txt;
                while true; do
                  date >> /data/backup-token.txt;
                  sleep 5;
                done
            volumeMounts:
            - name: storage
              mountPath: /data
          volumes:
          - name: storage
            persistentVolumeClaim:
              claimName: demo-pvc
    EOF
    ```

3.  Wait for the pod to become healthy and check that data is being written:
    ```bash
    kubectl get pvc -n demo-app
    # View the contents of the volume inside the container
    kubectl exec -n demo-app -it deployments/demo-writer -- cat /data/backup-token.txt
    ```

---

## Step 4 — Create a Backup with Velero

We will trigger a backup of the entire `demo-app` namespace, including all Kubernetes API resources (deployments, pods, secrets, configuration) and the underlying EBS volume data using CSI Snapshots.

1.  Create the backup:
    ```bash
    velero backup create demo-app-backup --include-namespaces demo-app
    ```

2.  Describe the backup and wait for the status to show `Completed`:
    ```bash
    velero backup describe demo-app-backup
    # Or query status list
    velero backup get
    ```

3.  Verify the backup file is present in your S3 bucket:
    ```bash
    aws s3 ls s3://student1-velero-backups/backups/demo-app-backup/
    ```

---

## Step 5 — Simulate a Disaster (Accidental Deletion)

We will now simulate a disaster scenario by completely purging the application namespace and the corresponding Persistent Volume Claim:

```bash
# Purge the application namespace
kubectl delete namespace demo-app
```

Verify that all resources, pods, and volumes have been removed:
```bash
kubectl get all -n demo-app
kubectl get pvc -n demo-app
```
*(In the AWS Console, you will see the EBS volume associated with this PVC being deleted automatically)*.

---

## Step 6 — Restore and Verify Data Recovery

We will now use Velero to restore the deleted application using the metadata and volume snapshots stored on S3.

1.  Trigger the restore operation:
    ```bash
    velero restore create --from-backup demo-app-backup
    ```

2.  Check the status of the restore:
    ```bash
    velero restore get
    velero restore describe <restore-name-returned-above>
    ```

3.  Verify that the namespace, deployment, and PV have been recreated successfully:
    ```bash
    kubectl get all -n demo-app
    kubectl get pvc -n demo-app
    ```

4.  **Confirm Data Integrity**: Inspect the content of `/data/backup-token.txt` inside the container. It should show the exact timestamp history matching your session from before the deletion:
    ```bash
    kubectl exec -n demo-app -it deployments/demo-writer -- cat /data/backup-token.txt
    ```

---

## Step 7 — Production Best Practices

*   **Implement Backup Storage Policies**: Enable Object Lock (WORM - Write Once, Read Many) and Versioning on your S3 bucket to protect backups from ransomware attacks or accidental deletion.
*   **Use Scheduled Backups**: Never rely solely on manual triggers. Set up automatic schedules with retention rules:
    ```bash
    # Create a daily backup schedule retained for 30 days
    velero schedule create daily-backup --schedule="0 1 * * *" --ttl 720h0m0s
    ```
*   **Filter Backups**: Use label selectors to categorize applications and keep backup file sizes low:
    ```bash
    velero backup create prod-db-backup --selector app=database
    ```
*   **Test Restores Regularly**: A backup is only as good as its restore. Schedule quarterly automated restore test runs inside an isolated dev namespace or staging cluster.

---

## Practice Exercises: Velero CLI Commands

Hone your skills by practicing these essential Velero CLI operations. Try to complete the actions below and verify the results.

### Exercise 1: Advanced Backup Filtering and Exclusions
By default, Velero backs up everything in the specified namespace. Practice filtering backups using tags and exclusions:

1. **Backup by Label Selector**:
   Only back up resources labeled with `app=writer` in the `demo-app` namespace:
   ```bash
   velero backup create writer-only-backup \
     --include-namespaces demo-app \
     --selector app=writer
   ```
2. **Exclude Specific Resources**:
   Back up the entire `demo-app` namespace but exclude PersistentVolumeClaims (PVCs):
   ```bash
   velero backup create no-pvc-backup \
     --include-namespaces demo-app \
     --exclude-resources persistentvolumeclaims,persistentvolumes
   ```
3. **Backup All Namespaces Except System Namespaces**:
   Back up your entire cluster but exclude system namespaces:
   ```bash
   velero backup create cluster-backup-exclude-system \
     --exclude-namespaces kube-system,kube-public,kube-node-lease,velero
   ```

### Exercise 2: Backup TTL (Time-To-Live) and Retention
To prevent S3 storage costs from ballooning, practice specifying how long a backup should persist before Velero automatically deletes it.

1. **Create a short-lived backup (valid for 2 hours)**:
   ```bash
   velero backup create temp-backup \
     --include-namespaces demo-app \
     --ttl 2h0m0s
   ```
2. **Verify the Expiration date**:
   ```bash
   velero backup describe temp-backup
   ```
   *(Look for the `Expiration:` field in the CLI output)*.

### Exercise 3: Namespace Remapping during Restore
One of Velero's most powerful features is the ability to restore backups to a completely different namespace. This is incredibly useful for testing or staging copies.

1. **Restore `demo-app-backup` into a new namespace `demo-app-staging`**:
   ```bash
   velero restore create staging-restore \
     --from-backup demo-app-backup \
     --namespace-mappings demo-app:demo-app-staging
   ```
2. **Monitor the restore progress**:
   ```bash
   velero restore describe staging-restore
   ```
3. **Verify the new namespace**:
   ```bash
   kubectl get all -n demo-app-staging
   ```
4. **Cleanup the staging restore**:
   ```bash
   kubectl delete namespace demo-app-staging
   # Delete the restore metadata from Velero
   velero restore delete staging-restore --confirm
   ```

### Exercise 4: Schedule Operations
Practice creating and managing scheduled backups.

1. **Create a Cron schedule** to back up `demo-app` every 15 minutes:
   ```bash
   velero schedule create demo-app-15min \
     --schedule="*/15 * * * *" \
     --include-namespaces demo-app \
     --ttl 1h0m0s
   ```
2. **List all schedules**:
   ```bash
   velero schedule get
   ```
3. **Manually trigger a backup immediately from an existing schedule**:
   ```bash
   velero backup create --from-schedule demo-app-15min
   ```
4. **Delete the schedule**:
   ```bash
   velero schedule delete demo-app-15min --confirm
   ```

### Exercise 5: Troubleshooting and Diagnostics
Learn how to check for errors and inspect backups when something goes wrong.

1. **Retrieve detailed logs for a backup**:
   ```bash
   velero backup logs demo-app-backup
   ```
2. **Retrieve logs for a restore operation**:
   ```bash
   velero restore logs <restore-name>
   ```
3. **Delete a backup and its associated S3 files**:
   ```bash
   velero backup delete demo-app-backup --confirm
   ```

