# Security Layer - Comprehensive Platform Security
# This layer provides:
# 1. Configuration Security with Kyverno policy engine
# 2. Image Security with Trivy vulnerability scanning
# 3. Cloud Security Posture with Prowler assessment
# 4. CIS Benchmarks compliance checking
# 5. Runtime Monitoring with Falco threat detection

locals {
  cluster_name = "cluster-prod"
  tags = {
    "karpenter.sh/discovery" = local.cluster_name
    "author"                 = "majid"
    "layer"                  = "security"
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "kubernetes_namespace_v1" "observability" {
  metadata {
    name = "observability"
  }
}
data "aws_route53_zone" "default" {
  name = "terraform-aws-platform.xyz"
}
data "kubernetes_service_v1" "ingress_service" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }
}

# ================================
# 1. CONFIGURATION SECURITY (KYVERNO)
# ================================

# Kyverno Policy Engine
resource "helm_release" "kyverno" {
  name             = "kyverno"
  namespace        = "kyverno"
  repository       = "https://kyverno.github.io/kyverno"
  chart            = "kyverno"
  version          = "3.1.4"
  timeout          = 600
  atomic           = true
  create_namespace = true

  values = [
    <<YAML
# Kyverno configuration
replicaCount: 2

admissionController:
  replicas: 2
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

backgroundController:
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

cleanupController:
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi

reportsController:
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi

# Enable metrics for Prometheus integration
metricsService:
  create: true
  type: ClusterIP
  port: 8000

# Service monitor for Prometheus
serviceMonitor:
  enabled: true
  additionalLabels:
    release: kube-prometheus-stack
    YAML
  ]
}

# Basic Security Policies
resource "kubernetes_manifest" "disallow_privileged_containers" {
  manifest = yamldecode(<<YAML
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-privileged-containers
  annotations:
    policies.kyverno.io/title: Disallow Privileged Containers
    policies.kyverno.io/category: Pod Security Standards (Baseline)
    policies.kyverno.io/severity: medium
    policies.kyverno.io/description: >-
      Privileged containers share namespaces with the host system and do not offer any security isolation.
spec:
  validationFailureAction: enforce
  background: true
  rules:
    - name: check-privileged
      match:
        any:
        - resources:
            kinds:
            - Pod
      validate:
        message: "Privileged containers are not allowed"
        pattern:
          spec:
            =(securityContext):
              =(privileged): "false"
            containers:
            - name: "*"
              =(securityContext):
                =(privileged): "false"
  YAML
  )

  depends_on = [helm_release.kyverno]
}

resource "kubernetes_manifest" "require_resource_limits" {
  manifest = yamldecode(<<YAML
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-pod-resources
  annotations:
    policies.kyverno.io/title: Require Pod Resources
    policies.kyverno.io/category: Best Practices
    policies.kyverno.io/severity: medium
    policies.kyverno.io/description: >-
      Resource limits and requests should be set for every container to ensure efficient resource usage.
spec:
  validationFailureAction: enforce
  background: true
  rules:
    - name: validate-resources
      match:
        any:
        - resources:
            kinds:
            - Pod
      exclude:
        any:
        - resources:
            namespaces:
            - kube-system
            - kube-public
            - kyverno
      validate:
        message: "Resource requests and limits are required"
        pattern:
          spec:
            containers:
            - name: "*"
              resources:
                requests:
                  memory: "?*"
                  cpu: "?*"
                limits:
                  memory: "?*"
                  cpu: "?*"
  YAML
  )

  depends_on = [helm_release.kyverno]
}

# ================================
# 2. IMAGE SECURITY (TRIVY)
# ================================

# Trivy Operator for vulnerability scanning
resource "helm_release" "trivy_operator" {
  name             = "trivy-operator"
  namespace        = "trivy-system"
  repository       = "https://aquasecurity.github.io/helm-charts"
  chart            = "trivy-operator"
  version          = "0.20.2"
  timeout          = 600
  atomic           = true
  create_namespace = true

  values = [
    <<YAML
# Trivy Operator configuration
operator:
  replicas: 1
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

# Enable metrics for Prometheus
serviceMonitor:
  enabled: true
  labels:
    release: kube-prometheus-stack

trivy:
  # Image scanning configuration
  resources:
    requests:
      cpu: 100m
      memory: 512Mi
    limits:
      cpu: 500m
      memory: 1Gi
  
  # Scan configuration
  severity: UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL
  slow: true
  
  # Cache configuration
  storageClassName: "gp2-csi"
  storageSize: "5Gi"

# Node agent for runtime scanning
nodeAgent:
  enabled: true
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi

# Compliance scanning
compliance:
  enabled: true
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi
    YAML
  ]
}

# ================================
# 3. RUNTIME MONITORING (FALCO)
# ================================

# Falco for runtime security monitoring
resource "helm_release" "falco" {
  name             = "falco"
  namespace        = "falco-system"
  repository       = "https://falcosecurity.github.io/charts"
  chart            = "falco"
  version          = "4.2.4"
  timeout          = 600
  atomic           = true
  create_namespace = true

  values = [
    <<YAML
# Falco configuration
falco:
  # Load kernel module or eBPF probe
  driver:
    kind: ebpf
  
  # Resource configuration
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

  # Rules configuration
  rules_file:
    - /etc/falco/falco_rules.yaml
    - /etc/falco/k8s_audit_rules.yaml
    - /etc/falco/rules.d

  # Output configuration
  json_output: true
  json_include_output_property: true
  json_include_tags_property: true

  # Syscall event drop handling
  syscall_event_drops:
    actions:
      - log
      - alert
    rate: 0.03333
    max_burst: 1000

# Service Monitor for Prometheus integration
serviceMonitor:
  enabled: true
  additionalLabels:
    release: kube-prometheus-stack

# HTTP output for webhook integration
falcosidekick:
  enabled: true
  replicaCount: 1
  
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi
  
  # Integration with Grafana/Prometheus
  config:
    prometheus:
      extralabels: "rule"
    grafana:
      hostport: "http://kube-prometheus-stack-grafana.observability:80"
      dashboardid: "11914"
    YAML
  ]
}

# ================================
# 4. CLOUD SECURITY POSTURE (PROWLER)
# ================================

# S3 bucket for Prowler reports
resource "random_string" "prowler_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket" "prowler_reports" {
  bucket = "${local.cluster_name}-prowler-reports-${random_string.prowler_suffix.result}"
  tags   = local.tags
}

resource "aws_s3_bucket_versioning" "prowler_reports" {
  bucket = aws_s3_bucket.prowler_reports.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "prowler_reports" {
  bucket = aws_s3_bucket.prowler_reports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# IAM role for Prowler
resource "aws_iam_role" "prowler_role" {
  name = "prowler-security-assessment"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "prowler_security_audit" {
  policy_arn = "arn:aws:iam::aws:policy/SecurityAudit"
  role       = aws_iam_role.prowler_role.name
}

resource "aws_iam_role_policy_attachment" "prowler_view_only" {
  policy_arn = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"
  role       = aws_iam_role.prowler_role.name
}

# Prowler CronJob for periodic security assessment
resource "kubernetes_cron_job_v1" "prowler_scan" {
  metadata {
    name      = "prowler-security-scan"
    namespace = "kube-system"
  }

  spec {
    schedule          = "0 2 * * 0"  # Weekly on Sunday at 2 AM
    concurrency_policy = "Forbid"

    job_template {
      metadata {}
      spec {
        template {
          metadata {}
          spec {
            restart_policy = "OnFailure"
            
            container {
              name  = "prowler"
              image = "toniblyx/prowler:latest"
              
              command = ["/bin/bash"]
              args = [
                "-c",
                <<-EOT
                prowler aws -f json -o /tmp/reports/ -M json,html && 
                aws s3 cp /tmp/reports/ s3://${aws_s3_bucket.prowler_reports.bucket}/$(date +%Y-%m-%d)/ --recursive
                EOT
              ]

              env {
                name  = "AWS_REGION"
                value = data.aws_region.current.name
              }

              env {
                name  = "AWS_DEFAULT_REGION"
                value = data.aws_region.current.name
              }

              resources {
                requests = {
                  cpu    = "100m"
                  memory = "256Mi"
                }
                limits = {
                  cpu    = "500m"
                  memory = "512Mi"
                }
              }
            }
          }
        }
      }
    }
  }
}

# ================================
# 5. SECURITY DASHBOARDS
# ================================

# Security Overview Dashboard for Grafana
resource "kubernetes_config_map" "security_dashboard" {
  metadata {
    name      = "security-overview-dashboard"
    namespace = data.kubernetes_namespace_v1.observability.metadata[0].name
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "security-overview.json" = jsonencode({
      "dashboard" = {
        "id"          = null
        "title"       = "Security Overview - Platform Security Monitoring"
        "description" = "Comprehensive security monitoring dashboard"
        "tags"        = ["security", "kyverno", "trivy", "falco"]
        "timezone"    = "browser"
        "panels" = [
          {
            "id"    = 1
            "title" = "Policy Violations (Kyverno)"
            "type"  = "stat"
            "targets" = [
              {
                "expr"         = "sum(kyverno_policy_results_total{policy_validation_mode=\"enforce\",policy_result=\"fail\"})"
                "legendFormat" = "Violations"
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
            "title" = "Vulnerability Summary (Trivy)"
            "type"  = "piechart"
            "targets" = [
              {
                "expr"         = "sum by (severity) (trivy_image_vulnerabilities)"
                "legendFormat" = "{{severity}}"
              }
            ]
            "gridPos" = {
              "h" = 8
              "w" = 6
              "x" = 6
              "y" = 0
            }
          },
          {
            "id"    = 3
            "title" = "Runtime Alerts (Falco)"
            "type"  = "timeseries"
            "targets" = [
              {
                "expr"         = "rate(falco_events_total[5m])"
                "legendFormat" = "{{rule}}"
              }
            ]
            "gridPos" = {
              "h" = 8
              "w" = 12
              "x" = 12
              "y" = 0
            }
          },
          {
            "id"    = 4
            "title" = "Security Events Timeline"
            "type"  = "logs"
            "targets" = [
              {
                "expr" = "{namespace=~\"kyverno|trivy-system|falco-system\"}"
              }
            ]
            "gridPos" = {
              "h" = 8
              "w" = 24
              "x" = 0
              "y" = 8
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

# ================================
# OUTPUTS
# ================================

output "security_endpoints" {
  description = "Security monitoring and management endpoints"
  value = {
    kyverno_policies     = "kubectl get clusterpolicies"
    trivy_reports       = "kubectl get vulnerabilityreports -A"
    falco_alerts        = "kubectl logs -n falco-system -l app.kubernetes.io/name=falco"
    prowler_reports     = "s3://${aws_s3_bucket.prowler_reports.bucket}"
    grafana_dashboard   = "https://grafana.terraform-aws-platform.xyz"
  }
}

output "security_tools_status" {
  description = "Commands to check security tools status"
  value = {
    kyverno = "kubectl get pods -n kyverno"
    trivy   = "kubectl get pods -n trivy-system" 
    falco   = "kubectl get pods -n falco-system"
    prowler = "kubectl get cronjob prowler-security-scan -n kube-system"
  }
}

output "prowler_s3_bucket" {
  description = "S3 bucket for Prowler security reports"
  value       = aws_s3_bucket.prowler_reports.bucket
}