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
| **AWS Load Balancer Controller** | `1.11`   | AWS load balancer controller for Kubernetes.     |
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

| Name                | Type        | Description                                        |
| ------------------- | ----------- | -------------------------------------------------- |
| `iam_oidc_provider` | object      | IAM OIDC provider associated with the EKS cluster. |
| `eks`               | object      | EKS cluster configuration.                         |
| `name_prefix`       | string      | Prefix for AWS resource names.                     |
| `domain`            | string      | Domain for External DNS.                           |
| `tags`              | map(string) | Tags applied to resources.                         |
| `region`            | string      | AWS region where the cluster is deployed.          |

## Usage

Example usage of the module:

```hcl
module "eks_tools" {
  source = "git::https://github.com/acidtango/terraform-aws-eks-tools?ref=1.32.0"
  eks = {
    cluster_name                    = "my-cluster"
    cluster_version                 = "1.32"
    cluster_iam_authenticator_token = data.aws_eks_cluster_auth.aws_iam_auth.token
    cluster_endpoint                = aws_eks_cluster.eks_cluster.endpoint
    cluster_ca_certificate          = base64decode(aws_eks_cluster.eks_cluster.certificate_authority.0.data)
    cluster_worker_node_role_arn    = aws_iam_role.eks_worker_role.arn
    cluster_vpc_id                  = aws_eks_cluster.eks_cluster.vpc_config[0].vpc_id"
    cluster_security_group_id       = aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id
  }
  region      = "eu-west-1"
  name_prefix = "tf-my-cluster"
  domain      = "example.com"
  tags        = { "Environment" = "staging", "CreatedBy"   = "Acidtango" }
}
```

## References

- [AWS Load Balancer Controller](https://github.com/aws/eks-charts/tree/master/stable/aws-load-balancer-controller)
- [External DNS](https://github.com/kubernetes-sigs/external-dns)
- [Metrics Server](https://github.com/kubernetes-sigs/metrics-server)
- [Karpenter](https://karpenter.sh/)
- [Terraform AWS EKS Module](https://github.com/terraform-aws-modules/terraform-aws-eks)
