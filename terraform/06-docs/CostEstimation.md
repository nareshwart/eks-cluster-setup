# Cost Estimation (per cluster, us-east-2, approximate)

| Resource | Qty | Approx. hourly | Notes |
|---|---|---|---|
| EKS cluster control plane | 1 | $0.10 | Standard support |
| t3.medium worker node | 3 | ~$0.0416 each (~$0.125 total) | On-Demand, default node count |
| NAT Gateway (optional) | 0-1 | ~$0.045 + data | Disabled by default |
| EBS gp3 volumes | ~3x20GB | ~$0.0016/hr per 20GB | Default node root volumes |
| CloudWatch Logs (optional) | 0 | ~$0.50/GB ingested | Disabled by default |

**Estimated per-student cost with defaults (no NAT, no CW logs): ~$0.25-0.30/hour.**

For a full-day (8h) training with 30 students: **~$60-72/day**.

Always run `./automation/destroy-all.sh` at the end of each training day —
resources are tagged `AutoDestroy=true` specifically to make this safe and
easy to audit with `./scripts/cost-summary.sh`.
