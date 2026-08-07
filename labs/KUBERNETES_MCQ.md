# Kubernetes & Containers: 

---

## 📝 Multiple Choice Questions

### Question 1
What is a key difference between a Docker container and a Virtual Machine (VM)?
*   **A.** Containers include a full operating system kernel, whereas VMs do not.
*   **B.** Containers share the host operating system kernel, making them lightweight, whereas VMs run a complete guest OS.
*   **C.** VMs start faster than containers.
*   **D.** Containers cannot run on cloud instances.

### Question 2
Which Docker CLI command is used to build a container image from a local Dockerfile?
*   **A.** `docker run`
*   **B.** `docker pull`
*   **C.** `docker build`
*   **D.** `docker push`

### Question 3
Which Docker CLI command is used to start a container from an image?
*   **A.** `docker save`
*   **B.** `docker run`
*   **C.** `docker create-image`
*   **D.** `docker commit`

### Question 4
What is the standard command-line utility used to interact with and manage a Kubernetes cluster?
*   **A.** `eksctl`
*   **B.** `docker`
*   **C.** `kubectl`
*   **D.** `kubeadm`

### Question 5
Which component in the Kubernetes Control Plane acts as the primary data store, holding the cluster's configuration state and metadata?
*   **A.** `kube-apiserver`
*   **B.** `etcd`
*   **C.** `kube-scheduler`
*   **D.** `kube-proxy`

### Question 6
Which component runs on every worker node in a cluster and is responsible for making sure containers are actually running in their assigned Pods?
*   **A.** `kubelet`
*   **B.** `kube-controller-manager`
*   **C.** `etcd`
*   **D.** `kube-apiserver`

### Question 7
What is the smallest and most basic deployable object that you can create and manage in Kubernetes?
*   **A.** Container
*   **B.** Service
*   **C.** Pod
*   **D.** Namespace

### Question 8
If a Pod contains multiple containers, do these containers share the same IP address and network space?
*   **A.** No, each container inside a Pod gets a separate, unique IP address.
*   **B.** Yes, they share the same IP address and network namespace.
*   **C.** Containers inside a Pod cannot communicate with each other.
*   **D.** Only one container inside a Pod is allowed to use networking.

### Question 9
Which workload controller is commonly used to manage stateless applications, handle scaling, and execute rolling updates of Pods?
*   **A.** DaemonSet
*   **B.** Job
*   **C.** Deployment
*   **D.** CronJob

### Question 10
Which Kubernetes controller guarantees that exactly one copy of a specific Pod runs on all (or selected) worker nodes in the cluster?
*   **A.** Deployment
*   **B.** ReplicaSet
*   **C.** DaemonSet
*   **D.** StatefulSet

### Question 11
Which controller should you use to run a short-lived container task that executes once and then terminates (e.g., database migration)?
*   **A.** Deployment
*   **B.** Job
*   **C.** CronJob
*   **D.** DaemonSet

### Question 12
What is the default type of a Kubernetes Service, which makes the service accessible only from within the cluster?
*   **A.** NodePort
*   **B.** LoadBalancer
*   **C.** ClusterIP
*   **D.** ExternalName

### Question 13
Which Service type exposes the application outside the cluster by opening a specific port (between 30000 and 32767) on every worker node?
*   **A.** ClusterIP
*   **B.** NodePort
*   **C.** Headless Service
*   **D.** CoreDNS

### Question 14
What is Amazon EKS (Elastic Kubernetes Service)?
*   **A.** A command-line tool used to install Docker.
*   **B.** A managed service provided by AWS that simplifies running Kubernetes clusters without needing to manage the Control Plane.
*   **C.** A private database storage system in AWS.
*   **D.** An EC2 instance type optimized for running containers.

### Question 15
Which command-line utility is officially recommended by AWS to provision and configure EKS clusters using simple YAML templates or commands?
*   **A.** `kubectl`
*   **B.** `eksctl`
*   **C.** `aws-cli`
*   **D.** `docker-compose`

### Question 16
Which Kubernetes volume type is created when a Pod is assigned to a node, but is **permanently deleted** when that Pod is deleted or rescheduled?
*   **A.** `PersistentVolume`
*   **B.** `emptyDir`
*   **C.** `hostPath`
*   **D.** `StorageClass`

### Question 17
What object does a developer create to request a specific size and access mode of persistent network storage in Kubernetes?
*   **A.** `StorageClass`
*   **B.** `PersistentVolume`
*   **C.** `PersistentVolumeClaim` (PVC)
*   **D.** `VolumeMount`

### Question 18
Which Kubernetes resource is designed specifically to store non-confidential configuration settings in plain text key-value pairs?
*   **A.** Secret
*   **B.** ConfigMap
*   **C.** PersistentVolume
*   **D.** DaemonSet

### Question 19
Where should you store sensitive data, such as database passwords, API tokens, or SSH keys, inside Kubernetes?
*   **A.** ConfigMap
*   **B.** Pod labels
*   **C.** Secret
*   **D.** Deployment annotations

### Question 20
Which probe configuration does Kubernetes use to check if a container is ready to start accepting network traffic from a Service?
*   **A.** Liveness Probe
*   **B.** Readiness Probe
*   **C.** Startup Probe
*   **D.** Initial Delay Probe

### Question 21
What happens if a container's **Liveness Probe** fails repeatedly?
*   **A.** The Pod is deleted.
*   **B.** Kubelet restarts the container.
*   **C.** Traffic is temporarily paused to that container.
*   **D.** The node goes into an unhealthy state.

### Question 22
Which parameter specifies the **minimum** amount of CPU or Memory resources a container needs to be scheduled and run?
*   **A.** `limits`
*   **B.** `requests`
*   **C.** `thresholds`
*   **D.** `quotas`

### Question 23
Which parameter specifies the **maximum** amount of CPU or Memory resources that a container is allowed to consume?
*   **A.** `requests`
*   **B.** `limits`
*   **C.** `bounds`
*   **D.** `tolerations`

### Question 24
Which built-in service resolves domain names and manages service discovery within a Kubernetes cluster?
*   **A.** kube-proxy
*   **B.** CoreDNS
*   **C.** Cloud-init
*   **D.** Route53

### Question 25
Which Kubernetes resource acts as a firewall, allowing you to control and restrict network traffic flow between Pods?
*   **A.** Service
*   **B.** NetworkPolicy
*   **C.** ingress-controller
*   **D.** SecurityGroup
