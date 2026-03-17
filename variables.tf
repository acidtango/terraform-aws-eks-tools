variable "domain" {
  description = "Domain for ExternalDNS to listen for changes"
  type        = string
}

variable "eks_cluster_name" {
  description = "EKS cluster name where tools will be installed"
  type        = string
}

variable "eks_node_group_iam_role_arn" {
  description = "Node group IAM role ARN required by Karpenter to create new nodes"
  type        = string
}

variable "enable_logs" {
  description = "Enable Container Insights logs via Fluent Bit"
  type        = bool
  default     = true
}

variable "enable_metrics" {
  description = "Enable Container Insights metrics via CloudWatch Agent"
  type        = bool
  default     = true
}

variable "iam_oidc_provider_arn" {
  description = "OIDC provider ARN for the EKS cluster"
  type        = string
}

variable "iam_oidc_provider_url" {
  description = "OIDC provider URL for the EKS cluster"
  type        = string
}

variable "log_retention_in_days" {
  description = "Retention period in days for CloudWatch log group"
  type        = number
  default     = 90

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days)
    error_message = "log_retention_in_days must be one of: 0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653."
  }
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default = {
    "ToolsVersion" = "1.33.0"
    "CreatedBy"    = "Acidtango"
    "ManagedBy"    = "Terraform"
  }
}
