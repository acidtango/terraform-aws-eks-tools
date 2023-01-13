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
  version = "1.0.0"

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
    version = "3.8.2"
  }
}


// Karpenter Installation
// Inspired from: https://karpenter.sh/v0.5.3/getting-started-with-terraform/
// and from: https://github.com/terraform-aws-modules/terraform-aws-eks/blob/v18.30.3/examples/karpenter/main.tf

data "aws_iam_policy" "ssm_managed_instance" {
  arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "karpenter_ssm_policy" {
  role       = var.eks-node-group-iam-role-name
  policy_arn = data.aws_iam_policy.ssm_managed_instance.arn
}

resource "aws_iam_instance_profile" "karpenter" {
  name = "KarpenterNodeInstanceProfile-${var.eks_cluster_name}"
  role = var.eks-node-group-iam-role-name
}

module "iam_assumable_role_karpenter" {
  source                        = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version                       = "4.7.0"
  create_role                   = true
  role_name                     = substr("karpenter-controller-${var.eks_cluster_name}", 0, 64)
  provider_url                  = local.oidc.url
  oidc_fully_qualified_subjects = ["system:serviceaccount:karpenter:karpenter"]
}

resource "aws_iam_role_policy" "karpenter_controller" {
  name = "karpenter-policy-${var.eks_cluster_name}"
  role = module.iam_assumable_role_karpenter.iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:CreateLaunchTemplate",
          "ec2:CreateFleet",
          "ec2:RunInstances",
          "ec2:CreateTags",
          "iam:PassRole",
          "ec2:TerminateInstances",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeAvailabilityZones",
          "ssm:GetParameter"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true

  name       = "karpenter"
  repository = "https://charts.karpenter.sh"
  chart      = "karpenter"
  version    = "v0.5.3"

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.iam_assumable_role_karpenter.iam_role_arn
  }

  set {
    name  = "controller.clusterName"
    value = var.eks_cluster_name
  }

  set {
    name  = "controller.clusterEndpoint"
    value = data.aws_eks_cluster.eks-cluster.endpoint
  }
}

# Workaround - https://github.com/hashicorp/terraform-provider-kubernetes/issues/1380#issuecomment-967022975
# Use all instance types as fallback and default
resource "kubectl_manifest" "karpenter_provisioner" {
  yaml_body = <<-YAML
  apiVersion: karpenter.sh/v1alpha5
  kind: Provisioner
  metadata:
    name: default
  spec:
    consolidation:
      enabled: true
    ttlSecondsUntilExpired: 604800
    ttlSecondsAfterEmpty: 30
    weight: 0
    requirements:
      - key: karpenter.sh/capacity-type
        operator: In
        values: ["spot", "on-demand"]
      - key: "kubernetes.io/arch"
        operator: In
        values: ["arm64", "amd64"]
    limits:
      resources:
        cpu: 32
    provider:
      instanceProfile: KarpenterNodeInstanceProfile-${var.eks_cluster_name}
      subnetSelector:
        Tier: Private
  YAML

  depends_on = [
    helm_release.karpenter
  ]
}

# See: https://github.com/aws/karpenter/issues/2916#issuecomment-1351278527
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
    ttlSecondsUntilExpired: 604800
    ttlSecondsAfterEmpty: 30
    weight: 100
    requirements:
      - key: "node.kubernetes.io/instance-type"
        operator: In
        values: ["t3a.small", "t3.small"]
      - key: karpenter.sh/capacity-type
        operator: In
        values: ["spot", "on-demand"]
    limits:
      resources:
        cpu: 32
    provider:
      instanceProfile: KarpenterNodeInstanceProfile-${var.eks_cluster_name}
      subnetSelector:
        Tier: Private
  YAML

  depends_on = [
    helm_release.karpenter
  ]
}
