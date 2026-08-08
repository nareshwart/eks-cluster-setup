# Architectural Guide & Lab: Kubernetes Probes

This document provides a conceptual overview and hands-on laboratory exercises explaining **Kubernetes Probes** (Startup, Liveness, and Readiness). You will learn how to configure them and verify their behavior in real-time.

---

## 🗺️ The Three Types of Probes

Kubernetes uses three distinct probes to manage container health and traffic routing:

```
                  ┌──────────────────────────────┐
                  │          Pod Created         │
                  └──────────────┬───────────────┘
                                 ▼
                  ┌──────────────────────────────┐
                  │        Startup Probe         │ ◄─── Blocks other probes
                  └──────────────┬───────────────┘      during slow app boot
                                 ▼ Success
                  ┌──────────────────────────────┐
                  │      Container Running       │
                  └──────┬───────────────┬───────┘
                         │               │
                         ▼               ▼
      ┌─────────────────────┐   ┌─────────────────────┐
      │   Readiness Probe   │   │   Liveness Probe    │
      └──────────┬──────────┘   └──────────┬──────────┘
                 │                         │
      Fails ──► Removes Pod     Fails ──► Restarts
                from Service               Container
```

### 1. Startup Probe
*   **Purpose**: Determines if the application inside the container has started up successfully.
*   **Behavior**: Disables liveness and readiness checks until the startup probe succeeds.
*   **Use Case**: Essential for legacy apps or Java applications that take 30+ seconds to boot, preventing them from being killed prematurely by a liveness check.

### 2. Liveness Probe
*   **Purpose**: Determines if the container needs to be **restarted**.
*   **Behavior**: If the liveness check fails, the kubelet kills the container and restarts it (governed by the pod's `restartPolicy`).
*   **Use Case**: Resolving deadlocks, out-of-memory locks, or freeze-ups where the process is running but cannot make progress.

### 3. Readiness Probe
*   **Purpose**: Determines if the container is ready to **accept network traffic**.
*   **Behavior**: If it fails, the pod is immediately removed from the endpoints of any matching Kubernetes Service. The container **is NOT restarted**.
*   **Use Case**: Temporarily pausing traffic while the app loads heavy database caches, runs migrations, or is overloaded with concurrent connections.

---

## 🧪 Probe Mechanisms

You can configure probes using one of four check types:

1.  **`httpGet`**: Performs an HTTP GET request against a path on the container's IP (Success = Status Code `200` to `399`).
2.  **`tcpSocket`**: Checks if a TCP port is open (Success = Port is listening).
3.  **`exec`**: Runs a command inside the container shell (Success = Exit code `0`).
4.  **`grpc`**: Performs a gRPC health check.

---

## 🛠️ Hands-on Lab Exercise

### Step 1: Deploy a Pod with Health Checks
Create a file named `probes-demo.yaml` containing a simple HTTP server that exposes endpoints simulating startup, readiness, and liveness states.

> **Note**: Avoid relying on `busybox`'s `httpd` applet or `alpine`'s bundled busybox for this — applet availability varies by build/tag, and if the server process fails to start, the container itself keeps running (because it's backgrounded with `&`) while the probes just fail forever, leaving the pod stuck at `0/1` with repeated restarts. To eliminate that risk entirely, this lab uses Python's built-in `http.server` module (`python:3.12-alpine`), which has no external dependencies and is guaranteed to be present in the image.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: probes-demo
  labels:
    app: probes-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: probes-demo
  template:
    metadata:
      labels:
        app: probes-demo
    spec:
      containers:
      - name: web-server
        image: python:3.12-alpine
        # Exposes a simple HTTP server on port 8080 via Python's stdlib http.server.
        # It takes 15s to become ready, and exposes /healthz and /ready
        command:
        - sh
        - -c
        - |
          mkdir -p /tmp/www
          echo "Starting..." > /tmp/www/healthz
          echo "Initial status" > /tmp/www/ready
          # Start HTTP server, serving /tmp/www directly (avoids relying on
          # shell cd/backgrounding order — --directory is explicit and unambiguous)
          python3 -m http.server 8080 --directory /tmp/www &
          # Simulate 15s boot time
          sleep 15
          echo "App Started!" > /tmp/www/healthz
          echo "Ready to accept traffic" > /tmp/www/ready
          # Run forever
          sleep 3600
        ports:
        - containerPort: 8080
        
        # 1. Startup Probe (Blocks others during 15s boot)
        startupProbe:
          httpGet:
            path: /healthz
            port: 8080
          failureThreshold: 30
          periodSeconds: 1
          
        # 2. Liveness Probe (Checks if container is alive)
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          periodSeconds: 5
          timeoutSeconds: 2
          
        # 3. Readiness Probe (Checks if container can take traffic)
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          periodSeconds: 5
          initialDelaySeconds: 2
---
apiVersion: v1
kind: Service
metadata:
  name: probes-demo
spec:
  selector:
    app: probes-demo
  ports:
  - port: 80
    targetPort: 8080
```

Apply the deployment and service:
```bash
kubectl apply -f probes-demo.yaml
```

---

### Step 2: Observe the Startup Phase
Run a watch command on the pods immediately after applying:
```bash
kubectl get pods -w
```
*   **Observation**: You will see the status stay at `0/1 Running` for 15 seconds. During this time, the `startupProbe` is running.
*   Once the 15-second sleep in our command exits, `/healthz` and `/ready` are populated, the startup probe succeeds, and the status switches to `1/1 Running`.

---

### Step 3: Simulate a Readiness Failure
Let's simulate a database connection outage by deleting the `/tmp/www/ready` file in one of the pods, causing the readiness check to return `404 Not Found`.

1. Get the pod names:
   ```bash
   kubectl get pods -l app=probes-demo
   ```
2. Exec into one of the pods and delete the readiness file:
   ```bash
   kubectl exec -it <pod-name> -- rm /tmp/www/ready
   ```
3. Watch the pod list status again (allow ~15 seconds — the default `failureThreshold: 3` at `periodSeconds: 5` means it takes 3 consecutive failed checks before the status flips):
   ```bash
   kubectl get pods -l app=probes-demo -w
   ```
   *   **Result**: The target pod will switch from `1/1` to **`0/1`**. The container is **not restarted**, but it is no longer ready to take traffic.
4. Check the service endpoints (the `probes-demo` Service created alongside the Deployment):
   ```bash
   kubectl describe endpoints probes-demo
   ```
   *   The IP address of the failed pod is automatically removed from the active endpoints pool, preventing real-time traffic from reaching the broken container!

---

### Step 4: Simulate a Liveness Failure
Now let's simulate a process crash/freeze by deleting the liveness file `/tmp/www/healthz`:

1. Exec into the same pod and delete the healthz file:
   ```bash
   kubectl exec -it <pod-name> -- rm /tmp/www/healthz
   ```
2. Watch the pod list:
   ```bash
   kubectl get pods -l app=probes-demo -w
   ```
   *   **Result**: The `livenessProbe` must fail **3 consecutive times** (the default `failureThreshold`) at a 5-second `periodSeconds`, so the restart happens roughly 10-15 seconds after deleting the file — not instantly on the first failed check.
   *   You will see the **`RESTARTS` count increment to 1**.

---

## 🔎 Advanced Probe Parameters Reference

*   `initialDelaySeconds`: How many seconds to wait after the container starts before launching the check (default: 0).
*   `periodSeconds`: How often to perform the check (default: 10).
*   `timeoutSeconds`: Maximum time to wait for a probe response before marking it as failed (default: 1).
*   `failureThreshold`: Number of consecutive failures before marking the check as failed (default: 3).
*   `successThreshold`: Number of consecutive successes required to mark the check as healthy after a failure (default: 1).
