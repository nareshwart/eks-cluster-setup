# Terraform Provisioning Flow & Dependency Graph

This document explains the resource provisioning sequence when `terraform apply` is executed on this platform. It maps out how the configuration flows from the root configuration down into the reusable modules, detailing how implicit and explicit dependencies dictate the order of creation.

---

## The Core Concept: Directed Acyclic Graph (DAG)

Terraform does not simply read files from top to bottom. Instead, it builds a dependency graph of all resources and modules. 
*   **Implicit Dependency**: Created when an output from one module is passed as an input variable to another (e.g., passing `module.networking.vpc_id` into the `eks` module).
*   **Explicit Dependency**: Set using the `depends_on` meta-argument.

---

## Architectural Flow Diagram (Mermaid)

The following diagram illustrates the execution flow and resource dependency tree from the root configuration down to the sub-modules:

```mermaid
graph TD
    %% Root configuration
    Root["Root config (03-examples/single-cluster/main.tf)"]
    
    %% Main Cluster Module
    Cluster["Cluster Module (01-modules/cluster/main.tf)"]
    
    %% Submodules
    Net["1. Networking Module (01-modules/networking/)"]
    IAM["2. IAM Module (01-modules/iam/)"]
    EKS_Ctrl["3a. EKS Control Plane & Access Entries"]
    EKS_CNI["3b. VPC CNI & ENIConfig Manifests"]
    EKS_Nodes["3c. EKS Managed Node Group"]
    Addons["4. Other Addons Module (01-modules/addons/)"]
    Storage["5. Storage Module (01-modules/storage/)"]
    Monitor["6. Monitoring Module (01-modules/monitoring/)"]

    %% Flow connections
    Root -->|Calls| Cluster
    Cluster -->|1st (Parallel)| Net
    Cluster -->|1st (Parallel)| IAM
    
    Net -->|Passes: subnet IDs & SGs| EKS_Ctrl
    IAM -->|Passes: role_arns & profile_names| EKS_Ctrl
    
    EKS_Ctrl -->|Triggers CNI deployment| EKS_CNI
    Net -->|Passes: pod_subnet_ids & azs| EKS_CNI
    
    EKS_CNI -->|Dependency block: depends_on| EKS_Nodes
    
    EKS_Nodes -->|Passes: node_group_name| Addons
    EKS_Ctrl -->|Passes: oidc_provider| Addons
    
    Addons -->|Explicit depends_on dependency| Storage
    EKS_Ctrl -->|Passes: cluster_name| Monitor
    
    style Root fill:#f9f,stroke:#333,stroke-width:2px
    style Cluster fill:#bbf,stroke:#333,stroke-width:2px
    style Net fill:#dfd,stroke:#333,stroke-width:1px
    style IAM fill:#dfd,stroke:#333,stroke-width:1px
    style EKS_Ctrl fill:#fdd,stroke:#333,stroke-width:2px
    style EKS_CNI fill:#fdd,stroke:#333,stroke-width:2px
    style EKS_Nodes fill:#fdd,stroke:#333,stroke-width:2px
    style Addons fill:#ffd,stroke:#333,stroke-width:1px
```

---

## Step-by-Step Execution Sequence

When you run `terraform apply`, Terraform executes the configuration in the following order:

### 1. Root Configuration Entry (`main.tf`)
The execution starts in the folder where `terraform apply` is called (e.g. `terraform/03-examples/single-cluster/main.tf`). This configuration sets up the AWS provider and calls:
```hcl
module "cluster" {
  source       = "../../01-modules/cluster"
  cluster_name = "student1"
  ...
}
```

---

### 2. Main Cluster Wrapper Module (`01-modules/cluster`)
This module acts as the orchestrator. It receives variables from the root config, establishes local common variables (like name prefixes and standard resource tags), and feeds them into the sub-modules.

---

### 3. Step 1 (Parallel execution): Networking & IAM Modules
Since there are no dependencies between Networking and IAM, Terraform initializes and creates their resources simultaneously.

#### A. Networking Module (`01-modules/networking`)
*   **Resources created**: VPC, Internet Gateway (IGW), public/pod subnets, route tables, security groups.
*   **Outputs**: Exports the `vpc_id`, `node_subnet_ids`, `pod_subnet_ids`, `azs`, and `cluster_security_group_id`.

#### B. IAM Module (`01-modules/iam`)
*   **Resources created**: EKS control plane IAM Role, managed EKS Node Group instance IAM Role, instance profiles.
*   **Outputs**: Exports the IAM role ARNs and instance profile names.

---

### 4. Step 2: EKS Module Execution (`01-modules/eks`)
The EKS module handles EKS Control Plane creation, IAM permissions, Access Entries, VPC CNI Setup, custom networking ENIConfigs, and Node Groups in a strict sequence:

#### Step 2a: Control Plane & Access Entries
*   The EKS Control Plane (`aws_eks_cluster.this`) is created.
*   Initial cluster Access Entries and Admin Policy Associations are created to grant the executing STS credentials cluster-admin permissions.

#### Step 2b: VPC CNI & Custom Networking Configuration
*   The EKS managed `vpc-cni` addon is configured. If custom pod networking is enabled, the addon is updated with environment values (`AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true`, `ENI_CONFIG_LABEL_DEF=topology.kubernetes.io/zone`, and `ENABLE_PREFIX_DELEGATION=true`).
*   One `ENIConfig` custom resource is created for each Availability Zone, mapping to the corresponding pod subnet and security group.
*   **Bypassing Validation**: We use a `terraform_data` resource with a `local-exec` provisioner running `kubectl apply` to deploy these manifests. This is because standard `kubernetes_manifest` resources fail during the planning stage if the `ENIConfig` CRD (installed by the CNI addon) is not yet registered in the EKS API. Local execution bypasses this client-side GroupVersionKind validation.

#### Step 2c: Managed Node Group Provisioning
*   The managed node group (`aws_eks_node_group.managed`) is created.
*   **Crucial sequencing**: The node group has an explicit `depends_on` on the `eniconfig` resources. This guarantees that nodes boot **after** custom networking is active, ensuring that worker nodes and their system pods receive their secondary CIDR IPs (`100.64.x.x`) immediately upon registration.

---

### 5. Step 3: Addons & Monitoring Modules (Parallel execution)
Once the EKS control plane and node group are active, Terraform deploys these supplementary modules:

#### A. Addons Module (`01-modules/addons`)
*   **Inputs received**: `oidc_provider_arn`, `oidc_provider_url`, `cluster_name`, and `managed_node_group_name` (from `eks`).
*   **Resources created**: Deploys supplementary components:
    *   CoreDNS & Kube-proxy managed addons (CoreDNS depends on the node group being active)
    *   AWS EBS CSI Driver (including IAM service accounts via OIDC)
    *   Kubernetes Metrics Server
    *   AWS Load Balancer Controller (optional Helm release)

#### B. Monitoring Module (`01-modules/monitoring`)
*   **Inputs received**: `cluster_name` (from `eks`).
*   **Resources created**: CloudWatch Log Groups for control plane logs.

---

### 6. Step 4: Storage Module (`01-modules/storage`)
The Storage module configures default storage classes (like gp3) inside the cluster. It has an **explicit dependency** on the Addons module to ensure the EBS CSI driver is active before creating the default EKS storage class.

```hcl
module "storage" {
  source     = "../storage"
  depends_on = [module.addons] # <-- Explicit dependency
}
```

*   **Resources created**: Default `gp3` Kubernetes StorageClass.

---

## Summary of Outputs
Once all modules complete execution, outputs ripple back to the root configuration level, exposing variables like `kubeconfig_command` to the operator so they can connect using `kubectl`.
