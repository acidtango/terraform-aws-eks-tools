variable "eks_cluster_name" {
  description = "eks cluster name where you want to install this tools"
  type        = string
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

variable "enable-metrics" {
  description = "A conditional indicator to enable container insights metrics"
  type        = bool
  default     = true
}

variable "enable-logs" {
  description = "A conditional indicator to enable container insights logs"
  type        = bool
  default     = true
}

variable "eks-node-group-iam-role-name" {
  description = "karpenter needs the node group iam role to create new nodes"
}
