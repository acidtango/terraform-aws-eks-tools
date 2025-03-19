##############################################
### Helm Charts Tools Installation
##############################################

# AWS Load Balancer Controller Installation 
resource "helm_release" "alb_ingress_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.11"

  values = [
    <<-EOT
    clusterName: ${var.eks.cluster_name}
    serviceAccount:
      create: false
      name: ${kubernetes_service_account.aws_lb_controller_sa.metadata[0].name}
      annotations:
        eks.amazonaws.com/role-arn: ${aws_iam_role.aws_lb_controller_role.arn}
    vpcId: ${var.eks.cluster_vpc_id}
    region: ${var.region}
    EOT
  ]
}

# External DNS Ingress Controller Installation (for Route 53)
resource "helm_release" "external_dns" {
  name       = "external-dns"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = "1.15.2"

  values = [
    <<-EOT
    txtOwnerId: "${var.eks.cluster_name}"
    domainFilters:
      - "${var.domain}"
    policy: sync
    logLevel: debug
    sources:
      - ingress
      - service
    serviceAccount:
      create: false
      name: ${kubernetes_service_account.aws_external_dns_sa.metadata[0].name}
      annotations:
        eks.amazonaws.com/role-arn: ${aws_iam_role.aws_external_dns_role.arn}
    EOT
  ]
}

# Metrics Server Installation (for Horizontal Pod Autoscaler)
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.12.2"
}

# AWS Container Insights Installation (CloudWatch Logs and Metrics)
resource "helm_release" "container_insights" {
  name       = "container-insights"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-for-fluent-bit"
  version    = "0.1.34"
}



##############################################
### Karpenter Installation
##############################################

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "20.34.0"

  cluster_name = var.eks.cluster_name

  # This variables change to true (by default) in the next breaking changes
  enable_v1_permissions           = true
  create_pod_identity_association = true

  irsa_oidc_provider_arn          = var.iam_oidc_provider.arn
  irsa_namespace_service_accounts = ["karpenter:karpenter"]

  create_node_iam_role          = false
  node_iam_role_arn             = var.eks.cluster_worker_node_role_arn
  node_iam_role_use_name_prefix = false

  # Error: creating EKS Access Entry ResourceInUseException: The specified access entry resource is already in use on this cluster.
  # https://github.com/terraform-aws-modules/terraform-aws-eks/blob/master/docs/UPGRADE-20.0.md#authentication_mode--api_and_config_map
  create_access_entry = false

  enable_irsa             = true
  create_instance_profile = true

  iam_role_use_name_prefix = false
  iam_role_name            = "KarpenterIRSA-${var.eks.cluster_name}"
  iam_role_description     = "Karpenter IAM role for service account"
  iam_policy_name          = "KarpenterIRSA-${var.eks.cluster_name}"
  iam_policy_description   = "Karpenter IAM role for service account"

  tags = var.tags
}



##############################################
### Karpenter Helm Chart Installation
##############################################

resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true

  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.3.3"


  values = [
    <<-EOT
    settings:
      clusterName: ${var.eks.cluster_name}
      clusterEndpoint: ${var.eks.cliuster_endpoint}
      defaultInstanceProfile: ${module.karpenter.instance_profile_name}
      interruptionQueueName: ${module.karpenter.queue_name}
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: ${module.karpenter.iam_role_arn}
    EOT
  ]
}



##############################################
### Kubernetes Manifests for Karpenter
##############################################

# Karpenter NodeClass to define the EC2 instance type and AMI
resource "kubectl_manifest" "karpenter_nodeclass_default" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      amiSelectorTerms:
        - alias: al2023@latest
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: "true"
      securityGroupSelectorTerms:
        - id: ${var.eks.cluster_security_group_id}
      role: "${var.eks.cluster_worker_node_role_arn}"
      tags:
        "Name": "karpenter-node"
        "karpenter.sh/discovery": "true"
  YAML

  depends_on = [helm_release.karpenter]
}

# Karpenter NodePool to define the requirements for the default EC2 instances
resource "kubectl_manifest" "karpenter_nodepool_default" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: default
    spec:
      weight: 20
      template:
        spec:
          expireAfter: 168h
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
          requirements:
            - key: karpenter.k8s.aws/instance-category
              operator: In
              values: ["t", "c", "m", "r"]
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
          cpu: "32"
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 5m
  YAML

  depends_on = [kubectl_manifest.karpenter_nodeclass_default]
}

# Karpenter NodePool to define the requirements for the cheap EC2 instances
resource "kubectl_manifest" "karpenter_nodepool_cheap" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: cheap-instances
    spec:
      weight: 50
      template:
        spec:
          expireAfter: 168h
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
          requirements:
            - key: karpenter.k8s.aws/instance-category
              operator: In
              values: ["t", "c", "m", "r"]
            - key: karpenter.k8s.aws/instance-size
              operator: In
              values: ["nano", "micro", "small", "medium"]
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
          cpu: "32"
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 5m
  YAML

  depends_on = [kubectl_manifest.karpenter_nodeclass_default]
}
