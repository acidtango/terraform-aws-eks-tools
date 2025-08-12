# Terraform AWS EKS Tools

This Terraform module installs and configures a curated set of operational tools on an existing **Amazon EKS** cluster by combining **Helm charts**, **Kubernetes manifests**, and the necessary **IAM** resources.

## Requirements

- Terraform `>= 1.12`
- AWS Provider `>= 5.0`
- Kubernetes Provider `>= 2.0`
- Helm Provider `>= 3.0`
- Kubectl Provider `>= 1.0`

## What gets installed?

### Helm Charts

| Helm Chart                                              | Version  | Purpose                                                                    |
| ------------------------------------------------------- | -------- | -------------------------------------------------------------------------- |
| **AWS Load Balancer Controller**                        | `1.13.4` | Manages LBs (ALB/NLB) for Kubernetes Ingress / Service objects.            |
| **External DNS**                                        | `1.18.0` | Creates/updates Route 53 records from Kubernetes resources.                |
| **Metrics Server**                                      | `3.13.0` | Exposes CPU / memory metrics needed by the HPA.                            |
| **AWS for Fluent Bit** (Container Insights Logs)        | `0.1.35` | Ships container logs to CloudWatch Logs (optional, see `enable_logs`).     |
| **AWS CloudWatch Metrics** (Container Insights Metrics) | `0.0.11` | Publishes node/pod metrics to CloudWatch (optional, see `enable_metrics`). |
| **Karpenter**                                           | `1.4.0`  | On-demand and spot node provisioning / consolidation.                      |

### Kubernetes Manifests (applied via kubectl)

- **EC2NodeClass** `default` – defines AMI, subnets and security groups for Karpenter-launched nodes.
- **NodePool** `default` – general-purpose pool, balanced across spot/on-demand.
- **NodePool** `cheap-instances` – cost-optimised pool restricted to _nano–medium_ instance sizes.

### IAM Roles & Policies

| Resource                                            | Purpose                                       |
| --------------------------------------------------- | --------------------------------------------- |
| `aws_lb_controller_role` + policy + service account | Permissions for AWS Load Balancer Controller. |
| `aws_external_dns_role` + policy + service account  | Route 53 permissions for External DNS.        |
| `aws_cw_agent_role` + policy                        | Bound to CloudWatch Agent (metrics).          |
| `karpenter` IRSA role & optional instance profile   | Allows Karpenter to provision EC2 instances.  |

All roles are configured through **IRSA** by annotating the corresponding Kubernetes service accounts.

---

## Variables

| Name                          | Type          | Default                                                                         | Description                                                             |
| ----------------------------- | ------------- | ------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| `eks_cluster_name`            | `string`      | –                                                                               | Name of the existing EKS cluster.                                       |
| `iam_oidc_provider_arn`       | `string`      | –                                                                               | OIDC provider ARN for IRSA.                                             |
| `iam_oidc_provider_url`       | `string`      | –                                                                               | OIDC issuer URL for IRSA.                                               |
| `domain`                      | `string`      | –                                                                               | Root domain that External DNS should manage.                            |
| `eks_node_group_iam_role_arn` | `string`      | –                                                                               | Node group or instance profile role used by Karpenter.                  |
| `enable_metrics`              | `bool`        | `false`                                                                         | Toggle installation of CloudWatch **metrics** (aws-cloudwatch-metrics). |
| `enable_logs`                 | `bool`        | `true`                                                                          | Toggle installation of CloudWatch **logs** (aws-for-fluent-bit).        |
| `tags`                        | `map(string)` | `{ ToolsVersion = "1.33.0", CreatedBy = "Acidtango", ManagedBy = "Terraform" }` | Tags applied to all AWS resources.                                      |

---

## Usage

Example usage of the module:

```hcl
module "eks_tools" {
  source = "git::https://github.com/acidtango/terraform-aws-eks-tools?ref=main"

  eks_cluster_name             = "my-cluster"
  iam_oidc_provider_arn        = module.eks.oidc_provider_arn
  iam_oidc_provider_url        = module.eks.oidc_provider_url
  eks_node_group_iam_role_arn  = module.eks.node_group_iam_role_arn
  domain                       = "example.com"

  enable_metrics = false   # disable CloudWatch Container Insights metrics
  enable_logs    = true    # keep logs enabled

  tags = {
    Environment = "staging"
    CreatedBy   = "Acidtango"
  }
}
```

## References & Documentation

- **AWS Load Balancer Controller** – <https://github.com/aws/eks-charts/tree/master/stable/aws-load-balancer-controller>
- **External DNS** – <https://github.com/kubernetes-sigs/external-dns/tree/master/charts/external-dns>
- **Metrics Server** – <https://github.com/kubernetes-sigs/metrics-server/tree/master/charts/metrics-server>
- **AWS for Fluent Bit** – <https://github.com/aws/eks-charts/tree/master/stable/aws-for-fluent-bit>
- **AWS CloudWatch Metrics** – <https://github.com/aws/eks-charts/tree/master/stable/aws-cloudwatch-metrics>
- **Karpenter** – <https://karpenter.sh/>
- **Terraform AWS EKS Module** – <https://github.com/terraform-aws-modules/terraform-aws-eks>

---
