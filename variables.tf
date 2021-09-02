variable "eks_cluster_name" {
  description = "eks cluster name where you want to install this tools"
  type        = string
}

variable "alb_controller_depends_on" {
  description = "objects you need to be created before alb controller should be deployed on"
}

variable "iam_oidc_provider_arn" {
  description = "identity issuer of eks cluster you want to install external dns"
}

variable "iam_oidc_provider_url" {
  description = "identity issuer of eks cluster you want to install some tools url"
}

variable "domain" {
  description = "domain for external dns to listen for changes"
}
