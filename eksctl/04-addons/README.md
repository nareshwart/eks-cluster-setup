# 04-addons

Install common EKS add-ons after the cluster is ready.

```bash
./04-addons/install-ebs-csi.sh student1 us-east-2
./04-addons/install-aws-load-balancer-controller.sh student1 us-east-2
./04-addons/install-metrics-server.sh
```

`install-karpenter.sh` is intentionally a guarded placeholder because Karpenter requires account-specific IAM, interruption queue, and node class settings.
