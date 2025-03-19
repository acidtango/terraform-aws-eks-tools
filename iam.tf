# The Service Linked Role is required to allow AWS to manage EC2 Spot Instances on your behalf.
# Without this role, using Spot Instances may result in an error (`AuthFailure.ServiceLinkedRoleCreationNotPermitted`).
# https://karpenter.sh/docs/troubleshooting/#missing-service-linked-role
resource "aws_iam_service_linked_role" "spot" {
  aws_service_name = "spot.amazonaws.com"
}

##############################################
### AWS IAM Roles
##############################################

resource "aws_iam_role" "aws_lb_controller_role" {
  name = "${var.name_prefix}-aws-lb-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Federated = var.iam_oidc_provider.arn
      },
      Action = "sts:AssumeRoleWithWebIdentity",
      Condition = {
        StringEquals = {
          "${replace(var.iam_oidc_provider.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role" "aws_external_dns_role" {
  name = "${var.name_prefix}-aws-external-dns-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Federated = var.iam_oidc_provider.arn
      },
      Action = "sts:AssumeRoleWithWebIdentity",
      Condition = {
        StringEquals = {
          "${replace(var.iam_oidc_provider.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:external-dns"
        }
      }
    }]
  })

  tags = var.tags
}

##############################################
### AWS IAM Policies
##############################################

resource "aws_iam_policy" "aws_lb_controller_policy" {
  name   = "${var.name_prefix}-AWSLoadBalancerControllerIAMPolicy"
  policy = file("${path.module}/alb_iam_policy.json")
}

resource "aws_iam_policy" "aws_external_dns_policy" {
  name = "${var.name_prefix}-AllowExternalDNSUpdates"
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

##############################################
### AWS IAM Role Policy Attachments
##############################################

resource "aws_iam_role_policy_attachment" "aws_lb_controller_policy_attach" {
  role       = aws_iam_role.aws_lb_controller_role.name
  policy_arn = aws_iam_policy.aws_lb_controller_policy.arn
}

resource "aws_iam_role_policy_attachment" "aws_external_dns_policy_attach" {
  role       = aws_iam_role.aws_external_dns_role.name
  policy_arn = aws_iam_policy.aws_external_dns_policy.arn
}

##############################################
### Kubernetes Service Accounts
##############################################

resource "kubernetes_service_account" "aws_lb_controller_sa" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.aws_lb_controller_role.arn
    }
  }
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
