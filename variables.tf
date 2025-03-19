variable "iam_oidc_provider" {
  description = "The IAM OIDC provider associated with the EKS cluster"
  type = object({
    arn = string
    url = string
  })
}

variable "eks" {
  description = "The EKS cluster where you want to install the tools"
  type = object({
    cluster_name                    = string
    cluster_version                 = string
    cluster_iam_authenticator_token = string # The token used by the Kubernetes provider to authenticate with the EKS cluster
    cluster_endpoint                = string
    cluster_ca_certificate          = string # The CA certificate for the EKS cluster, obtained by decoding the base64-encoded certificate authority data from the EKS cluster resource.
    cluster_worker_node_role_arn    = string # The IAM role ARN of the EKS node group, required by Karpenter to provision new nodes
    cluster_vpc_id                  = string
    cluster_security_group_id       = string
  })
}

variable "name_prefix" {
  description = "A prefix that will be prepended to the names of AWS resources created by this module"
  type        = string
}

variable "domain" {
  description = "The domain name for External DNS to listen for changes"
  type        = string
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
}

variable "region" {
  description = "The AWS region where the EKS cluster will be deployed"
  type        = string
}
