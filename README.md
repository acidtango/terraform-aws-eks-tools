# Terraform AWS EKS Tools

This Terraform module deploys various tools on an Amazon EKS cluster using Helm Charts and Kubernetes Manifests.

## Requirements

- Terraform `>= 1.11.2`
- AWS Provider `>= 5.0`
- Kubernetes Provider `>= 2.0`
- Helm Provider `>= 2.0`
- Kubectl Provider `>= 1.0`

## Deployed Resources

This module installs and configures the following resources:

### Helm Charts

| Helm Chart                       | Version  | Description                                      |
| -------------------------------- | -------- | ------------------------------------------------ |
| **AWS Load Balancer Controller** | `1.13.3` | AWS load balancer controller for Kubernetes.     |
| **External DNS**                 | `1.15.2` | Automatically manages DNS records in Route 53.   |
| **Metrics Server**               | `3.12.2` | Provides support for pod auto-scaling (HPA).     |
| **AWS Container Insights**       | `0.1.34` | Logs and metrics in CloudWatch Logs.             |
| **Karpenter**                    | `1.3.3`  | Automatic node provisioning and scaling for EKS. |

### Kubernetes Manifests for Karpenter

- **EC2NodeClass**: Defines the EC2 instance type and AMI to use.
- **NodePool (default)**: Default node configuration.
- **NodePool (cheap-instances)**: Configuration for low-cost instances.

### IAM Roles and Policies

- **IAM Roles**:
  - `aws_lb_controller_role`: Role for AWS Load Balancer Controller.
  - `aws_external_dns_role`: Role for External DNS.
- **IAM Policies**:
  - `aws_lb_controller_policy`: Permissions to manage load balancers.
  - `aws_external_dns_policy`: Permissions to update DNS records.
- **Service Accounts**:
  - `aws_lb_controller_sa`: ServiceAccount for Load Balancer Controller.
  - `aws_external_dns_sa`: ServiceAccount for External DNS.

## Variables

| Name                          | Type        | Description                                                        |
| ----------------------------- | ----------- | ------------------------------------------------------------------ |
| `eks_cluster_name`            | string      | eks cluster name where you want to install this tools.             |
| `eks-node-group-iam-role-arn` | string      | karpenter needs the node group iam role arn to create new nodes    |
| `iam_oidc_provider_arn`       | object      | identity issuer of eks cluster you want to install external dns.   |
| `iam_oidc_provider_url`       | string      | identity issuer of eks cluster you want to install some tools url. |
| `domain`                      | string      | domain for external dns to listen for changes.                     |
| `enable-metrics`              | bool        | A conditional indicator to enable container insights metrics       |
| `enable-logs`                 | bool        | A conditional indicator to enable container insights logs.         |
| `tags`                        | map(string) | A map of tags to add to all resources.                             |

## Usage

Example usage of the module:

```hcl
module "eks-tools" {
  source = "git::https://github.com/acidtango/terraform-aws-eks-tools?ref=main"

  eks_cluster_name            = "my-cluster"
  iam_oidc_provider_arn       = module.eks-cluster.iam-oidc-provider-arn
  iam_oidc_provider_url       = module.eks-cluster.iam-oidc-provider-url
  eks-node-group-iam-role-arn = module.eks-cluster.eks-node-group-iam-role-arn
  domain                      = "example.com"
  enable-metrics              = false
  tags                        = { "Environment" = "staging", "CreatedBy"   = "Acidtango" }
}
```

## References

- [AWS Load Balancer Controller](https://github.com/aws/eks-charts/tree/master/stable/aws-load-balancer-controller)
- [External DNS](https://github.com/kubernetes-sigs/external-dns)
- [Metrics Server](https://github.com/kubernetes-sigs/metrics-server)
- [Karpenter](https://karpenter.sh/)
- [Terraform AWS EKS Module](https://github.com/terraform-aws-modules/terraform-aws-eks)
