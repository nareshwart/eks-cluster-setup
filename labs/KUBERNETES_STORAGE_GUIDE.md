# Architectural Guide: Kubernetes Storage Abstractions

This document provides a conceptual and hands-on guide to Kubernetes storage abstractions. It covers the difference between ephemeral, host-bound, and persistent networked storage using `emptyDir`, `hostPath`, `PersistentVolume` (PV), `PersistentVolumeClaim` (PVC), and `StorageClass` (SC).

---

## 🗺️ Storage Abstractions Overview

```
Ephemereal (Bound to Pod lifecycle)
 └─► emptyDir  ──> Temporary scratch space / RAM cache (Node disk)

Host-Bound (Bound to specific Node lifecycle)
 └─► hostPath  ──> Host node filesystem directory (Unsafe for normal apps)

Networked Persistent Storage (Decoupled from Pod & Node lifecycle)
 ├─► StorageClass (SC)         ──> Blueprint / Dynamic Volume Provisioner (e.g., EBS CSI gp3)
 ├─► PersistentVolumeClaim (PVC) ──> Developer's request for storage (e.g., "Give me 10Gi gp3")
 └─► PersistentVolume (PV)     ──> Actual volume provisioned in AWS (bound to the PVC)
```

---

## 📊 Summary Comparison

| Storage Option | Lifecycle Bound To | Scope / Portability | Common Use Case |
| :--- | :--- | :--- | :--- |
| **`emptyDir`** | Pod | Local Node (ephemeral) | Temp scratchpad, log sharing, RAM cache |
| **`hostPath`** | Host Node | Single Node (non-portable) | FluentBit reading `/var/log` from node |
| **`PersistentVolume`** | Independent | Global (network-attached) | Physical disk allocated in AWS (EBS/EFS) |
| **`PersistentVolumeClaim`**| User Namespace | Portable request | Requesting database storage size & access |
| **`StorageClass`** | Global Cluster | Admin Blueprint | Defines gp3 provisioner settings & IOPS |

---

## 1. Ephemeral Local Storage: `emptyDir`

An `emptyDir` volume is created when a Pod is assigned to a Node, and exists as long as that Pod is running on that node. If the container crashes, the data is preserved; however, if the **Pod is deleted, evicted, or rescheduled**, all data in the `emptyDir` is **permanently lost**.

### Hands-on Example: Shared Log Scratchpad
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: log-processor-pod
spec:
  containers:
  - name: app-writer
    image: alpine
    command: ["/bin/sh", "-c", "while true; do echo $(date) 'App Log' >> /var/log/app.log; sleep 1; done"]
    volumeMounts:
    - name: shared-logs
      mountPath: /var/log
  - name: log-shipper
    image: alpine
    command: ["/bin/sh", "-c", "tail -f /var/log/app.log"]
    volumeMounts:
    - name: shared-logs
      mountPath: /var/log
  volumes:
  - name: shared-logs
    emptyDir: {} # Can optionally set medium: "Memory" to use RAM disk (tmpfs)
```

---

## 2. Node-Bound Storage: `hostPath`

A `hostPath` volume mounts a specific file or directory from the host node's filesystem directly into your Pod. 
*   **WARNING**: If your pod gets rescheduled to a different worker node, it will connect to a new empty directory on the new node, losing access to the previous node's files.
*   **Security Risk**: Pods running with `hostPath` can read or modify sensitive host OS configurations, posing a significant container breakout risk.

### Hands-on Example: Node Logger (DaemonSets)
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: node-log-viewer
spec:
  containers:
  - name: syslog-reader
    image: alpine
    command: ["tail", "-f", "/host/var/log/messages"]
    volumeMounts:
    - name: system-logs
      mountPath: /host/var/log
      readOnly: true
  volumes:
  - name: system-logs
    hostPath:
      path: /var/log # Location on the physical EC2 worker node
      type: Directory
```

---

## 3. Networked Persistent Storage: SC ──► PVC ──► PV

For databases (e.g. Postgres, MySQL) and stateful applications, storage must be **independent** of Pod and Node lifecycles. This is handled by a three-tiered decoupling design:

```
[ Developer ]                   [ Kubernetes Controller ]                 [ AWS Infrastructure ]
PersistentVolumeClaim (PVC)  ──►  StorageClass Dynamic Provisioner  ──►  PersistentVolume (PV) + AWS EBS Disk
(Requests 10Gi Storage)          (Reads blueprint & triggers AWS API)     (Volume is attached to pod node)
```

### 3a. StorageClass (The Blueprint)
Defines the backend storage type, provisioner driver (e.g. AWS EBS CSI), volume type (`gp3`), filesystem, and reclaiming policy.
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-gp3-sc
provisioner: ebs.csi.aws.com # AWS EBS CSI driver (installed during addons lab)
volumeBindingMode: WaitForFirstConsumer # Important: Delays volume creation until the Pod is placed in an AZ
allowVolumeExpansion: true
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
```

### 3b. PersistentVolumeClaim (The Request)
Developers create a PVC requesting storage parameters. They do not need to know AWS details; they simply reference the `StorageClass` name:
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: database-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce # RWO: Can only be mounted to 1 node at a time (standard EBS)
  resources:
    requests:
      storage: 10Gi
  storageClassName: ebs-gp3-sc # References the blueprint
```

### 3c. PersistentVolume (The Physical Resource)
When the PVC is created:
1.  The EBS CSI Controller detects the PVC.
2.  It calls the AWS API to provision a physical **10 GiB gp3 EBS Volume** in the correct Availability Zone.
3.  It automatically creates a **`PersistentVolume` (PV)** object in Kubernetes representing that EBS disk and binds it to your PVC.

### 3d. Mounting PVC in Pod
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: database-deploy
spec:
  replicas: 1
  selector:
    matchLabels:
      app: database
  template:
    metadata:
      matchLabels:
        app: database
    spec:
      containers:
      - name: postgres
        image: postgres:15
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: db-data
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: db-data
        persistentVolumeClaim:
          claimName: database-pvc # Binds to our claim
```

---

## 🧠 Access Modes Reference

Kubernetes Volumes support three primary access modes. Choose depending on your AWS volume backend:

*   **`ReadWriteOnce` (RWO)**: The volume can be mounted as read-write by a **single node** at a time. Ideal for block storage (**AWS EBS**).
*   **`ReadWriteMany` (RWX)**: The volume can be mounted as read-write by **many nodes** simultaneously. Ideal for shared filesystems (**AWS EFS**).
*   **`ReadOnlyMany` (ROX)**: The volume can be mounted as read-only by many nodes simultaneously. Good for static asset distribution.
