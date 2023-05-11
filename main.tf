// EKS Tools configuration

data "aws_region" "current" {}

data "aws_eks_cluster" "eks-cluster" {
  name = var.eks_cluster_name
}

locals {
  oidc = {
    url = replace(var.iam_oidc_provider_url, "https://", "")
    arn = var.iam_oidc_provider_arn
  }
}

// AWS Load Balancer Controller Installation

module "alb_controller" {
  source  = "Young-ook/eks/aws//modules/lb-controller"
  version = "1.7.10"

  oidc = local.oidc
  helm = {
    vars = {
      clusterName = var.eks_cluster_name
    }
  }
}


// AWS External DNS Ingress Controller Installation

module "external_dns" {
  source  = "lablabs/eks-external-dns/aws"
  version = "1.1.1"

  cluster_identity_oidc_issuer     = data.aws_eks_cluster.eks-cluster.identity[0].oidc[0].issuer
  cluster_identity_oidc_issuer_arn = var.iam_oidc_provider_arn

  settings = {
    "domainFilters[0]" = var.domain
  }
}


// AWS Container Inshights Installation

module "container-insights" {
  source  = "Young-ook/eks/aws//modules/container-insights"
  version = "1.7.10"

  cluster_name = data.aws_eks_cluster.eks-cluster.name
  oidc         = local.oidc
  features = {
    enable_metrics = var.enable-metrics
    enable_logs    = var.enable-logs
  }
}


// Metrics server Installation (for Horizontal Pod Autoscaler)

module "metrics-server" {
  source  = "Young-ook/eks/aws//modules/metrics-server"
  version = "1.7.10"

  oidc = local.oidc
  helm = {
    repository = "https://kubernetes-sigs.github.io/metrics-server/"
    version    = "3.8.2"
  }
}


// Karpenter Installation
// Inspired from: https://karpenter.sh/v0.22.1/getting-started/getting-started-with-terraform/

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "19.5.1"

  cluster_name = var.eks_cluster_name

  irsa_oidc_provider_arn          = var.iam_oidc_provider_arn
  irsa_namespace_service_accounts = ["karpenter:karpenter"]

  # Since Karpenter is running on an EKS Managed Node group,
  # we can re-use the role that was created for the node group
  create_iam_role = false
  iam_role_arn    = var.eks-node-group-iam-role-arn

  create_irsa = true
  # due to names too long we need to provide short ones
  irsa_name = substr("KarpenterIRSA-${var.eks_cluster_name}", 0, 37)
}

provider "aws" {
  region = "us-east-1"
  alias  = "virginia"
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}

resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true

  name                = "karpenter"
  repository          = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart               = "karpenter"
  version             = "v0.24.0"

  set {
    name  = "settings.aws.clusterName"
    value = var.eks_cluster_name
  }

  set {
    name  = "settings.aws.clusterEndpoint"
    value = data.aws_eks_cluster.eks-cluster.endpoint
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.karpenter.irsa_arn
  }

  set {
    name  = "settings.aws.defaultInstanceProfile"
    value = module.karpenter.instance_profile_name
  }

  set {
    name  = "settings.aws.interruptionQueueName"
    value = module.karpenter.queue_name
  }
}

# Workaround - https://github.com/hashicorp/terraform-provider-kubernetes/issues/1380#issuecomment-967022975
# Use all instance types as fallback
resource "kubectl_manifest" "karpenter_provisioner" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1alpha5
    kind: Provisioner
    metadata:
      name: default
    spec:
      consolidation:
        enabled: true
      weight: 1
      ttlSecondsUntilExpired: 604800
      requirements:
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["t", "c", "m", "r"]
# Blocklist for instance types that give us problems in the past
        - key: node.kubernetes.io/instance-type
          operator: NotIn
          values: ["m1.small"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
      limits:
        resources:
          cpu: 64
      provider:
        subnetSelector:
          karpenter.sh/discovery: "true"
        securityGroupSelector:
          aws-ids: ${data.aws_eks_cluster.eks-cluster.vpc_config[0].cluster_security_group_id}
        tags:
          karpenter.sh/discovery: ${var.eks_cluster_name}
  YAML

  depends_on = [
    helm_release.karpenter
  ]
}

# Workaround - https://github.com/hashicorp/terraform-provider-kubernetes/issues/1380#issuecomment-967022975
# provisioner with cheapest instance types
resource "kubectl_manifest" "karpenter_provisioner_cheap" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1alpha5
    kind: Provisioner
    metadata:
      name: cheap-instances
    spec:
      consolidation:
        enabled: true
      weight: 100
      ttlSecondsUntilExpired: 604800
      requirements:
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["t", "c", "m", "r"]
        - key: karpenter.k8s.aws/instance-size
          operator: In
          values: ["nano", "micro", "small", "medium"]
# Blocklist for instance types that give us problems in the past
        - key: node.kubernetes.io/instance-type
          operator: NotIn
          values: ["m1.small"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
      limits:
        resources:
          cpu: 64
      provider:
        subnetSelector:
          karpenter.sh/discovery: "true"
        securityGroupSelector:
          aws-ids: ${data.aws_eks_cluster.eks-cluster.vpc_config[0].cluster_security_group_id}
        tags:
          karpenter.sh/discovery: ${var.eks_cluster_name}
  YAML

  depends_on = [
    helm_release.karpenter
  ]
}
