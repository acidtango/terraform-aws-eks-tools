// EKS Tools configuration

data "aws_region" "current" {}

data "aws_eks_cluster" "eks-cluster" {
  name = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "aws_iam_authenticator" {
  name = data.aws_eks_cluster.eks-cluster.name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.eks-cluster.endpoint
  token                  = data.aws_eks_cluster_auth.aws_iam_authenticator.token
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks-cluster.certificate_authority[0].data)
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.eks-cluster.endpoint
    token                  = data.aws_eks_cluster_auth.aws_iam_authenticator.token
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks-cluster.certificate_authority[0].data)
  }
}


// AWS Load Balancer Controller Installation

module "alb_controller" {
  source = "git::https://github.com/GSA/terraform-kubernetes-aws-load-balancer-controller?ref=v4.2.0gsa"

  k8s_cluster_type = "eks"
  k8s_namespace    = "kube-system"

  aws_region_name  = data.aws_region.current.name
  k8s_cluster_name = data.aws_eks_cluster.eks-cluster.name

  alb_controller_depends_on = [
    var.alb_controller_depends_on
  ]
}


// AWS External DNS Ingress Controller Installation

module "external_dns" {
  source  = "lablabs/eks-external-dns/aws"
  version = "0.6.1"

  cluster_name                     = data.aws_eks_cluster.eks-cluster.name
  cluster_identity_oidc_issuer     = data.aws_eks_cluster.eks-cluster.identity[0].oidc[0].issuer
  cluster_identity_oidc_issuer_arn = var.iam_oidc_provider_arn

  settings = {
    "domainFilters[0]" = var.domain
  }
}


// AWS Container Inshights Installation

module "container-insights" {
  source  = "Young-ook/eks/aws//modules/container-insights"
  version = "1.4.16"

  cluster_name = data.aws_eks_cluster.eks-cluster.name
  oidc = {
    url = replace(var.iam_oidc_provider_url, "https://", "")
    arn = var.iam_oidc_provider_arn
  }
}


// Metrics server Installation (for Horizontal Pod Autoscaler)

module "metrics-server" {
  source  = "Young-ook/eks/aws//modules/metrics-server"
  version = "1.4.16"

  cluster_name = data.aws_eks_cluster.eks-cluster.name
  oidc = {
    url = replace(var.iam_oidc_provider_url, "https://", "")
    arn = var.iam_oidc_provider_arn
  }
}


// Cluster autoscaler Installation

module "cluster-autoscaler" {
  source  = "Young-ook/eks/aws//modules/cluster-autoscaler"
  version = "1.4.16"

  cluster_name = data.aws_eks_cluster.eks-cluster.name
  oidc = {
    url = replace(var.iam_oidc_provider_url, "https://", "")
    arn = var.iam_oidc_provider_arn
  }
}
