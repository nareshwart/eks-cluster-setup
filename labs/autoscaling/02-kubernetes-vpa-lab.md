# Vertical Pod Autoscaler (VPA) Lab Guide

This lab guide explains how the Kubernetes **Vertical Pod Autoscaler (VPA)** automatically adjusts the CPU and memory requests and limits for pods. 

Unlike the Horizontal Pod Autoscaler (HPA), which adds or removes pod replicas, VPA scales resources **vertically** for existing pods. This is particularly useful for stateful services or applications that cannot scale out horizontally.

```
       HPA (Horizontal)                     VPA (Vertical)
      Add/Remove Replicas               Resize CPU/Memory Requests
      
         [Pod] [Pod]                         [  New Pod  ]
              ^                              [ 2x CPU/RAM]
              |                                    ^
        +------------+                             |
   <--- | Deployment | --->                  +------------+
        +------------+                       | Deployment |
              ^                              +------------+
              |                                    ^
            [Pod]                                  |
                                                 [Pod]
```

---

## VPA Modes of Operation

VPA can run in three different modes:
1.  **`Off`**: VPA only calculates and recommends resource values. It does not modify pod specifications or restart running pods. (Highly recommended for production profiling).
2.  **`Initial`**: VPA assigns resource requests at pod creation time but never restarts running pods to adjust resources.
3.  **`Auto`**: VPA assigns resource requests at pod creation time and actively evicts (restarts) running pods if their resources need to be updated.

---

## VPA Kubernetes Version Support & Compatibility

The Vertical Pod Autoscaler is maintained in the `kubernetes/autoscaler` repository. Its controller releases are version-locked and tested against specific Kubernetes minor versions to ensure CRD and webhook compatibility.

Always use the VPA release branch that matches your cluster's Kubernetes version:

| Kubernetes Version | EKS Support | VPA Release Branch |
| :--- | :--- | :--- |
| **Kubernetes 1.33+** | Active / Dev | `vpa-release-1.4` |
| **Kubernetes 1.32** | Active / Dev | `vpa-release-1.3` |
| **Kubernetes 1.31** | Active | `vpa-release-1.2` |
| **Kubernetes 1.30** | Active | `vpa-release-1.1` |
| **Kubernetes 1.29** | Active | `vpa-release-1.0` |
| **Kubernetes 1.28** | Active | `vpa-release-0.13` |
| **Kubernetes 1.27** | Active | `vpa-release-0.12` |
| **Kubernetes 1.25 - 1.26** | EOL | `vpa-release-0.11` |

---

## Prerequisites

*   A working EKS/Kubernetes cluster.
*   The **Metrics Server** add-on installed and running:
    ```bash
    kubectl get deployment metrics-server -n kube-system
    ```
*   `git` installed on your master node to clone the VPA controller repository.

---

## Step 1 — Install the VPA Controller

Unlike HPA, the VPA controllers are not installed by default in EKS. You must install the official Kubernetes Autoscaler VPA components.

### 1a. Clone the Kubernetes Autoscaler Repository:
Determine your EKS cluster version (using `kubectl version`) and clone the corresponding VPA release branch (for example, using `vpa-release-1.1` for EKS 1.30):

```bash
cd /tmp
# Replace 'vpa-release-1.1' with your cluster's corresponding version branch
git clone -b vpa-release-1.1 https://github.com/kubernetes/autoscaler.git
cd autoscaler/vertical-pod-autoscaler/
```

### 1b. Install VPA CRDs and Controllers:
Execute the installation script. This script generates self-signed certificates for the VPA admission webhook and deploys the components:
```bash
./hack/vpa-up.sh
```

### 1c. Verify the installation:
Check that the VPA pods are running in the `kube-system` namespace:
```bash
kubectl get pods -n kube-system | grep vpa
```
**Expected Output**:
You should see three running pods:
*   `vpa-recommender-*`: Monitors resource utilization and calculates recommendations.
*   `vpa-updater-*`: Evicts pods that need resource updates (used in `Auto` mode).
*   `vpa-admission-controller-*`: Intercepts pod creation requests to inject recommended values.

---

## Step 2 — Deploy a Test Application

We will deploy a CPU-bound application (known as the "hamster" app). It starts with tiny resource requests (`10m` CPU and `10Mi` RAM) but actively consumes much more, forcing the VPA to make recommendations.

### 2a. Deploy the hamster application:
Apply the deployment manifest:
```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hamster
  namespace: default
spec:
  selector:
    matchLabels:
      app: hamster
  replicas: 2
  template:
    metadata:
      labels:
        app: hamster
    spec:
      containers:
      - name: hamster
        image: registry.k8s.io/ubuntu-slim:0.14
        resources:
          requests:
            cpu: 10m
            memory: 10Mi
        command: ["/bin/sh"]
        args:
        - "-c"
        - "while true; do timeout 0.5s yes >/dev/null; sleep 0.5s; done"
EOF
```

### 2b. Verify the pods are running:
```bash
kubectl get pods -l app=hamster
```

---

## Step 3 — Create VPA in Recommendation Mode (`Off`)

We will configure the VPA in `Off` mode. This profiles the application and computes recommendations without disrupting the running pods.

### 3a. Create the VPA resource:
Apply the VPA configuration targeting the `hamster` deployment:
```bash
cat <<EOF | kubectl apply -f -
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: hamster-vpa
  namespace: default
spec:
  targetRef:
    apiVersion: "apps/v1"
    kind: Deployment
    name: hamster
  updatePolicy:
    updateMode: "Off"   # <-- Recommendation-only mode
EOF
```

### 3b. Wait for metrics gathering:
The VPA Recommender needs about **1 to 2 minutes** to collect usage metrics from the Metrics Server before it displays recommendations.

---

## Step 4 — Observe VPA Recommendations

Once metrics have accumulated, inspect the VPA object to view recommended CPU and memory settings.

### 4a. Describe the VPA resource:
```bash
kubectl describe vpa hamster-vpa
```

Look at the **`Status.Recommendation`** block at the bottom of the output:
```yaml
Status:
  Recommendation:
    Container Recommendations:
      Container Name:  hamster
      Lower Bound:
        Cpu:     25m
        Memory:  26214400
      Target:
        Cpu:     58m
        Memory:  26214400
      Uncapped Target:
        Cpu:     58m
        Memory:  26214400
      Upper Bound:
        Cpu:     102m
        Memory:  26214400
```

### Understanding VPA recommendation metrics:
*   **`Target`**: The recommended resource request. This is the value VPA will inject if auto-scaling is enabled.
*   **`Lower Bound`**: If a pod's current request is below this minimum value, the VPA will trigger a restart to scale it up.
*   **`Upper Bound`**: If a pod's request is above this maximum value, the VPA will trigger a restart to scale it down.
*   **`Uncapped Target`**: The recommended target ignoring any min/max constraints specified in the VPA configuration.

---

## Step 5 — Enable Automatic Vertical Scaling (`Auto`)

Now, we will change the VPA mode to `Auto`. VPA will detect that the hamster pods are under-provisioned (running with `10m` CPU instead of the recommended target `~50m+`) and restart the pods to inject the updated resource requests.

### 5a. Update VPA to Auto Mode:
Change the `updateMode` to `"Auto"` and apply:
```bash
cat <<EOF | kubectl apply -f -
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: hamster-vpa
  namespace: default
spec:
  targetRef:
    apiVersion: "apps/v1"
    kind: Deployment
    name: hamster
  updatePolicy:
    updateMode: "Auto"   # <-- Automatic eviction/injection mode
EOF
```

### 5b. Watch the Pod restarts:
Monitor your pods. Within 30 seconds, you should see the VPA Updater evict the existing hamster pods and the ReplicaSet spawn new ones:
```bash
kubectl get pods -l app=hamster -w
```
*Observe that pods are terminated and new pods start in their place.*

### 5c. Verify the new pod's resources:
Inspect the YAML configuration of one of the newly spawned pods:
```bash
kubectl get pod -l app=hamster -o yaml | grep -A 5 resources
```

**Expected Result**:
You should see that the pod's `resources.requests` values have been updated automatically from the original `10m` / `10Mi` to the VPA's recommended `Target` (e.g. `~58m` CPU and `25Mi` RAM):

```yaml
    resources:
      requests:
        cpu: 58m
        memory: 26214400
```
*(Notice that the original Deployment manifest was not modified; the VPA Admission Controller intercepted the pod creation request and injected the updated values on-the-fly).*

---

## Step 6 — Clean Up Everything

To clean up all resources created in this lab and uninstall the VPA controller:

### 6a. Delete the test app and VPA config:
```bash
kubectl delete vpa hamster-vpa
kubectl delete deployment hamster
```

### 6b. Uninstall the VPA controller:
```bash
cd /tmp/autoscaler/vertical-pod-autoscaler/
./hack/vpa-down.sh
rm -rf /tmp/autoscaler
```
