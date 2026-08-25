# AWS Load Balancers: Classic Load Balancer (CLB) vs. Application Load Balancer (ALB)

This guide provides a comparative analysis of the AWS Classic Load Balancer (CLB) and the Application Load Balancer (ALB), with specific context on how they integrate with Kubernetes (EKS) and containerized workloads.

---

## 📊 Comparison Matrix

| Feature | Classic Load Balancer (CLB) | Application Load Balancer (ALB) |
| :--- | :--- | :--- |
| **OSI Layer** | Layer 4 (TCP/SSL) & Layer 7 (HTTP/HTTPS) | Layer 7 (HTTP/HTTPS/gRPC) |
| **Routing Decisions** | Simple load balancing based only on Port/IP. | Content-based routing (Path, Host, Query, Headers). |
| **Target Types** | EC2 Instances only. | EC2 Instances, IP Addresses (Pods), Lambda, ALBs. |
| **Kubernetes Integration** | Legacy in-tree controller (`type: LoadBalancer`). | AWS Load Balancer Controller (Ingress). |
| **EKS Pod Routing** | NodePort routing (extra network hop). | Direct Pod IP routing (using VPC CNI IP target mode). |
| **Microservices Multiplexing** | Requires 1 CLB per Service (expensive). | Multiple Services shared on 1 ALB (host/path rules). |
| **Protocols Supported** | TCP, SSL/TLS, HTTP, HTTPS | HTTP, HTTPS, HTTP/2, gRPC, WebSockets |
| **Target Group Weights** | Not Supported. | Supported (useful for Blue/Green & Canary deploys). |
| **AWS WAF Integration** | Not Supported. | Natively Supported. |

---

## 🔍 Key Differences Explained

### 1. OSI Layer & Routing Capabilities
*   **CLB (Classic)**: A legacy load balancer. It makes routing decisions at either the Transport layer (TCP) or Application layer (HTTP). However, it lacks smart application awareness. You cannot route traffic matching `/api` to one group of servers and `/web` to another; it simply routes all traffic arriving on a port to the backend instances.
*   **ALB (Application)**: A modern Layer 7 load balancer. It inspects HTTP headers, paths, hosts, query strings, and cookies to make intelligent routing decisions. For example, a single ALB can route `api.example.com/v1` to your backend pods and `example.com` to your frontend pods.

```
Classic Load Balancer (CLB):
[Client] ──► [ CLB (Port 80) ] ──► [ EC2 Instance Pool ] (All traffic goes to same pool)

Application Load Balancer (ALB):
                         ┌── Path: /api  ──► [ Backend Target Group ]
[Client] ──► [ ALB (L7) ]┼── Path: /web  ──► [ Frontend Target Group ]
                         └── Host: auth.* ──► [ Auth Service Target Group ]
```

---

### 2. Target Resolution Modes (EC2 vs. IP Mode)
*   **CLB (Instance Mode)**: Can only route traffic to EC2 instances. In EKS, this means the load balancer sends traffic to the node's external IP on a `NodePort`. The node's internal `kube-proxy` rules must then forward the packet to the actual Pod IP (which could be on a different node), causing an extra network hop.
*   **ALB (IP Mode)**: Supports targeting raw IP addresses. When integrated with EKS using the **AWS Load Balancer Controller**, the ALB routes traffic **directly to Pod IP addresses** allocated by the AWS VPC CNI. This bypasses the node's IP routing entirely, reducing latency, avoiding extra hops, and skipping `kube-proxy` translation.

---

### 3. Cost and Multiplexing
*   **CLB**: If you have 10 microservices, you must deploy 10 separate Classic Load Balancers. Each CLB charges an hourly base rate, leading to high AWS bills.
*   **ALB**: You can deploy a single ALB and use path/host rules to multiplex all 10 microservices through a single load balancer, significantly lowering infrastructure costs.

---

### 4. Advanced Protocol Support
*   **ALB** supports modern web communication standards natively, including:
    *   **HTTP/2**: Multiplexes requests over a single TCP connection, reducing latency.
    *   **gRPC**: Used for high-performance microservice-to-microservice communication.
    *   **WebSockets**: Enables persistent, low-latency, bi-directional connections (e.g., chat applications).

---

## 🛠️ Kubernetes Integration Reference

### Classic Load Balancer (In-Tree Service)
To provision a CLB, you simply create a standard `LoadBalancer` service:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: clb-service
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 8080
  selector:
    app: my-app
```

### Application Load Balancer (Ingress)
To provision an ALB, you install the **AWS Load Balancer Controller** and create an `Ingress` resource specifying `target-type: ip`:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: alb-ingress
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip # Directly routes to Pod IPs (Zero hops)
spec:
  ingressClassName: alb
  rules:
  - http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: backend-service
            port:
              number: 80
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend-service
            port:
              number: 80
```
