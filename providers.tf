provider "aws" {
  region = var.region

  default_tags {
    tags = var.tags
  }
}

provider "kubernetes" {
  host                   = var.eks.cluster_endpoint
  token                  = var.eks.cluster_iam_authenticator_token
  cluster_ca_certificate = var.eks.cluster_ca_certificate
}

provider "helm" {
  kubernetes {
    host                   = var.eks.cluster_endpoint
    token                  = var.eks.cluster_iam_authenticator_token
    cluster_ca_certificate = var.eks.cluster_ca_certificate
  }
}
