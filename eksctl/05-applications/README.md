# 05-applications

Deploys a small nginx workload and ALB ingress.

```bash
kubectl apply -f 05-applications/nginx.yaml
kubectl apply -f 05-applications/ingress.yaml
kubectl get ingress nginx
```

Install the AWS Load Balancer Controller before applying `ingress.yaml`.
