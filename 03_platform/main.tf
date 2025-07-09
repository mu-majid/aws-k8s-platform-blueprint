# Looks up the ingress-nginx-controller service in your EKS cluster
# Retrieves the AWS Load Balancer hostname (something like abc123-456789.us-west-2.elb.amazonaws.com)
data "kubernetes_service_v1" "ingress_service" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }
}
# Sets your domain name as a reusable variable
# Defaults to terraform-aws-platform.xyz
variable "domain" {
  description = "AWS Route53 hosted zone domain name"
  type        = string
  default = "terraform-aws-platform.xyz"
}

variable "email" {
  description = "Letsencrypt email"
  type        = string
}
# Finds your existing Route53 hosted zone for the domain
# Gets the zone ID needed to create DNS records
data "aws_route53_zone" "default" {
  name = var.domain
}

# SECTION 1

# Creating the DNS record to map the domain to ingress IP
# Creates a CNAME record: app.terraform-aws-platform.xyz
# Points to your ingress controller's load balancer hostname
# TTL of 300 seconds (5 minutes)
resource "aws_route53_record" "ingress_record" {
  zone_id = data.aws_route53_zone.default.zone_id
  name    = "app.${var.domain}"
  type    = "CNAME"
  ttl     = "300"
  records = [
    data.kubernetes_service_v1.ingress_service.status.0.load_balancer.0.ingress.0.hostname
  ]
}

# SECTION 2

# Deploys a cert-manager ClusterIssuer into your Kubernetes cluster
# ClusterIssuer = cluster-wide certificate authority that can issue SSL certificates
# solvers http01 -> let's encrypt way of checking that we own the domain -> it send a challenge and expects our response
#HTTP-01: Proves domain ownership by serving a file at /.well-known/acme-challenge/
# Nginx ingress: Uses your ingress controller to serve the challenge file
# Let's Encrypt hits http://app.terraform-aws-platform.xyz/.well-known/acme-challenge/xyz to verify you own the domain
resource "kubernetes_manifest" "cert_issuer" {
  manifest = yamldecode(<<YAML
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${var.email}
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            ingressClassName: nginx
  YAML
  )

  depends_on = [
    aws_route53_record.ingress_record
  ]
}

# SECTION 3
data "aws_caller_identity" "current" {}
resource "kubernetes_service_account_v1" "secret_store" { # service account -> will use role created in foundation
  metadata {
    namespace = "external-secrets"
    name      = "secret-store"
    annotations = {
      "eks.amazonaws.com/role-arn" = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/secret-store"
    }
  }
}

# Deploys an external-secrets ClusterSecretStore into your Kubernetes cluster
# ClusterSecretStore = cluster-wide connection to external secret management system

# Provider: Connects to AWS Parameter Store (not Secrets Manager)
# Region: Frankfurt region (eu-central-1)
# Purpose: Retrieves secrets from AWS Parameter Store and syncs them to Kubernetes

# JWT Auth: Uses IAM Roles for Service Accounts (IRSA)
# Service Account: secret-store in external-secrets namespace
# How it works: This service account has AWS permissions to read Parameter Store values
resource "kubernetes_manifest" "cluster_secret_store" {
  manifest = yamldecode(<<YAML
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-store
spec:
  provider:
    aws:
      service: ParameterStore
      region: eu-central-1
      auth:
        jwt:
          serviceAccountRef:
            namespace: external-secrets
            name: secret-store
  YAML
  )

  depends_on = [
    kubernetes_service_account_v1.secret_store
  ]
}