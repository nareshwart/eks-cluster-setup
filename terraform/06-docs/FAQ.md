# FAQ

**Can I run more than a handful of clusters?**
Yes — the platform scales purely by adding entries to
`clusters.auto.tfvars.json`; no module or root code changes are required.

**Why local backend + workspaces instead of S3?**
Simpler for a single operator machine and keeps state isolated per cluster out
of the box. See `terraform/backend/README.md` to switch to S3 + DynamoDB for
shared/CI use.

**Why is NAT Gateway disabled by default?**
Cost. Each NAT Gateway is billed hourly + per-GB. Public subnets alone are
sufficient for most exercises. Enable per-cluster via
`enable_nat_gateway = true` if private-only workloads are needed.

**Why is CloudWatch cluster logging off by default?**
Cost and log noise for short-lived training clusters. Enable via
`enable_cluster_logging = true` if deeper debugging is required.

**Is ArgoCD/Karpenter/Istio included?**
Not yet — see `docs/Architecture.md` and the playbook's Phase 15 for planned
future enhancements. The `addons` module is structured so these can be added
without breaking existing students.
