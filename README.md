# Terraform AWS EKS Tools

This Terraform module installs and configures a curated set of **production-ready operational tools** on an existing Amazon EKS cluster. It provides a comprehensive solution for cluster observability, autoscaling, ingress management, and DNS automation using industry-standard tools.

## Prerequisites

- **Existing EKS Cluster**: This module requires a pre-existing EKS cluster
- **OIDC Provider**: The EKS cluster must have an OIDC identity provider configured
- **Route 53 Hosted Zone**: Required for ExternalDNS functionality
- **Appropriate IAM Permissions**: The Terraform execution role must have sufficient permissions

## Requirements

- Terraform `~> 1.0`
- AWS Provider `~> 5.0`
- Kubernetes Provider `~> 2.0`
- Helm Provider `~> 3.0`
- Kubectl Provider `~> 1.0`

## What Gets Installed?

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

The module automatically creates the following Karpenter resources:

- **EC2NodeClass** `default`: Defines AMI selection, subnet discovery, and security groups
- **NodePool** `default`: General-purpose node pool with balanced spot/on-demand allocation
- **NodePool** `cheap-instances`: Cost-optimized pool for small workloads (nano–medium instances)

### IAM Resources

| IAM Role                  | Purpose                      | Permissions                              |
| ------------------------- | ---------------------------- | ---------------------------------------- |
| `aws-lb-controller-role`  | AWS Load Balancer Controller | ELB management, EC2 describe permissions |
| `aws-external-dns-role`   | ExternalDNS                  | Route 53 record management               |
| `aws-for-fluent-bit-role` | Fluent Bit logging           | CloudWatch Logs permissions              |
| `aws-cw-agent-role`       | CloudWatch metrics           | CloudWatch metrics publishing            |
| `karpenter-irsa-role`     | Karpenter                    | EC2 instance provisioning and management |

> All IAM roles use **IRSA** (IAM Roles for Service Accounts) for secure, temporary credential access.

## Input Variables

| Name                          | Type          | Default   | Required | Description                                                       |
| ----------------------------- | ------------- | --------- | -------- | ----------------------------------------------------------------- |
| `eks_cluster_name`            | `string`      | -         | ✅       | Name of the existing EKS cluster where tools will be installed    |
| `iam_oidc_provider_arn`       | `string`      | -         | ✅       | ARN of the OIDC identity provider associated with the EKS cluster |
| `iam_oidc_provider_url`       | `string`      | -         | ✅       | URL of the OIDC identity provider (used for IRSA trust policies)  |
| `domain`                      | `string`      | -         | ✅       | Root domain that ExternalDNS will manage (e.g., `example.com`)    |
| `eks_node_group_iam_role_arn` | `string`      | -         | ✅       | IAM role ARN used by EKS node groups (required by Karpenter)      |
| `enable_metrics`              | `bool`        | `true`    | ❌       | Enable CloudWatch Container Insights metrics collection           |
| `enable_logs`                 | `bool`        | `true`    | ❌       | Enable CloudWatch Container Insights log collection               |
| `tags`                        | `map(string)` | See below | ❌       | Tags applied to all AWS resources created by this module          |

### Default Tags

```hcl
{
  "ToolsVersion" = "1.33.0"
  "CreatedBy"    = "Acidtango"
  "ManagedBy"    = "Terraform"
}
```

## Usage Examples

### Basic Usage

```hcl
module "eks_tools" {
  source = "git::https://github.com/acidtango/terraform-aws-eks-tools.git?ref=1.33.0

  eks_cluster_name             = "my-production-cluster"
  iam_oidc_provider_arn        = module.eks.oidc_provider_arn
  iam_oidc_provider_url        = module.eks.cluster_oidc_issuer_url
  eks_node_group_iam_role_arn  = module.eks.eks_managed_node_groups["main"].iam_role_arn
  domain                       = "example.com"
}
```

### Advanced Usage with Custom Configuration

```hcl
module "eks_tools" {
  source = "git::https://github.com/acidtango/terraform-aws-eks-tools.git?ref=1.33.0

  eks_cluster_name             = "my-cluster"
  iam_oidc_provider_arn        = module.eks.oidc_provider_arn
  iam_oidc_provider_url        = module.eks.cluster_oidc_issuer_url
  eks_node_group_iam_role_arn  = module.eks.eks_managed_node_groups["main"].iam_role_arn
  domain                       = "staging.example.com"

  # Disable metrics collection to reduce costs
  enable_metrics = false
  # Keep logs enabled for debugging
  enable_logs    = true

  # Custom tags for cost allocation
  tags = {
    Environment = "staging"
    Team        = "platform"
    CostCenter  = "engineering"
    Project     = "k8s-infrastructure"
  }
}
```

## Karpenter Configuration

The module creates two pre-configured Karpenter NodePools:

### Default NodePool

- **Weight**: 20 (lower priority)
- **Instance Types**: t, c, m, r families (all sizes)
- **Capacity**: Both spot and on-demand
- **CPU Limit**: 32 cores
- **Consolidation**: Enabled with 5-minute wait time

### Cheap Instances NodePool

- **Weight**: 50 (higher priority)
- **Instance Types**: t, c, m, r families (nano, micro, small, medium only)
- **Capacity**: Both spot and on-demand
- **CPU Limit**: 32 cores
- **Consolidation**: Enabled with 5-minute wait time

> 💡 **Tip**: The cheap instances pool has higher weight, so Karpenter will prefer smaller, cost-effective instances when possible.

## References & Documentation

- **AWS Load Balancer Controller** – <https://github.com/aws/eks-charts/tree/master/stable/aws-load-balancer-controller>
- **External DNS** – <https://github.com/kubernetes-sigs/external-dns/tree/master/charts/external-dns>
- **Metrics Server** – <https://github.com/kubernetes-sigs/metrics-server/tree/master/charts/metrics-server>
- **AWS for Fluent Bit** – <https://github.com/aws/eks-charts/tree/master/stable/aws-for-fluent-bit>
- **AWS CloudWatch Metrics** – <https://github.com/aws/eks-charts/tree/master/stable/aws-cloudwatch-metrics>
- **Karpenter** – <https://karpenter.sh/>
- **Terraform AWS EKS Module** – <https://github.com/terraform-aws-modules/terraform-aws-eks>

---

**Made with ❤️ by [Acidtango](https://acidtango.com)**
