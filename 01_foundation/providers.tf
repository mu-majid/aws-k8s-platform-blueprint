terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.0.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.24.0"
    }
  }
  # used for terraform state management
  # Needs to be created manually, before running terraform init
  backend "s3" { 
    bucket = "terraform-k8s-platform-app"
    key    = "aws/00_foundations"
    region = "eu-central-1"
  }
}

provider "aws" {
  region = "eu-central-1"
}

provider "kubernetes" {
  host                   = module.cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.cluster.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.cluster.cluster_name]
  }
}