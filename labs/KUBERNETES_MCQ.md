# Kubernetes & Containers: Introductory MCQ Assessment

This assessment contains 25 multiple-choice questions designed to evaluate basic, entry-level knowledge of Docker containers, Kubernetes architecture, core workloads, EKS services, storage, and networking.

---

## 📝 Multiple Choice Questions

### Question 1 (Docker Containers)
What is a key difference between a Docker container and a Virtual Machine (VM)?
*   **A.** Containers include a full operating system kernel, whereas VMs do not.
*   **B.** Containers share the host operating system kernel, making them lightweight, whereas VMs run a complete guest OS.
*   **C.** VMs start faster than containers.
*   **D.** Containers cannot run on cloud instances.

### Question 2 (Docker Containers)
Which Docker CLI command is used to build a container image from a local Dockerfile?
*   **A.** `docker run`
*   **B.** `docker pull`
*   **C.** `docker build`
*   **D.** `docker push`

### Question 3 (Docker Containers)
Which Docker CLI command is used to start a container from an image?
*   **A.** `docker save`
*   **B.** `docker run`
*   **C.** `docker create-image`
*   **D.** `docker commit`

### Question 4 (Kubernetes Architecture)
What is the standard command-line utility used to interact with and manage a Kubernetes cluster?
*   **A.** `eksctl`
*   **B.** `docker`
*   **C.** `kubectl`
*   **D.** `kubeadm`

### Question 5 (Kubernetes Architecture)
Which component in the Kubernetes Control Plane acts as the primary data store, holding the cluster's configuration state and metadata?
*   **A.** `kube-apiserver`
*   **B.** `etcd`
*   **C.** `kube-scheduler`
*   **D.** `kube-proxy`

### Question 6 (Kubernetes Architecture)
Which component runs on every worker node in a cluster and is responsible for making sure containers are actually running in their assigned Pods?
*   **A.** `kubelet`
*   **B.** `kube-controller-manager`
*   **C.** `etcd`
*   **D.** `kube-apiserver`

### Question 7 (Pods)
What is the smallest and most basic deployable object that you can create and manage in Kubernetes?
*   **A.** Container
*   **B.** Service
*   **C.** Pod
*   **D.** Namespace

### Question 8 (Pods)
If a Pod contains multiple containers, do these containers share the same IP address and network space?
*   **A.** No, each container inside a Pod gets a separate, unique IP address.
*   **B.** Yes, they share the same IP address and network namespace.
*   **C.** Containers inside a Pod cannot communicate with each other.
*   **D.** Only one container inside a Pod is allowed to use networking.

### Question 9 (Controllers)
Which workload controller is commonly used to manage stateless applications, handle scaling, and execute rolling updates of Pods?
*   **A.** DaemonSet
*   **B.** Job
*   **C.** Deployment
*   **D.** CronJob

### Question 10 (Controllers)
Which Kubernetes controller guarantees that exactly one copy of a specific Pod runs on all (or selected) worker nodes in the cluster?
*   **A.** Deployment
*   **B.** ReplicaSet
*   **C.** DaemonSet
*   **D.** StatefulSet

### Question 11 (Controllers)
Which controller should you use to run a short-lived container task that executes once and then terminates (e.g., database migration)?
*   **A.** Deployment
*   **B.** Job
*   **C.** CronJob
*   **D.** DaemonSet

### Question 12 (Services)
What is the default type of a Kubernetes Service, which makes the service accessible only from within the cluster?
*   **A.** NodePort
*   **B.** LoadBalancer
*   **C.** ClusterIP
*   **D.** ExternalName

### Question 13 (Services)
Which Service type exposes the application outside the cluster by opening a specific port (between 30000 and 32767) on every worker node?
*   **A.** ClusterIP
*   **B.** NodePort
*   **C.** Headless Service
*   **D.** CoreDNS

### Question 14 (EKS Cluster Setup)
What is Amazon EKS (Elastic Kubernetes Service)?
*   **A.** A command-line tool used to install Docker.
*   **B.** A managed service provided by AWS that simplifies running Kubernetes clusters without needing to manage the Control Plane.
*   **C.** A private database storage system in AWS.
*   **D.** An EC2 instance type optimized for running containers.

### Question 15 (EKS Cluster Setup)
Which command-line utility is officially recommended by AWS to provision and configure EKS clusters using simple YAML templates or commands?
*   **A.** `kubectl`
*   **B.** `eksctl`
*   **C.** `aws-cli`
*   **D.** `docker-compose`

### Question 16 (Storage)
Which Kubernetes volume type is created when a Pod is assigned to a node, but is **permanently deleted** when that Pod is deleted or rescheduled?
*   **A.** `PersistentVolume`
*   **B.** `emptyDir`
*   **C.** `hostPath`
*   **D.** `StorageClass`

### Question 17 (Storage)
What object does a developer create to request a specific size and access mode of persistent network storage in Kubernetes?
*   **A.** `StorageClass`
*   **B.** `PersistentVolume`
*   **C.** `PersistentVolumeClaim` (PVC)
*   **D.** `VolumeMount`

### Question 18 (ConfigMaps / Secrets)
Which Kubernetes resource is designed specifically to store non-confidential configuration settings in plain text key-value pairs?
*   **A.** Secret
*   **B.** ConfigMap
*   **C.** PersistentVolume
*   **D.** DaemonSet

### Question 19 (ConfigMaps / Secrets)
Where should you store sensitive data, such as database passwords, API tokens, or SSH keys, inside Kubernetes?
*   **A.** ConfigMap
*   **B.** Pod labels
*   **C.** Secret
*   **D.** Deployment annotations

### Question 20 (Probes)
Which probe configuration does Kubernetes use to check if a container is ready to start accepting network traffic from a Service?
*   **A.** Liveness Probe
*   **B.** Readiness Probe
*   **C.** Startup Probe
*   **D.** Initial Delay Probe

### Question 21 (Probes)
What happens if a container's **Liveness Probe** fails repeatedly?
*   **A.** The Pod is deleted.
*   **B.** Kubelet restarts the container.
*   **C.** Traffic is temporarily paused to that container.
*   **D.** The node goes into an unhealthy state.

### Question 22 (Resource Limits)
Which parameter specifies the **minimum** amount of CPU or Memory resources a container needs to be scheduled and run?
*   **A.** `limits`
*   **B.** `requests`
*   **C.** `thresholds`
*   **D.** `quotas`

### Question 23 (Resource Limits)
Which parameter specifies the **maximum** amount of CPU or Memory resources that a container is allowed to consume?
*   **A.** `requests`
*   **B.** `limits`
*   **C.** `bounds`
*   **D.** `tolerations`

### Question 24 (Pod-to-Pod Communication / CoreDNS)
Which built-in service resolves domain names and manages service discovery within a Kubernetes cluster?
*   **A.** kube-proxy
*   **B.** CoreDNS
*   **C.** Cloud-init
*   **D.** Route53

### Question 25 (Network Policies)
Which Kubernetes resource acts as a firewall, allowing you to control and restrict network traffic flow between Pods?
*   **A.** Service
*   **B.** NetworkPolicy
*   **C.** ingress-controller
*   **D.** SecurityGroup

---

## 🔑 Answer Key & Explanations

1.  **B**
    *   *Explanation*: Containers share the host OS kernel and isolate process layers, making them lightweight. VMs run a full hypervisor and guest OS.
2.  **C**
    *   *Explanation*: The command `docker build` processes a Dockerfile to create a reusable container image.
3.  **B**
    *   *Explanation*: The command `docker run` instantiates and starts a container process from a specified image.
4.  **C**
    *   *Explanation*: `kubectl` is the official Kubernetes command-line tool used to create, inspect, and manage resources.
5.  **B**
    *   *Explanation*: `etcd` is a consistent, highly-available key-value store used to hold all cluster configuration state data.
6.  **A**
    *   *Explanation*: The `kubelet` is the node agent that receives pod specifications from the API Server and runs containers via the local container runtime.
7.  **C**
    *   *Explanation*: A Pod is the smallest deployable computing unit in Kubernetes, representing a single instance of a running process.
8.  **B**
    *   *Explanation*: Containers in the same Pod share the same network namespace and IP address, communicating with each other via `localhost`.
9.  **C**
    *   *Explanation*: `Deployments` manage stateless pods, offering declarative updates, rollbacks, and scaling.
10. **C**
    *   *Explanation*: A `DaemonSet` runs a copy of a pod on all nodes, useful for logging, monitoring, and network daemons.
11. **B**
    *   *Explanation*: A `Job` creates one or more pods and ensures that a specified number of them successfully terminate.
12. **C**
    *   *Explanation*: `ClusterIP` exposes the Service on a cluster-internal IP, making it only reachable from within the cluster.
13. **B**
    *   *Explanation*: `NodePort` opens a static port on each worker node's IP, forwarding traffic to the backend Service.
14. **B**
    *   *Explanation*: Amazon EKS is a managed service that runs the Kubernetes control plane for you, ensuring high availability.
15. **B**
    *   *Explanation*: `eksctl` is a simple CLI tool developed by Weaveworks and officially recommended by AWS to provision and manage EKS clusters.
16. **B**
    *   *Explanation*: An `emptyDir` volume is ephemeral, created when a Pod is assigned to a node and deleted when the Pod is deleted.
17. **C**
    *   *Explanation*: A `PersistentVolumeClaim` (PVC) is a request for storage by a user, specifying size and access parameters.
18. **B**
    *   *Explanation*: `ConfigMaps` store non-sensitive configuration keys in plain text.
19. **C**
    *   *Explanation*: `Secrets` store sensitive keys (passwords, tokens, keys) and are Base64-obfuscated in configuration manifests.
20. **B**
    *   *Explanation*: The `ReadinessProbe` checks if a container is ready to serve network requests, controlling service endpoint registration.
21. **B**
    *   *Explanation*: The `LivenessProbe` detects if a container process is frozen or deadlocked. Fails -> container is restarted.
22. **B**
    *   *Explanation*: Resource `requests` define the minimum memory/CPU a container needs to start, used by the scheduler to place the Pod.
23. **B**
    *   *Explanation*: Resource `limits` define the absolute maximum memory/CPU a container can consume.
24. **B**
    *   *Explanation*: `CoreDNS` is the default DNS resolver running inside Kubernetes to translate service names to cluster IPs.
25. **B**
    *   *Explanation*: `NetworkPolicy` resources configure firewall rules for pods, controlling traffic ingress and egress.
