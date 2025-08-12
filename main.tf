data "aws_region" "current" {}

data "aws_eks_cluster" "eks_cluster" {
  name = var.eks_cluster_name
}


##############################################
### AWS Load Balancer Controller
##############################################

resource "aws_iam_role" "aws_lb_controller_role" {
  name = "${var.eks_cluster_name}-aws-lb-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Federated = var.iam_oidc_provider_arn
      },
      Action = "sts:AssumeRoleWithWebIdentity",
      Condition = {
        StringEquals = {
          "${replace(var.iam_oidc_provider_url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_policy" "aws_lb_controller_policy" {
  name   = "${var.eks_cluster_name}-AWSLoadBalancerControllerIAMPolicy"
  policy = file("${path.module}/iam_policy.json")
}

resource "aws_iam_role_policy_attachment" "aws_lb_controller_policy_attach" {
  role       = aws_iam_role.aws_lb_controller_role.name
  policy_arn = aws_iam_policy.aws_lb_controller_policy.arn
}

resource "kubernetes_service_account" "aws_lb_controller_sa" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.aws_lb_controller_role.arn
    }
  }
}

resource "helm_release" "alb_ingress_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.13.4"

  values = [
    <<-EOT
    clusterName: ${var.eks_cluster_name}
    serviceAccount:
      create: false
      name: ${kubernetes_service_account.aws_lb_controller_sa.metadata[0].name}
      annotations:
        eks.amazonaws.com/role-arn: ${aws_iam_role.aws_lb_controller_role.arn}
    vpcId: ${data.aws_eks_cluster.eks_cluster.vpc_config[0].vpc_id}
    region: ${data.aws_region.current.name}
    EOT
  ]
}


##############################################
### Kubernetes ExternalDNS
##############################################

resource "aws_iam_role" "aws_external_dns_role" {
  name = "${var.eks_cluster_name}-aws-external-dns-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Federated = var.iam_oidc_provider_arn
      },
      Action = "sts:AssumeRoleWithWebIdentity",
      Condition = {
        StringEquals = {
          "${replace(var.iam_oidc_provider_url, "https://", "")}:sub" = "system:serviceaccount:kube-system:external-dns"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_policy" "aws_external_dns_policy" {
  name = "${var.eks_cluster_name}-AllowExternalDNSUpdates"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets"
        ]
        Resource = "arn:aws:route53:::hostedzone/*"
      },
      {
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets",
          "route53:ListTagsForResource"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "aws_external_dns_policy_attach" {
  role       = aws_iam_role.aws_external_dns_role.name
  policy_arn = aws_iam_policy.aws_external_dns_policy.arn
}


resource "kubernetes_service_account" "aws_external_dns_sa" {
  metadata {
    name      = "external-dns"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.aws_external_dns_role.arn
    }
  }
}

resource "helm_release" "external_dns" {
  name       = "external-dns"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = "1.18.0"

  values = [
    <<-EOT
    txtOwnerId: "${var.eks_cluster_name}"
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


##############################################
### AWS for fluent bit
##############################################

# TODO: Improve this helm release to use custom service account and log group
resource "helm_release" "container_insights_logs" {
  count      = var.enable_logs ? 1 : 0
  name       = "container-insights-logs"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-for-fluent-bit"
  version    = "0.1.35"
}

// This helm is not working
#resource "helm_release" "container_insights_metrics" {
#  count      = var.enable-metrics ? 1 : 0
#  name       = "container-insights-metrics"
#  namespace  = "kube-system"
#  repository = "https://aws.github.io/eks-charts"
#  chart      = "aws-cloudwatch-metrics"
#  version    = "0.0.11"
#  #values = [
#  #  <<-EOT
#  #  clusterName: "${var.eks_cluster_name}"
#  #  EOT
#  #]
#}


// Metrics server Installation (for Horizontal Pod Autoscaler)

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.13.0"
}


##############################################
### Karpenter
##############################################

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "20.37.2"

  cluster_name = var.eks_cluster_name

  # This variables change to true (by default) in the next breaking changes
  enable_v1_permissions           = true
  create_pod_identity_association = true

  irsa_oidc_provider_arn          = var.iam_oidc_provider_arn
  irsa_namespace_service_accounts = ["karpenter:karpenter"]

  create_node_iam_role          = false
  node_iam_role_arn             = var.eks_node_group_iam_role_arn
  node_iam_role_use_name_prefix = false

  # Error: creating EKS Access Entry ResourceInUseException: The specified access entry resource is already in use on this cluster.
  # https://github.com/terraform-aws-modules/terraform-aws-eks/blob/master/docs/UPGRADE-20.0.md#authentication_mode--api_and_config_map
  create_access_entry = false

  enable_irsa             = true
  create_instance_profile = true

  iam_role_use_name_prefix = false
  iam_role_name            = "KarpenterIRSA-${var.eks_cluster_name}"
  iam_role_description     = "Karpenter IAM role for service account"
  iam_policy_name          = "KarpenterIRSA-${var.eks_cluster_name}"
  iam_policy_description   = "Karpenter IAM role for service account"

  tags = var.tags
}

resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true

  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.4.0"


  values = [
    <<-EOT
    settings:
      clusterName: ${var.eks_cluster_name}
      clusterEndpoint: ${data.aws_eks_cluster.eks_cluster.endpoint}
      defaultInstanceProfile: ${module.karpenter.instance_profile_name}
      interruptionQueueName: ${module.karpenter.queue_name}
    serviceAccount:
      annotations:
        eks.amazonaws.com/role-arn: ${module.karpenter.iam_role_arn}
    EOT
  ]
}

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
        - id: ${data.aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id}
      role: "${var.eks_node_group_iam_role_arn}"
      tags:
        "Name": "karpenter-node"
        "karpenter.sh/discovery": "true"
  YAML

  depends_on = [helm_release.karpenter]
}

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
