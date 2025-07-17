# FinOps Layer - Cost Optimization and Resource Management
# This layer provides:
# 1. Real-time Kubernetes cost monitoring with OpenCost
# 2. Grafana integration for unified cost dashboards
# 3. Foundation for advanced autoscaling tools

locals {
  cluster_name = "cluster-prod"
  tags = {
    "karpenter.sh/discovery" = local.cluster_name
    "author"                 = "majid"
    "layer"                  = "finops"
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "kubernetes_namespace_v1" "observability" { # created in observability layer
  metadata {
    name = "observability"
  }
}

resource "helm_release" "opencost" {
  name             = "opencost"
  namespace        = data.kubernetes_namespace_v1.observability.metadata[0].name
  repository       = "https://opencost.github.io/opencost-helm-chart"
  chart            = "opencost"
  version          = "2.1.6"
  timeout          = 600
  atomic           = true
  create_namespace = false

  values = [
    <<YAML
# OpenCost configuration
opencost:
  exporter:
    # AWS configuration
    cloudProviderApiKey: "AIzaSyD29bGxmHAVEOBYtgd8sYM2uuzSETpm_hE"  # Default key for AWS pricing API
    
    # Resource requests and limits
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi
    
    # AWS specific configuration
    env:
      - name: AWS_REGION
        value: ${data.aws_region.current.name}
      - name: CLUSTER_ID
        value: ${local.cluster_name}
      
    # Enable cloud integration
    aws:
      # For now using local pricing data, can be enhanced with real AWS billing data
      serviceKeyName: ""
      
  # Enable Prometheus integration
  prometheus:
    # Connect to existing Prometheus in observability namespace
    external:
      enabled: true
      url: "http://kube-prometheus-stack-prometheus:9090"
    
    internal:
      enabled: false  # Use external Prometheus

# UI Configuration
ui:
  enabled: true
  
  # Resource limits for UI
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi

# Service Monitor for Prometheus integration
serviceMonitor:
  enabled: true
  additionalLabels:
    release: kube-prometheus-stack  # Match Prometheus operator label selector
  
# Network policy (if needed)
networkPolicy:
  enabled: false

# Annotations for cost allocation
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "9003"
  prometheus.io/path: "/metrics"
    YAML
  ]

  depends_on = [
    data.kubernetes_namespace_v1.observability
  ]
}

# Ingress for OpenCost UI (optional - can access via Grafana dashboards)
resource "kubernetes_ingress_v1" "opencost" {
  metadata {
    name      = "opencost"
    namespace = data.kubernetes_namespace_v1.observability.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer"                = "letsencrypt-prod"
      "nginx.ingress.kubernetes.io/rewrite-target"    = "/"
      "nginx.ingress.kubernetes.io/backend-protocol"  = "HTTP"
    }
  }
  
  spec {
    ingress_class_name = "nginx"
    
    tls {
      hosts = [
        "opencost.terraform-aws-platform.xyz",
      ]
      secret_name = "opencost-tls"
    }
    
    rule {
      host = "opencost.terraform-aws-platform.xyz"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "opencost"
              port {
                number = 9090
              }
            }
          }
        }
      }
    }
  }
  
  depends_on = [
    helm_release.opencost
  ]
}

# DNS record for OpenCost
resource "aws_route53_record" "opencost_record" {
  zone_id = data.aws_route53_zone.default.zone_id
  name    = "opencost.terraform-aws-platform.xyz"
  type    = "CNAME"
  ttl     = "300"
  records = [
    data.kubernetes_service_v1.ingress_service.status.0.load_balancer.0.ingress.0.hostname
  ]
}

# Data sources for DNS (reference from Platform3)
data "aws_route53_zone" "default" {
  name = "terraform-aws-platform.xyz"
}

data "kubernetes_service_v1" "ingress_service" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }
}

# Grafana Dashboard for OpenCost (Custom Resource)
resource "kubernetes_config_map" "opencost_dashboard" {
  metadata {
    name      = "opencost-dashboard"
    namespace = data.kubernetes_namespace_v1.observability.metadata[0].name
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "opencost-dashboard.json" = jsonencode({
      "dashboard" = {
        "id"          = null
        "title"       = "OpenCost - Kubernetes Cost Monitoring"
        "description" = "Cost monitoring and optimization dashboard"
        "tags"        = ["kubernetes", "cost", "finops"]
        "timezone"    = "browser"
        "panels" = [
          {
            "id"    = 1
            "title" = "Total Cluster Cost"
            "type"  = "stat"
            "targets" = [
              {
                "expr"         = "sum(opencost_total_cost)"
                "legendFormat" = "Total Cost"
              }
            ]
            "gridPos" = {
              "h" = 4
              "w" = 6
              "x" = 0
              "y" = 0
            }
          },
          {
            "id"    = 2
            "title" = "Cost by Namespace"
            "type"  = "bargauge"
            "targets" = [
              {
                "expr"         = "sum by (namespace) (opencost_total_cost)"
                "legendFormat" = "{{namespace}}"
              }
            ]
            "gridPos" = {
              "h" = 8
              "w" = 12
              "x" = 0
              "y" = 4
            }
          },
          {
            "id"    = 3
            "title" = "CPU Cost Efficiency"
            "type"  = "timeseries"
            "targets" = [
              {
                "expr"         = "opencost_cpu_cost / opencost_cpu_usage"
                "legendFormat" = "CPU Cost per Unit"
              }
            ]
            "gridPos" = {
              "h" = 8
              "w" = 12
              "x" = 12
              "y" = 4
            }
          }
        ]
        "time" = {
          "from" = "now-24h"
          "to"   = "now"
        }
        "refresh" = "5m"
      }
    })
  }
}

# Output important information
output "opencost_ui_url" {
  description = "OpenCost UI URL"
  value       = "https://opencost.terraform-aws-platform.xyz"
}

output "grafana_url" {
  description = "Grafana URL with OpenCost dashboard"
  value       = "https://grafana.terraform-aws-platform.xyz"
}

output "cost_monitoring_endpoints" {
  description = "Cost monitoring access points"
  value = {
    opencost_ui   = "https://opencost.terraform-aws-platform.xyz"
    grafana       = "https://grafana.terraform-aws-platform.xyz"
    prometheus    = "Available via port-forward to kube-prometheus-stack-prometheus:9090"
  }
}