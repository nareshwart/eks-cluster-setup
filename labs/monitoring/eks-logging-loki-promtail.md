# Lab Guide: Container Log Aggregation with Grafana Loki and Promtail

This lab guide walks you through setting up a centralized container logging solution in your EKS cluster using **Grafana Loki** and **Promtail**. You will learn how Kubernetes logs are collected, how to deploy Loki and Promtail via Helm, and how to query logs using **LogQL** inside Grafana.

---

## Overview & Architecture

By default, container logs in Kubernetes (stdout/stderr) are ephemeral. When a container restarts or its pod is deleted, the logs are lost. To retain and query logs across the entire cluster, we need a log aggregation stack.

Here is the architecture of the Loki-Promtail logging stack:

```
                      ┌──────────────────────────────────────────────┐
                      │              Kubernetes Node                 │
                      │                                              │
                      │  ┌───────────────┐        ┌───────────────┐  │
                      │  │   App Pod A   │        │   App Pod B   │  │
                      │  └───────┬───────┘        └───────┬───────┘  │
                      │          │ (stdout/stderr)        │          │
                      │          ▼                        ▼          │
                      │  ┌────────────────────────────────────────┐  │
                      │  │       Host directory: /var/log/pods    │  │
                      │  └───────────────────┬────────────────────┘  │
                      │                      │ (Read/Tail logs)      │
                      │                      ▼                       │
                      │  ┌────────────────────────────────────────┐  │
                      │  │       Promtail DaemonSet Agent         │  │
                      │  └───────────────────┬────────────────────┘  │
                      └──────────────────────┼───────────────────────┘
                                             │ (HTTP Push API)
                                             ▼
                                ┌─────────────────────────┐
                                │       Grafana Loki      │
                                │   (Log Aggregator/DB)   │
                                └────────────┬────────────┘
                                             ▲
                                             │ (LogQL Queries)
                                ┌────────────┴────────────┐
                                │         Grafana         │
                                │  (Visual Dashboards)    │
                                └─────────────────────────┘
```

1. **Promtail**: A logging agent deployed as a `DaemonSet` on every node in the cluster. It discovers container runtimes on the host, mounts the local directory `/var/log/pods`, tails the logs, and ships them to Loki.
2. **Grafana Loki**: A horizontally scalable, highly available, multi-tenant log aggregation system inspired by Prometheus. Unlike Elasticsearch, Loki indexation works on labels instead of full log text, making it extremely cost-effective and easy to operate.
3. **Grafana**: Query engine and visualization tool that connects to Loki as a data source to build graphs, dashboards, and live log streams.

---

## Prerequisites

Ensure you have completed the following monitoring lab:
- [Cluster Monitoring & Visualizing Metrics with Prometheus & Grafana](./eks-monitoring-prometheus-grafana.md) (Since we will reuse the Grafana instance deployed in that lab).

---

## Step 1 — Deploy Loki and Promtail

We will deploy Loki and Promtail using the community-standard `loki-stack` Helm chart in the same `monitoring` namespace.

1. **Add the Grafana Helm repository** (if not already added):
   ```bash
   helm repo add grafana https://grafana.github.io/helm-charts
   helm repo update
   ```

2. **Install Loki and Promtail**:
   Run the following installation command. We configure Loki with persistence enabled using `gp3` storage, and enable Promtail so it is automatically deployed as a DaemonSet:
   ```bash
   helm install loki-stack grafana/loki-stack \
     --namespace monitoring \
     --set loki.persistence.enabled=true \
     --set loki.persistence.storageClassName="gp3" \
     --set loki.persistence.size="5Gi" \
     --set promtail.enabled=true
   ```

3. **Verify the installation**:
   Ensure all logging workloads are successfully created and running:
   ```bash
   kubectl get pods -n monitoring -l "app.kubernetes.io/part-of=loki"
   ```
   You should see:
   - A Loki stateful set pod (e.g. `loki-stack-0`).
   - A Promtail DaemonSet pod running on each EKS worker node (e.g. `loki-stack-promtail-xxxxx`).

---

## Step 2 — Connect Loki as a Grafana Data Source

Since Loki is deployed in the same cluster and namespace as your existing Grafana instance, they can communicate internally using DNS.

1. **Get your Grafana Access URL and Login**:
   If you need to retrieve your credentials or NodePort again, refer back to the retrieval steps in [Step 2 of the Monitoring Lab](./eks-monitoring-prometheus-grafana.md#L92).

2. **Add the Loki Data Source**:
   - Log in to your Grafana UI.
   - Click the **Menu (hamburger icon)** on the top-left, select **Connections**, then select **Data sources**.
   - Click **Add data source** and search for **Loki**.
   - Set the following configuration options:
     - **Name**: `Loki`
     - **URL**: `http://loki-stack-loki.monitoring.svc.cluster.local:3100`
   - Scroll to the bottom and click **Save & test**. You should see a green notification: *"Data source successfully connected."*

---

## Step 3 — Query Logs using LogQL

Loki queries are written in **LogQL** (Log Query Language). LogQL is structured like PromQL, combining label matchers and filter expressions.

1. In Grafana, click the **Menu** on the top-left and select **Explore**.
2. Select **Loki** from the data source dropdown at the top.
3. In the query box, try the following common search queries:

### Query 1: Retrieve all logs from a specific namespace
Find all logs emitted by pods running in the `monitoring` namespace:
```logql
{namespace="monitoring"}
```
Click **Run query** (top-right). Scroll down to see the real-time stream of logs.

### Query 2: Filter by a specific container
Find logs originating only from the `promtail` containers:
```logql
{container="promtail"}
```

### Query 3: Search for errors (Filter Expression)
Use the pipe filter (`|=`) to search logs containing the text "error" case-sensitively:
```logql
{namespace="monitoring"} |= "error"
```
To search case-insensitively, use the regular expression filter (`|~`):
```logql
{namespace="monitoring"} |~ "(?i)error"
```

### Query 4: Format and parse JSON logs
If your application logs in JSON format, Loki can automatically parse the fields so you can filter by them.
```logql
{namespace="monitoring"} | json
```

---

## Step 4 — Build a Live Log Dashboard Panel

You can build a dashboard that shows cluster health metrics side-by-side with live container logs to help with real-time incident investigations.

1. In Grafana, go to **Dashboards** -> **New Dashboard** -> **Add visualization**.
2. Select **Loki** as the data source.
3. Set the LogQL query to view logs from your default namespace:
   ```logql
   {namespace="default"}
   ```
4. On the right-hand options panel, change the visualization type from **Time series** (default) to **Logs**.
5. Title the panel **"Default Namespace Container Logs"**.
6. Click **Apply** in the top-right corner.
7. Save the dashboard as **"Cluster Operations & Logs"**.

---

## Step 5 — Practice Exercises

### Exercise 1: Correlating App Failures and Logs
To practice debugging using Loki:
1. Deploy a broken pod that emits error logs and exits:
   ```yaml
   cat <<EOF | kubectl apply -f -
   apiVersion: v1
   kind: Pod
   metadata:
     name: faulty-logger
     namespace: default
   spec:
     containers:
     - name: log-writer
       image: alpine
       command: ["sh", "-c", "echo 'Initializing application...'; sleep 2; echo 'CRITICAL ERROR: Failed to connect to database!'; sleep 1; exit 1"]
   EOF
   ```
2. Navigate to **Explore** in Grafana, select **Loki**, and use a LogQL query to find the database connection failure message.
3. Clean up the faulty pod:
   ```bash
   kubectl delete pod faulty-logger
   ```

### Exercise 2: Calculate Log Volume Rates
We can perform metric operations on logs.
1. Enter the following query to graph the rate of logs generated per second over a 5-minute range:
   ```logql
   sum(rate({namespace="monitoring"}[5m]))
   ```
2. Change the visualization type to **Time series** to see the log volume visualized as a line chart.

### Exercise 3: Handling Multi-line Logs (Stack Traces)
Application errors, particularly in Java, Python, or Node.js, often output stack traces that span multiple lines. By default, container runtimes and Promtail treat each line as a separate log entry, making troubleshooting difficult.

1. **Deploy a pod that logs a stack trace**:
   ```yaml
   cat <<EOF | kubectl apply -f -
   apiVersion: v1
   kind: Pod
   metadata:
     name: stacktrace-logger
     namespace: default
   spec:
     containers:
     - name: log-writer
       image: alpine
       command: ["sh", "-c", "echo 'java.lang.NullPointerException: Cannot invoke method because object is null'; echo '  at com.example.App.main(App.java:15)'; echo '  at system.Run(Server.java:42)'; sleep 3600"]
   EOF
   ```

2. **Query the stack trace in Grafana Loki**:
   Go to **Explore** and run:
   ```logql
   {pod="stacktrace-logger"}
   ```
   Notice that the NullPointerException and its `at ...` traces appear as separate log entries with individual timestamps.

3. **Verify Promtail Multi-line configuration pattern**:
   In a production setup, you merge these lines at the agent level before shipping them. Promtail can be configured using a `multiline` stage in its block config:
   ```yaml
   # Conceptual Promtail configuration snippet:
   pipeline_stages:
     - multiline:
         firstline: '^\S' # Matches lines that do not start with whitespace
         max_wait_time: 3s
   ```
   This merges any line starting with a space or tab (such as stack trace lines) into the previous line.

4. **Cleanup the logger**:
   ```bash
   kubectl delete pod stacktrace-logger
   ```

### Exercise 4: Log-based Metric Alerts
You can generate metrics directly from logs to trigger alerts when error rates spike.

1. **Write a metric-from-logs LogQL query**:
   Run the following query in the **Explore** tab to count the number of database error occurrences in the last 10 minutes:
   ```logql
   sum(count_over_time({namespace="default"} |= "ERROR" [10m]))
   ```
2. **Configure an alert rule**:
   - In Grafana, click the **Menu** -> **Alerting** -> **Alert rules**.
   - Click **Create rule**.
   - Select **Loki** as the query source and paste your metric LogQL query.
   - Set the threshold to fire if the value is `IS ABOVE 0`.
   - Under **Contact points**, you can route this to Slack, PagerDuty, or Discord to alert operators immediately when critical errors appear in container logs.

---

## Step 6 — Cleanup

Clean up log aggregator resources once finished:

1. **Uninstall the Loki Helm release**:
   ```bash
   helm uninstall loki-stack -n monitoring
   ```

2. **Delete the Persistent Volume Claim (PVC)**:
   ```bash
   kubectl delete pvc -l app=loki -n monitoring
   ```
