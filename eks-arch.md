# 🚀 Amazon EKS — Architecture, Node Types & Add-ons

---

## 📐 EKS Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│  AWS CLOUD                                                                                  │
│                                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────────────────────┐  │
│  │  EKS CONTROL PLANE  (AWS-Managed VPC — invisible to customer)                         │  │
│  │                                                                                       │  │
│  │   ┌─────────────────┐   ┌──────────────────┐   ┌──────────────────────────────────┐   │  │
│  │   │  kube-apiserver │   │   etcd  (HA)     │   │  kube-scheduler                  │   │  │
│  │   │  (EKS endpoint) │   │  3 AZ replicas   │   │  kube-controller-manager         │   │  │
│  │   └────────┬────────┘   └──────────────────┘   └──────────────────────────────────┘   │  │
│  │            │   AWS manages: patching · HA · backups · version upgrades                │  │
│  └────────────┼──────────────────────────────────────────────────────────────────────────┘  │
│               │ Cross-VPC ENI injection (EKS injects ENIs into your VPC subnets)            │
│               │ kubectl / Helm / AWS SDK  ◄──► EKS Public/Private API Endpoint              │
│               ▼                                                                             │
│  ╔═══════════════════════════════════════════════════════════════════════════════════════╗  │
│  ║  YOUR VPC  (e.g., 10.0.0.0/16)                                                        ║  │
│  ║                                                                                       ║  │
│  ║  ┌─────────────────────────────────────────────────────────────────────────────────┐  ║  │
│  ║  │  PUBLIC SUBNETS  (10.0.0.0/24 · 10.0.1.0/24 · 10.0.2.0/24)  — 3 AZs             │  ║  │
│  ║  │                                                                                 │  ║  │
│  ║  │   ┌──────────────────┐   ┌──────────────────────────────────────────────────┐   │  ║  │
│  ║  │   │   Internet GW    │   │  Application Load Balancer (ALB)                 │   │  ║  │
│  ║  │   │   NAT Gateway    │   │  aws-load-balancer-controller manages this       │   │  ║  │
│  ║  │   └────────┬─────────┘   └────────────────────────┬─────────────────────────┘   │  ║  │
│  ║  └────────────┼──────────────────────────────────────┼─────────────────────────────┘  ║  │
│  ║               │ (outbound internet for nodes/pods)   │ (inbound traffic → NodePort)   ║  │
│  ║  ┌────────────┼──────────────────────────────────────┼─────────────────────────────┐  ║  │
│  ║  │  PRIVATE NODE SUBNETS  (10.0.10.0/24 · 10.0.11.0/24 · 10.0.12.0/24) — 3 AZs     │  ║  │
│  ║  │  (EC2 worker nodes live here — node ENIs get IPs from this subnet)              │  ║  │
│  ║  │                                                                                 │  ║  │
│  ║  │   AZ-a (10.0.10.0/24)         AZ-b (10.0.11.0/24)        AZ-c (10.0.12.0/24)    │  ║  │
│  ║  │   ┌───────────────────┐       ┌───────────────────┐       ┌──────────────────┐  │  ║  │
│  ║  │   │  EC2 Worker Node  │       │  EC2 Worker Node  │       │  EC2 Worker Node │  │  ║  │
│  ║  │   │  IP: 10.0.10.5    │       │  IP: 10.0.11.7    │       │  IP: 10.0.12.3   │  │  ║  │
│  ║  │   │  ├─ kubelet       │       │  ├─ kubelet       │       │  ├─ kubelet      │  │  ║  │
│  ║  │   │  ├─ kube-proxy    │       │  ├─ kube-proxy    │       │  ├─ kube-proxy   │  │  ║  │
│  ║  │   │  └─ containerd    │       │  └─ containerd    │       │  └─ containerd   │  │  ║  │
│  ║  │   │                   │       │                   │       │                  │  │  ║  │
│  ║  │   │  ┌─────────────┐  │       │  ┌─────────────┐  │       │  ┌────────────┐  │  │  ║  │
│  ║  │   │  │  Pod        │  │       │  │  Pod        │  │       │  │  Pod       │  │  │  ║  │
│  ║  │   │  │100.64.0.5   │  │       │  │100.64.1.8   │  │       │  │100.64.2.4  │  │  │  ║  │
│  ║  │   │  └─────────────┘  │       │  └─────────────┘  │       │  └────────────┘  │  │  ║  │
│  ║  │   │  ┌─────────────┐  │       │  ┌─────────────┐  │       │  ┌────────────┐  │  │  ║  │
│  ║  │   │  │  Pod        │  │       │  │  Pod        │  │       │  │  Pod       │  │  │  ║  │
│  ║  │   │  │100.64.0.6   │  │       │  │100.64.1.9   │  │       │  │100.64.2.5  │  │  │  ║  │
│  ║  │   │  └─────────────┘  │       │  └─────────────┘  │       │  └────────────┘  │  │  ║  │
│  ║  │   └───────────────────┘       └───────────────────┘       └──────────────────┘  │  ║  │
│  ║  │                ▲  Pod IPs from Pod Subnet (secondary CIDR via VPC CNI)  ▲        │  ║  │
│  ║  └────────────────┼────────────────────────────────────────────────────────┼────────┘  ║  │
│  ║                   │                                                        │           ║  │
│  ║  ┌────────────────┼────────────────────────────────────────────────────────┼────────┐  ║  │
│  ║  │  POD SUBNETS   (Secondary CIDR: 100.64.0.0/16 split across AZs)        │        │  ║  │
│  ║  │  VPC CNI custom networking — pods get IPs from dedicated pod subnet     │        │  ║  │
│  ║  │                                                                                 │  ║  │
│  ║  │   100.64.0.0/18 (AZ-a)        100.64.64.0/18 (AZ-b)    100.64.128.0/18 (AZ-c) │  ║  │
│  ║  │   Pod IPs: 100.64.0.x         Pod IPs: 100.64.64.x      Pod IPs: 100.64.128.x  │  ║  │
│  ║  └─────────────────────────────────────────────────────────────────────────────────┘  ║  │
│  ║                                                                                       ║  │
│  ║  ┌──────────────────────────────────────────────────────────────────────────────────┐ ║  │
│  ║  │  AWS FARGATE  (Serverless — AWS manages micro-VMs, no visible EC2 nodes)         │ ║  │
│  ║  │  Pods run in isolated microVMs · IPs assigned from pod subnet · No node SSH      │ ║  │
│  ║  │   ┌────────────────────┐   ┌────────────────────┐   ┌────────────────────────┐  │ ║  │
│  ║  │   │ Pod  100.64.0.20   │   │ Pod  100.64.64.30  │   │ Pod  100.64.128.40     │  │ ║  │
│  ║  │   │ (microVM / AZ-a)   │   │ (microVM / AZ-b)   │   │ (microVM / AZ-c)       │  │ ║  │
│  ║  │   └────────────────────┘   └────────────────────┘   └────────────────────────┘  │ ║  │
│  ║  └──────────────────────────────────────────────────────────────────────────────────┘ ║  │
│  ║                                                                                       ║  │
│  ╚═══════════════════════════════════════════════════════════════════════════════════════╝  │
│                                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────────────────────┐  │
│  │  AWS SUPPORTING SERVICES (outside VPC / VPC-integrated via endpoints)                 │  │
│  │  IAM │ ECR │ EBS │ EFS │ S3 │ CloudWatch │ Secrets Manager │ Route53 │ ACM           │  │
│  └───────────────────────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Subnet IP Allocation Summary

| Subnet Type | CIDR Example | What Gets IPs Here | Who Manages |
|-------------|-------------|-------------------|-------------|
| **Public Subnet** | `10.0.0.0/24` per AZ | NAT Gateway, ALB, Internet GW | You (via VPC) |
| **Node Subnet** (Private) | `10.0.10.0/24` per AZ | EC2 worker node primary ENI | You (via VPC) |
| **Pod Subnet** (Secondary CIDR) | `100.64.0.0/18` per AZ | Pod IPs via VPC CNI custom networking | VPC CNI add-on |
| **Fargate Pod IPs** | From pod subnet | Fargate microVM pod ENI | AWS Fargate |

> **Why a separate Pod Subnet?**
> By default, VPC CNI assigns pod IPs from the **same node subnet**, which can exhaust IPs quickly.
> With **custom networking** (`AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true`), pods get IPs from a
> **dedicated secondary CIDR** (e.g., `100.64.0.0/16`), preserving node subnet IPs for EC2 instances.


---

## 🧩 EKS Component Layers

```
┌─────────────────────────────────────────────────────────────────┐
│  YOUR APPLICATIONS (Deployments, Services, Ingress, ConfigMaps) │
├─────────────────────────────────────────────────────────────────┤
│  KUBERNETES ADD-ONS  (CoreDNS, kube-proxy, VPC CNI, etc.)       │
├─────────────────────────────────────────────────────────────────┤
│  DATA PLANE  (EC2 Managed / EC2 Self-managed / Fargate)         │
├─────────────────────────────────────────────────────────────────┤
│  CONTROL PLANE  (API Server, etcd, Scheduler, Controllers)      │
├─────────────────────────────────────────────────────────────────┤
│  AWS INFRASTRUCTURE  (VPC, IAM, ELB, EBS, CloudWatch)          │
└─────────────────────────────────────────────────────────────────┘
```

---

## 👤 Responsibility Matrix — Who Manages What?

| Component | Control Plane | Managed Node Groups | Unmanaged Node Groups | AWS Fargate |
|-----------|:-------------:|:-------------------:|:---------------------:|:-----------:|
| **API Server** | ✅ AWS | — | — | — |
| **etcd** | ✅ AWS | — | — | — |
| **Scheduler** | ✅ AWS | — | — | — |
| **Controller Manager** | ✅ AWS | — | — | — |
| **HA across AZs** | ✅ AWS | ✅ AWS | ⚠️ You | ✅ AWS |
| **K8s version upgrades** | ✅ AWS | ✅ AWS (nodes follow) | ⚠️ You | ✅ AWS |
| **Node AMI patching** | — | ✅ AWS | ⚠️ You | ✅ AWS |
| **Node provisioning** | — | ✅ AWS (via ASG) | ⚠️ You | ✅ AWS |
| **Node scaling** | — | ✅ AWS (Cluster Autoscaler / Karpenter) | ⚠️ You | ✅ AWS (per pod) |
| **kubelet / kube-proxy** | — | ✅ AWS | ⚠️ You | ✅ AWS |
| **OS-level security** | — | ✅ AWS | ⚠️ You | ✅ AWS |
| **Custom AMI / OS** | — | ❌ Limited | ✅ Full control | ❌ Not applicable |
| **GPU / custom hardware** | — | ✅ Supported | ✅ Full control | ❌ Not supported |
| **EC2 instance visibility** | — | ✅ Visible in EC2 | ✅ Visible in EC2 | ❌ No EC2 nodes |
| **SSH / SSM access to nodes** | — | ✅ Yes | ✅ Yes | ❌ No node access |
| **Cost model** | Flat fee/cluster | EC2 On-demand/Spot/RI | EC2 On-demand/Spot/RI | Per vCPU+Memory/sec |
| **IAM for node** | — | IAM Node Role | IAM Node Role | Pod Execution Role |

### Legend
- ✅ AWS = AWS fully manages this
- ⚠️ You = You are responsible
- ❌ = Not applicable or not supported

---

## 🔍 Node Type Comparison — Deep Dive

| Feature | Managed Node Groups | Unmanaged Node Groups | Fargate |
|---------|--------------------|-----------------------|---------|
| **Setup complexity** | Low | High | Very Low |
| **AMI management** | AWS-optimized AMI, auto-updated | You choose and maintain | No AMI — serverless |
| **Cluster Autoscaler support** | ✅ Native | ✅ Manual setup | ✅ (scales per pod) |
| **Karpenter support** | ✅ Yes | ✅ Yes | ❌ No |
| **Spot instance support** | ✅ Yes | ✅ Yes | ❌ No |
| **Bottlerocket OS** | ✅ Supported | ✅ Supported | ❌ N/A |
| **Windows containers** | ✅ Supported | ✅ Supported | ❌ Not supported |
| **GPU workloads** | ✅ Supported | ✅ Supported | ❌ Not supported |
| **DaemonSets** | ✅ Supported | ✅ Supported | ❌ Not supported |
| **Node affinity/taints** | ✅ Supported | ✅ Supported | ✅ Profile-based |
| **Multi-tenant isolation** | Shared node | Shared node | ✅ Pod-level microVM isolation |
| **Stateful workloads (EBS)** | ✅ Yes | ✅ Yes | ❌ EBS not supported |
| **EFS support** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Ideal for** | General workloads | Special OS/hardware needs | Bursty / batch / serverless |

---

## 🔌 AWS-Provided EKS Add-ons

AWS maintains official add-ons that can be installed and upgraded through the EKS console, CLI, or Terraform. These are versioned, tested against specific K8s versions, and support IAM Roles for Service Accounts (IRSA).

### Core Networking & DNS

| Add-on | Name | Purpose |
|--------|------|---------|
| **Amazon VPC CNI** | `vpc-cni` | Assigns real AWS VPC IP addresses to pods. Enables pod-to-pod and pod-to-AWS service communication directly over the VPC network |
| **CoreDNS** | `coredns` | Cluster-internal DNS server. Resolves service names (e.g., `my-svc.default.svc.cluster.local`) to ClusterIPs |
| **kube-proxy** | `kube-proxy` | Maintains network rules on each node using iptables/IPVS. Handles Service-to-Pod traffic routing |

### Storage

| Add-on | Name | Purpose |
|--------|------|---------|
| **Amazon EBS CSI Driver** | `aws-ebs-csi-driver` | Manages EBS volumes as Kubernetes PersistentVolumes (PVs). Required for stateful workloads needing block storage |
| **Amazon EFS CSI Driver** | `aws-efs-csi-driver` | Mounts EFS file systems as PVs. Supports ReadWriteMany (RWX) — multiple pods can share the same volume simultaneously |
| **Amazon S3 Mountpoint CSI Driver** | `aws-mountpoint-s3-csi-driver` | Mount S3 buckets as a file system inside pods using Mountpoint for Amazon S3 |

### Security & Identity

| Add-on | Name | Purpose |
|--------|------|---------|
| **Pod Identity Agent** | `eks-pod-identity-agent` | Allows pods to assume IAM roles without needing OIDC/IRSA setup. Recommended over IRSA for simplicity |
| **AWS Secrets & Config Provider** | `secrets-store-csi-driver-provider-aws` | Mount secrets from AWS Secrets Manager and SSM Parameter Store directly into pods as files or env vars |
| **Amazon VPC CNI Network Policy** | `vpc-cni` (with Network Policy) | Enforces Kubernetes NetworkPolicies using AWS-native eBPF engine (no Calico required) |

### Observability & Monitoring

| Add-on | Name | Purpose |
|--------|------|---------|
| **Amazon CloudWatch Observability** | `amazon-cloudwatch-observability` | Deploys CloudWatch Agent + Fluent Bit. Collects container logs, metrics, and traces. Enables Container Insights |
| **AWS Distro for OpenTelemetry (ADOT)** | `adot` | Collects traces and metrics using OpenTelemetry SDK. Sends data to X-Ray, CloudWatch, or Prometheus |

### Ingress & Load Balancing

| Add-on | Name | Purpose |
|--------|------|---------|
| **AWS Load Balancer Controller** | `aws-load-balancer-controller` | Creates ALB (for Ingress) and NLB (for LoadBalancer Services) automatically when Kubernetes objects are created |

### Auto-scaling

| Add-on | Name | Purpose |
|--------|------|---------|
| **Karpenter** | `karpenter` | Next-gen node autoscaler. Provisions optimally-sized EC2 nodes in seconds based on pending pod requirements. Replaces Cluster Autoscaler |

---

## 🗺️ Add-on to Use-Case Mapping

| Use Case | Add-on(s) to Use |
|----------|-----------------|
| Pods can't communicate with each other | `vpc-cni` |
| Service DNS not resolving inside cluster | `coredns` |
| Service traffic not routing to pods | `kube-proxy` |
| Persistent storage for databases (MySQL, Postgres) | `aws-ebs-csi-driver` |
| Shared storage across multiple pods | `aws-efs-csi-driver` |
| Read large datasets from S3 in pods | `aws-mountpoint-s3-csi-driver` |
| Pods need to access AWS services (S3, DynamoDB) | `eks-pod-identity-agent` |
| Mount database passwords securely into pods | `secrets-store-csi-driver-provider-aws` |
| Restrict pod-to-pod traffic | `vpc-cni` with Network Policy |
| View container logs in CloudWatch | `amazon-cloudwatch-observability` |
| Distributed tracing with X-Ray | `adot` |
| HTTP routing / HTTPS with ACM certificates | `aws-load-balancer-controller` |
| Auto-scale nodes when pods are pending | `karpenter` |

---

## 💰 EKS Pricing Summary

| Component | Cost |
|-----------|------|
| **EKS Control Plane** | $0.10 per cluster per hour (~$72/month) |
| **Managed Node Groups** | EC2 instance pricing (On-demand / Spot / Reserved) |
| **Unmanaged Node Groups** | EC2 instance pricing |
| **Fargate** | $0.04048 per vCPU/hour + $0.004445 per GB/hour |
| **EKS Add-ons** | Free (you pay for underlying AWS resources e.g., EBS volume) |

---

## ✅ Quick Decision Guide

```
Do you need GPU / Windows / Custom OS?
  └─► YES → Unmanaged Node Groups

Do you want AWS to manage node patching and upgrades?
  └─► YES → Managed Node Groups

Do you want zero node management (serverless)?
  └─► YES → Fargate
       └─► But: No DaemonSets, No EBS, No GPU → check if acceptable

Do you need cost-optimized scaling with diverse instance types?
  └─► YES → Managed Node Groups + Karpenter

Do you need shared persistent storage across pods?
  └─► YES → EFS CSI Driver (works with Managed, Unmanaged, and Fargate)

Do you need per-pod block storage?
  └─► YES → EBS CSI Driver (Managed or Unmanaged only — NOT Fargate)
```
