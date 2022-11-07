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
  oidc = local.oidc
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
  }
}


// Cluster autoscaler Installation

module "cluster-autoscaler" {
  source  = "Young-ook/eks/aws//modules/cluster-autoscaler"
  version = "1.7.10"

  oidc = local.oidc
  helm = {
    vars = {
      "autoDiscovery.clusterName" = data.aws_eks_cluster.eks-cluster.name
    }
  }
}
