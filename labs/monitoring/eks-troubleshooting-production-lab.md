# Troubleshooting Production EKS Clusters

## The Kubernetes Debugging Toolkit

When troubleshooting workloads, your primary commands will be:
- `kubectl get pods`: Provides a high-level status of your workloads.
- `kubectl describe pod <pod-name>`: Shows detailed lifecycle events, resource limits, and container states.
- `kubectl logs <pod-name>`: Displays the standard output (stdout) and standard error (stderr) streams of the container.
- `kubectl get events --sort-by='.metadata.creationTimestamp'`: Lists cluster-wide events chronologically.

---

## Scenario 1 — ImagePullBackOff / ErrImagePull

### 1a. Deploy the broken workload
Deploy a pod that references a non-existent image version:

```yaml
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: web-server-scenario1
  namespace: default
spec:
  containers:
  - name: nginx
    image: nginx:1.25-alpineee # Typo in the image tag
    ports:
    - containerPort: 80
EOF
```

### 1b. Diagnose the issue
1. Check the pod status:
   ```bash
   kubectl get pod web-server-scenario1
   ```
   *Expected Status: `ErrImagePull` or `ImagePullBackOff`.*

2. Describe the pod to find the root cause:
   ```bash
   kubectl describe pod web-server-scenario1
   ```
   Scroll down to the **Events** section at the bottom. You should see an event similar to:
   > `Failed to pull image "nginx:1.25-alpineee": rpc error: code = NotFound desc = failed to resolve image ...`

### 1c. Resolve the issue
Edit the pod manifest to point to a valid image tag (`nginx:1.25-alpine`) and redeploy:
```bash
# Delete the broken pod
kubectl delete pod web-server-scenario1

# Re-apply with the correct image
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: web-server-scenario1
  namespace: default
spec:
  containers:
  - name: nginx
    image: nginx:1.25-alpine
    ports:
    - containerPort: 80
EOF
```
Verify the pod transitions to `Running`.

---

## Scenario 2 — CrashLoopBackOff

A pod enters `CrashLoopBackOff` when the container starts up, but exits or crashes repeatedly. Kubernetes back-off delays restart attempts to save CPU cycles.

### 2a. Deploy the broken workload
Deploy a pod whose startup command fails immediately:

```yaml
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: app-runner-scenario2
  namespace: default
spec:
  containers:
  - name: app
    image: alpine
    command: ["sh", "-c", "echo 'Booting up application...'; sleep 5; exit 1"]
EOF
```

### 2b. Diagnose the issue
1. List the pods to check the status:
   ```bash
   kubectl get pod app-runner-scenario2
   ```
   *Expected Status: `CrashLoopBackOff` (or `Error` temporarily, with a high restart count).*

2. Since the container actually started, check the container logs:
   ```bash
   kubectl logs app-runner-scenario2
   ```
   *Output: `Booting up application...` (indicating the script started but exited).*

3. Describe the pod to inspect the exit code:
   ```bash
   kubectl describe pod app-runner-scenario2
   ```
   Look under the **Containers -> app -> Last State** field:
   - **Reason**: Error
   - **Exit Code**: 1 (Indicates a general script failure or abnormal termination)

### 2c. Resolve the issue
Change the script to exit successfully (Exit Code 0) or block indefinitely to keep the service running:
```bash
kubectl delete pod app-runner-scenario2

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: app-runner-scenario2
  namespace: default
spec:
  containers:
  - name: app
    image: alpine
    command: ["sh", "-c", "echo 'Booting up application...'; exec sleep 3600"]
EOF
```
Verify the pod stays in the `Running` state without restarts.

---

## Scenario 3 — OOMKilled (Exit Code 137)

The Out-Of-Memory (OOM) Killer is a Linux kernel mechanism that terminates processes to save system memory. In Kubernetes, this happens when a container exceeds its defined memory `limits`.

### 3a. Deploy the broken workload
Deploy a pod with a very low memory limit (50Mi) and a memory-consuming workload:

```yaml
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: memory-consumer-scenario3
  namespace: default
spec:
  containers:
  - name: stress-test
    image: polinux/stress
    command: ["stress"]
    args: ["--vm", "1", "--vm-bytes", "150M", "--vm-hang", "1"]
    resources:
      limits:
        memory: "50Mi" # Limit is too low for the 150M workload
EOF
```

### 3b. Diagnose the issue
1. Wait a few seconds and check the pod status:
   ```bash
   kubectl get pod memory-consumer-scenario3
   ```
   *Expected Status: `OOMKilled` or `CrashLoopBackOff`.*

2. Describe the pod to find the termination details:
   ```bash
   kubectl describe pod memory-consumer-scenario3
   ```
   Look at the **Last State** section:
   - **Reason**: OOMKilled
   - **Exit Code**: 137 (This code is specific to SIGKILL, commonly triggered by the Linux OOM Killer)

### 3c. Resolve the issue
Increase the container's memory limit to accommodate the workload:
```bash
kubectl delete pod memory-consumer-scenario3

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: memory-consumer-scenario3
  namespace: default
spec:
  containers:
  - name: stress-test
    image: polinux/stress
    command: ["stress"]
    args: ["--vm", "1", "--vm-bytes", "150M", "--vm-hang", "1"]
    resources:
      requests:
        memory: "150Mi"
      limits:
        memory: "250Mi" # Correctly sized limit
EOF
```
Verify the pod transitions to `Running` and remains stable.

---

## Scenario 4 — Pod stuck in Pending (Unschedulable)

A pod remains in `Pending` state when the Kubernetes scheduler cannot find a node that matches the pod's constraints (resource requirements, node selectors, taints/tolerations).

### 4a. Deploy the broken workload
Deploy a deployment requesting an impossible amount of CPU capacity (e.g. 100 vCPU cores):

```yaml
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: heavy-deployment-scenario4
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: heavy-workload
  template:
    metadata:
      matchLabels:
        app: heavy-workload
    spec:
      containers:
      - name: db
        image: redis
        resources:
          requests:
            cpu: "100" # Requires 100 CPU cores
EOF
```

### 4b. Diagnose the issue
1. Check the pod status:
   ```bash
   kubectl get pods -l app=heavy-workload
   ```
   *Expected Status: `Pending`.*

2. Describe the pending pod:
   ```bash
   kubectl describe pod -l app=heavy-workload
   ```
   Look at the **Events** section:
   > `Warning  FailedScheduling  default-scheduler  0/3 nodes are available: 3 Insufficient cpu.`

### 4c. Resolve the issue
Modify the resource requests to match realistic node limits (e.g., `100m` or 0.1 CPU core):
```bash
kubectl edit deployment heavy-deployment-scenario4
```
Locate the `resources.requests.cpu` block, change `"100"` to `"100m"`, save, and exit.

Or redeploy using:
```bash
kubectl scale deployment heavy-deployment-scenario4 --replicas=0
kubectl delete deployment heavy-deployment-scenario4

cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: heavy-deployment-scenario4
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: heavy-workload
  template:
    metadata:
      matchLabels:
        app: heavy-workload
    spec:
      containers:
      - name: db
        image: redis
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
EOF
```
Verify the pod successfully schedules and enters the `Running` state.

---

## Scenario 5 — Node Disk Pressure & Pod Eviction

When a node runs low on disk space (typically >85% root disk utilization), the kubelet marks the node status with the `DiskPressure` taint and starts evicting lower-priority pods to preserve node operating system integrity.

### 5a. Diagnose Node Pressure
If workloads suddenly stop running or exit with `Evicted` status:

1. **Check Node Conditions**:
   ```bash
   kubectl get nodes
   ```
   Look under the `STATUS` column. If a node is under pressure, it will list conditions. To see detailed conditions:
   ```bash
   kubectl describe node <node-name>
   ```
   Look under the **Conditions** block for `DiskPressure` or `MemoryPressure` set to `True`.

2. **Locate Evicted Pods**:
   ```bash
   kubectl get pods --all-namespaces | grep Evicted
   ```

### 5b. Resolution Steps for Disk Pressure
To recover from node disk pressure, administrators follow these steps:

1. **Identify space-hogging containers**:
   Check EKS node system storage. Connect to the node via SSM Session Manager or SSH and inspect directory sizes:
   ```bash
   df -h
   sudo du -sh /var/lib/docker/* # For Docker runtime
   # Or for containerd:
   sudo du -sh /var/lib/containerd/*
   ```

2. **Run Kubelet Garbage Collection**:
   The `kubelet` automatically attempts to garbage-collect unused container images and stopped containers when threshold limits are breached. You can trigger manual cleanup of unused Docker images if needed:
   ```bash
   docker image prune -a
   # Or for containerd/crictl:
   sudo crictl rmi --prune
   ```

3. **Delete Evicted Pod Metadata**:
   Once disk pressure is resolved, clear out the dead evicted pod records:
   ```bash
   kubectl get pods --all-namespaces --no-headers | grep Evicted | awk '{print $2 " --namespace=" $1}' | xargs -I {} sh -c 'kubectl delete pod {}'
   ```

---

## Scenario 6 — Service Connection Failure (Empty Endpoints / Selector Misalignment)

A common developer issue is when an application is successfully `Running`, but internal curl requests to the service name or IP address fail with connection timeouts or connection refused errors.

### 6a. Deploy the broken workload
Deploy a backend deployment and a Service that has a typo in its selector labels:
```yaml
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-app-scenario6
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend-scenario6
  template:
    metadata:
      labels:
        app: backend-scenario6
    spec:
      containers:
      - name: web
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: backend-service-scenario6
  namespace: default
spec:
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: backend-scen6 # Typo: mismatch with pod label "backend-scenario6"
EOF
```

### 6b. Diagnose the issue
1. Deploy a temporary debugging shell and attempt to query the backend service:
   ```bash
   kubectl run curl-test --image=curlimages/curl -it --rm --restart=Never -- curl -m 5 http://backend-service-scenario6
   ```
   *Expected Output: `curl: (28) Connection timed out` (or similar failure).*

2. Inspect the service configuration and endpoints list:
   ```bash
   kubectl get endpoints backend-service-scenario6
   ```
   *Expected Output: Under `ENDPOINTS`, you will see `<none>` or an empty list, indicating the service is not routing traffic to any pods.*

3. Describe the service to check its selector:
   ```bash
   kubectl describe svc backend-service-scenario6
   ```
   Check the `Selector` field. It shows `app=backend-scen6`.

4. Check the labels of your running pods:
   ```bash
   kubectl get pods --show-labels -l app=backend-scenario6
   ```
   Compare the label `app=backend-scenario6` against the Service selector `app=backend-scen6`. Notice the mismatch.

### 6c. Resolve the issue
Update the Service's selector to match the Pod's labels:
```bash
# Patch the service selector directly
kubectl patch svc backend-service-scenario6 -p '{"spec":{"selector":{"app":"backend-scenario6"}}}'
```
Verify the endpoints are now populated:
```bash
kubectl get endpoints backend-service-scenario6
```
Ensure the `ENDPOINTS` column lists the IP of the backend pod. Re-run the curl test to verify successful connectivity.

---

## Scenario 7 — EKS IRSA Permission Denied (AWS Credentials/IAM Failures)

When running applications on EKS, developers use IAM Roles for Service Accounts (IRSA) to grant pods access to AWS resources. If misconfigured, applications fail with `Access Denied` or security credential errors.

### 7a. Deploy the broken workload
Deploy a ServiceAccount and a pod that attempts to list S3 buckets using the AWS CLI:
```yaml
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: s3-reader-sa-scenario7
  namespace: default
  # Missing the mandatory annotation linking it to the AWS IAM Role
---
apiVersion: v1
kind: Pod
metadata:
  name: s3-client-scenario7
  namespace: default
spec:
  serviceAccountName: s3-reader-sa-scenario7
  containers:
  - name: aws-cli
    image: amazon/aws-cli:latest
    command: ["aws", "s3", "ls"]
  restartPolicy: Never
EOF
```

### 7b. Diagnose the issue
1. View the pod logs to inspect the error:
   ```bash
   kubectl logs s3-client-scenario7
   ```
   *Expected Output: `Unable to locate credentials. You can configure credentials by running "aws configure".` (indicating the AWS SDK/CLI did not find any IAM role credentials).*

2. Describe the pod and inspect the injected environments:
   ```bash
   kubectl describe pod s3-client-scenario7
   ```
   Look for the `Environment` section. Notice that `AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE` variables are **missing**. On EKS, these are injected automatically by the EKS Pod Identity Webhook *only* if the ServiceAccount has the correct annotation.

3. Describe the ServiceAccount:
   ```bash
   kubectl describe sa s3-reader-sa-scenario7
   ```
   Notice that the `Annotations` field is empty or missing `eks.amazonaws.com/role-arn`.

### 7c. Resolve the issue
To fix this, the ServiceAccount must be annotated with the ARN of a valid AWS IAM Role that trusts the cluster's OIDC provider.
*(Note: Replace `<IAM_ROLE_ARN>` with your actual training IAM Role ARN if testing locally).*
```bash
# Add the required EKS IRSA annotation to the ServiceAccount
kubectl annotate sa s3-reader-sa-scenario7 eks.amazonaws.com/role-arn="arn:aws:iam::123456789012:role/eks-s3-readonly-role" --overwrite

# Pods must be recreated to inherit the new credentials:
kubectl delete pod s3-client-scenario7

# Re-deploy the pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: s3-client-scenario7
  namespace: default
spec:
  serviceAccountName: s3-reader-sa-scenario7
  containers:
  - name: aws-cli
    image: amazon/aws-cli:latest
    command: ["aws", "s3", "ls"]
  restartPolicy: Never
EOF
```
Verify the pod environment:
- Run `kubectl describe pod s3-client-scenario7` and verify `AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE` are now populated.
- Check `kubectl logs s3-client-scenario7` to see the S3 bucket list (or AWS authorization output).

---

## Troubleshooting Cheat Sheet

| Kubernetes Pod Status / Error | Common Causes | Diagnostic Commands | Primary Resolution |
|---|---|---|---|
| **ImagePullBackOff** | Typo in image name; private registry credentials missing/expired | `kubectl describe pod` | Correct the tag; create/verify image pull secret |
| **CrashLoopBackOff** | Misconfigured entrypoint; command errors; missing environment vars | `kubectl logs`, `kubectl describe pod` | Inspect application logs; adjust environment configs |
| **OOMKilled (Exit Code 137)** | Memory usage exceeded the limit defined in the resource quota | `kubectl describe pod` | Increase the memory `limit` in YAML |
| **Pending** | Insufficient CPU/Memory; Node selectors or taints do not match nodes | `kubectl describe pod` | Resize requests; configure autoscaler or correct selectors |
| **Evicted** | Node disk or memory capacity exhausted | `kubectl get events`, `kubectl describe node` | Clean up node host storage; optimize container resource requests |
| **Empty Endpoints** | Service selector labels mismatch Pod labels; Port mismatch | `kubectl get endpoints`, `kubectl describe svc` | Align Service selector labels with Pod labels; fix targetPort |
| **IAM AccessDenied** | ServiceAccount missing annotation; OIDC Trust Policy misconfigured | `kubectl describe sa`, `kubectl logs` | Annotate ServiceAccount with AWS Role ARN; update trust policy |

