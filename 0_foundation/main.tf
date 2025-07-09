locals {
  cluster_name = "cluster-prod"
  tags = {
    "karpenter.sh/discovery" = local.cluster_name
    "author"                 = "majid"
  }
}
variable "domain" {
  description = "AWS Route53 hosted zone domain name"
  type        = string
  default = "terraform-k8s-mumajid"
}

# data "aws_route53_zone" "default" {
#   name = var.domain
# }

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.2.0"

  name = local.cluster_name
  cidr = "10.0.0.0/16" # group of IPs in our network (vpc)

  azs             = ["eu-north-1a", "eu-north-1b", "eu-north-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  intra_subnets   = ["10.0.51.0/24", "10.0.52.0/24", "10.0.53.0/24"]

  enable_nat_gateway = true # one-way door for nodes to allow outbound traffic, but block inbound public traffic

  tags = local.tags
}

module "cluster" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.20"

  cluster_name    = local.cluster_name
  cluster_version = "1.27"

  cluster_endpoint_public_access = true # important

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets # workers in private subnet -> no internet access
  control_plane_subnet_ids = module.vpc.intra_subnets  # put the control plane in the intra subnet from the vpc module

  eks_managed_node_groups = {
    default = {
      iam_role_name            = "node-${local.cluster_name}"
      iam_role_use_name_prefix = false
      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
      }

      ami_type = "BOTTLEROCKET_x86_64"
      platform = "bottlerocket"

      min_size     = 2
      desired_size = 2
      max_size     = 5

      instance_types = ["t3.xlarge"]
    }
  }

  tags = local.tags
}

# IAM roles (irsa = IAM Roles for Service Accounts)

module "cert_manager_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.32.0"

  role_name                     = "cert-manager"
  attach_cert_manager_policy    = true
  # cert_manager_hosted_zone_arns = [data.aws_route53_zone.default.arn]

  oidc_providers = {
    ex = {
      provider_arn               = module.cluster.oidc_provider_arn
      namespace_service_accounts = ["kube-system:cert-manager"]
    }
  }

  tags = local.tags
}

module "external_secrets_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.32.0"

  role_name                           = "secret-store"
  attach_external_secrets_policy      = true
  external_secrets_ssm_parameter_arns = ["arn:aws:ssm:*:*:parameter/${local.cluster_name}-*"] # clusters can only access their secrets (secret store paramters startsWith clusterName)

  oidc_providers = {
    ex = {
      provider_arn               = module.cluster.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:secret-store"] # ServiceAccount assuming this role exists in external-secrets namespace, the ServiceAccount name is secret-store
    }
  }

  tags = local.tags
}