# Lab Guide: Cluster Monitoring & Visualizing Metrics with Prometheus & Grafana

This lab guide walks you through setting up a complete, production-grade monitoring stack in Kubernetes using **Prometheus** and **Grafana** (via the community-standard `kube-prometheus-stack` Helm chart). You will learn how to monitor Kubernetes nodes and pods, access Grafana dashboards, generate synthetic load on the cluster, and watch metrics react in real time.

---

## Overview & Architecture

To monitor a Kubernetes cluster, we need to gather metrics from multiple levels (hardware, operating system, Kubernetes API, and container runtimes) and consolidate them into a queryable database. 

Here is how the monitoring stack works:

```
                  ┌──────────────────────────────────────────────────────────┐
                  │                    Kubernetes Cluster                    │
                  │                                                          │
                  │   ┌───────────────┐                  ┌───────────────┐   │
                  │   │ kube-state-   │                  │ node-exporter │   │
                  │   │ metrics       │                  │ (Depl. per    │   │
                  │   │ (Cluster API) │                  │ Node)         │   │
                  │   └───────┬───────┘                  └───────┬───────┘   │
                  │           │ (Scrape)                         │ (Scrape)  │
                  │           ▼                                  ▼           │
                  │   ┌──────────────────────────────────────────────────┐   │
                  │   │              Prometheus Server                   │   │
                  │   │               (TSDB Database)                    │   │
                  │   └───────────────────────┬──────────────────────────┘   │
                  └───────────────────────────┼──────────────────────────────┘
                                              │ (PromQL Queries)
                                              ▼
                                 ┌─────────────────────────┐
                                 │         Grafana         │
                                 │  (Visual Dashboards)    │
                                 └─────────────────────────┘
```

1. **Prometheus Server**: A time-series database (TSDB) that pulls (scrapes) metrics from configured endpoints at regular intervals.
2. **node-exporter**: Runs as a `DaemonSet` on every node in the cluster to collect host-level metrics like CPU, memory, and disk usage.
3. **kube-state-metrics**: Listens to the Kubernetes API server and generates metrics about the state of objects (e.g., deployments, pod status, resource limits).
4. **Grafana**: A visualization tool that connects to Prometheus as a data source and renders beautiful, real-time charts and dashboards.

---

## Prerequisites

Ensure you have the following setup before beginning:
- An active EKS cluster.
- `kubectl` configured to communicate with your EKS cluster.
- `helm` CLI installed (v3+).

---

## Step 1 — Deploy the Kube-Prometheus-Stack

We will use Helm to deploy the Prometheus Operator stack in a dedicated namespace named `monitoring`.

1. **Create the `monitoring` namespace**:
   ```bash
   kubectl create namespace monitoring
   ```

2. **Add the Prometheus Community Helm repository**:
   ```bash
   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
   helm repo update
   ```

3. **Install the kube-prometheus-stack Helm chart**:
   Here, we will install the stack using the default values. This will spin up the Prometheus Operator, Prometheus Server, Grafana, Alertmanager, and exporters:
   ```bash
   helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
     --namespace monitoring \
     --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName="gp3" \
     --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage="10Gi" \
     --set grafana.persistence.storageClassName="gp3" \
     --set grafana.persistence.enabled=true \
     --set grafana.persistence.size="5Gi" \
     --set grafana.service.type=NodePort \
     --set prometheus.service.type=NodePort
   ```
   *(Note: Setting `gp3` storage class ensures that your metrics data and Grafana dashboards persist even if the pods restart).*

4. **Verify the installation**:
   It may take a couple of minutes for all the pods to pull images and start up. Run this command to monitor progress:
   ```bash
   kubectl get pods -n monitoring
   ```
   Ensure all pods (Prometheus, Grafana, Node Exporters, and Kube State Metrics) show `Running` and are in a healthy state.

---

## Step 2 — Retrieve Grafana Credentials and Connect

Since we configured the Grafana service to be of type `NodePort`, it is exposed on a high port (30000-32767) on all cluster nodes.

> [!TIP]
> If Grafana was installed without setting the service type to `NodePort` (meaning it is still configured as the default `ClusterIP`), you can patch the service first by running:
> ```bash
> kubectl patch svc kube-prometheus-stack-grafana -n monitoring -p '{"spec": {"type": "NodePort"}}'
> ```


1. **Get the Grafana Admin Password**:
   Helm automatically generates a secure password for the `admin` user. Retrieve and decode it using the following command:
   ```bash
   kubectl get secret --namespace monitoring kube-prometheus-stack-grafana \
     -o jsonpath="{.data.admin-password}" | base64 --decode ; echo
   ```
   *Record the output password safely. The default username is `admin`.*

2. **Retrieve the Grafana NodePort**:
   Query the Grafana service to find the dynamically assigned NodePort:
   ```bash
   export GRAFANA_PORT=$(kubectl get svc -n monitoring kube-prometheus-stack-grafana -o jsonpath='{.spec.ports[0].nodePort}')
   echo "Grafana NodePort: $GRAFANA_PORT"
   ```

3. **Retrieve a Node IP**:
   Find the IP address of one of your EKS nodes. 
   - If your cluster is public-facing:
     ```bash
     export NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')
     echo "Grafana Access URL: http://$NODE_IP:$GRAFANA_PORT"
     ```
   - If you are accessing from within the private network (e.g., via a jumpbox or VPN):
     ```bash
     export NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
     echo "Grafana Access URL: http://$NODE_IP:$GRAFANA_PORT"
     ```

4. **Access Grafana**:
   Open your web browser and navigate to the `Grafana Access URL` printed above.
   - **Username**: `admin`
   - **Password**: *[The password retrieved in Step 2.1]*

---

## Step 3 — Explore Pre-configured Dashboards

One of the main benefits of the `kube-prometheus-stack` is that Grafana comes pre-loaded with official Kubernetes dashboards.

1. Once logged into Grafana, click on the **Menu (hamburger icon)** on the top-left, then select **Dashboards**.
2. Expand the folders to locate the pre-installed dashboards. Find and open the following:
   - **Kubernetes / Compute Resources / Cluster**: Gives an overview of the CPU, Memory, and Storage usage across your entire EKS cluster.
   - **Kubernetes / Compute Resources / Node (Pods)**: Shows resource utilization per node and displays how much resource capacity remains.
   - **Kubernetes / Compute Resources / Pod**: Displays specific resource usage (CPU/Memory) for containers running inside a selected namespace and pod.
3. Observe the charts. Currently, they will show the baseline utilization of your EKS cluster.

---

## Step 4 — Simulate Resource Load on the Cluster

To see Grafana react to dynamic metrics, we will deploy a resource-intensive deployment that runs a CPU and memory stress test.

1. **Deploy a Load Generator App**:
   Create a manifest named `load-generator.yaml` and apply it, or run the following command directly:
   ```yaml
   cat <<EOF | kubectl apply -f -
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: load-generator
     namespace: default
   spec:
     replicas: 3
     selector:
       matchLabels:
         app: load-generator
     template:
       metadata:
         matchLabels:
           app: load-generator
       spec:
         containers:
         - name: cpu-burner
           image: alpine
           command: ["sh", "-c", "while true; do md5sum /dev/urandom; done"]
           resources:
             requests:
               cpu: "250m"
               memory: "64Mi"
             limits:
               cpu: "500m"
               memory: "128Mi"
   EOF
   ```
   *This command runs three replicas of an alpine container performing infinite MD5 calculations. Each container requests at least 0.25 vCPU cores (`250m`).*

2. **Verify Pod status**:
   Ensure the three load generator pods are running:
   ```bash
   kubectl get pods -l app=load-generator
   ```

3. **Observe the Grafana Dashboard**:
   - Go back to your browser at `http://localhost:3000` and open the **Kubernetes / Compute Resources / Namespace (Pods)** dashboard.
   - Select the `default` namespace from the dropdown filter at the top.
   - Wait 1-2 minutes and observe the **CPU Usage** and **Memory Usage** graphs for the `load-generator` pods.
   - Notice the CPU usage lines spike up and stabilize around the limits we defined.

---

## Step 5 — Practice Exercises

### Exercise 1: Querying Prometheus Directly using PromQL
Prometheus collects raw metrics which can be queried using Prometheus Query Language (PromQL).
1. Since the Prometheus service is also exposed as a `NodePort`, retrieve the Prometheus NodePort and Node IP:
   ```bash
   export PROM_PORT=$(kubectl get svc -n monitoring kube-prometheus-stack-prometheus -o jsonpath='{.spec.ports[0].nodePort}')
   # Use the same NODE_IP determined in Step 2:
   echo "Prometheus Access URL: http://$NODE_IP:$PROM_PORT"
   ```
2. Open your web browser and navigate to the `Prometheus Access URL` printed above.
3. In the query box, paste the following PromQL queries and click **Execute**:
   - **Total memory usage by container (in bytes)**:
     ```promql
     sum(container_memory_working_set_bytes{namespace="default"}) by (pod)
     ```
   - **CPU usage rate per pod (averaged over 2 minutes)**:
     ```promql
     sum(rate(container_cpu_usage_seconds_total{namespace="default"}[2m])) by (pod)
     ```
   - **Count of pods running in each namespace**:
     ```promql
     sum(kube_pod_status_phase{phase="Running"}) by (namespace)
     ```

### Exercise 2: Build a Custom Grafana Dashboard Panel
Create a dedicated visualization representing only our load generator pods.
1. In Grafana, click the **+ (plus icon)** at the top-right and select **New Dashboard**, then click **Add visualization**.
2. Select **Prometheus** as the data source.
3. In the query field (under **Metric Query**), enter the PromQL expression for the load generator pod CPU usage:
   ```promql
   sum(rate(container_cpu_usage_seconds_total{pod=~"load-generator-.*"}[2m])) by (pod)
   ```
4. On the right-side options panel:
   - Change the panel title to **"Load Generator Pod CPU Usage"**.
   - Under **Graph Styles**, set the style to **Area** and enable **Gradient mode (Opacity)** for a modern UI.
5. Click **Apply** in the top-right corner to save the panel to your new dashboard.

### Exercise 3: Deploying a Custom Prometheus Alerting Rule
The Prometheus Operator manages alerting rules dynamically using the `PrometheusRule` Custom Resource Definition (CRD).

1. **Deploy a custom alerting rule**:
   Create a rule that fires an alert if any pod in the cluster fails or enters a failed state:
   ```yaml
   cat <<EOF | kubectl apply -f -
   apiVersion: monitoring.coreos.com/v1
   kind: PrometheusRule
   metadata:
     name: custom-pod-alerts
     namespace: monitoring
     labels:
       release: kube-prometheus-stack
   spec:
     groups:
     - name: pod.rules
       rules:
       - alert: PodInFailedState
         expr: kube_pod_status_phase{phase="Failed"} > 0
         for: 1m
         labels:
           severity: warning
         annotations:
           summary: "Pod {{ \$labels.pod }} failed"
           description: "Pod {{ \$labels.pod }} in namespace {{ \$labels.namespace }} has been in a Failed state for more than 1 minute."
   EOF
   ```
   *(Note: The label `release: kube-prometheus-stack` is critical. The Prometheus Operator uses label matching to automatically locate and load new alerting rules).*

2. **Verify the alerting rule**:
   - Access the Prometheus web interface (see Exercise 1).
   - Click on **Status** in the top navigation bar, then select **Rules**.
   - Search for `custom-pod-alerts`. Verify that your newly created rule appears in the list and is successfully parsed.

### Exercise 4: Scraping Custom App Metrics via ServiceMonitor
Rather than modifying a global static scraping config, the Prometheus Operator utilizes the `ServiceMonitor` CRD. It automatically discovers and configures scrape targets by selecting Kubernetes services with matching labels.

1. **Deploy a sample app that exposes metrics**:
   Let's deploy a sample container that exposes custom Prometheus metrics on port `8080/metrics`:
   ```yaml
   cat <<EOF | kubectl apply -f -
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: sample-metrics-app
     namespace: default
     labels:
       app: sample-metrics-app
   spec:
     replicas: 1
     selector:
       matchLabels:
         app: sample-metrics-app
     template:
       metadata:
         labels:
           app: sample-metrics-app
       spec:
         containers:
         - name: prometheus-app
           image: prom/write-to-prometheus:latest
           ports:
           - containerPort: 8080
             name: web-metrics
   ---
   apiVersion: v1
   kind: Service
   metadata:
     name: sample-metrics-app
     namespace: default
     labels:
       app: sample-metrics-app
   spec:
     ports:
     - port: 8080
       targetPort: web-metrics
       name: http-metrics
     selector:
       app: sample-metrics-app
   EOF
   ```

2. **Deploy a ServiceMonitor**:
   Create a monitor in the `monitoring` namespace targeting our sample service in the `default` namespace:
   ```yaml
   cat <<EOF | kubectl apply -f -
   apiVersion: monitoring.coreos.com/v1
   kind: ServiceMonitor
   metadata:
     name: sample-metrics-monitor
     namespace: monitoring
     labels:
       release: kube-prometheus-stack
   spec:
     selector:
       matchLabels:
         app: sample-metrics-app
     namespaceSelector:
       matchNames:
       - default
     endpoints:
     - port: http-metrics
       interval: 15s
       path: /metrics
   EOF
   ```
   *(Note: The label `release: kube-prometheus-stack` is required so the operator configures Prometheus to scrape this ServiceMonitor).*

3. **Verify the new Target in Prometheus**:
   - In the Prometheus UI, go to **Status** -> **Targets**.
   - Search for `sample-metrics-monitor`. Verify that the target is listed and its status is `UP`.

4. **Cleanup custom app resources**:
   ```bash
   kubectl delete servicemonitor sample-metrics-monitor -n monitoring
   kubectl delete svc,deployment sample-metrics-app -n default
   kubectl delete prometheusrule custom-pod-alerts -n monitoring
   ```

---

## Step 6 — Cleanup

Always clean up lab resources once finished to optimize cloud infrastructure costs.

1. **Delete the load generator**:
   ```bash
   kubectl delete deployment load-generator
   ```

2. **Uninstall kube-prometheus-stack**:
   ```bash
   helm uninstall kube-prometheus-stack -n monitoring
   ```

3. **Delete PVs and CRDs (Optional but recommended)**:
   Uninstalling the Helm release will leave behind Custom Resource Definitions (CRDs) and persistent volume claims. Purge them to complete cleanup:
   ```bash
   # Delete persistent volume claims (PVCs) in monitoring namespace
   kubectl delete pvc --all -n monitoring
   
   # Delete the monitoring namespace
   kubectl delete namespace monitoring
   
   # Clean up Prometheus Operator CRDs
   kubectl delete crd alertmanagerconfigs.monitoring.coreos.com alertmanagers.monitoring.coreos.com contenttemplates.monitoring.coreos.com podmonitors.monitoring.coreos.com probes.monitoring.coreos.com prometheusagents.monitoring.coreos.com prometheuses.monitoring.coreos.com prometheusrules.monitoring.coreos.com servicemonitors.monitoring.coreos.com thanosrulers.monitoring.coreos.com
   ```
