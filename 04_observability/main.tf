# Variables for observability configuration
variable "domain" {
  description = "Domain name for Grafana ingress"
  type        = string
  default     = "terraform-aws-platform.xyz"
}

variable "pixie_deploy_key" {
  description = "Pixie deploy key for cluster registration"
  type        = string
  sensitive   = true
}

# Creates observability namespace for all monitoring components
resource "kubernetes_namespace_v1" "observability" {
  metadata {
    name = "observability"
  }
}

# SECTION 1: METRICS & VISUALIZATION - FIXED VERSION
resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  namespace        = kubernetes_namespace_v1.observability.metadata[0].name
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "55.0.0"
  timeout          = 1500  # 25 minutes - increased timeout
  atomic           = true
  create_namespace = false

  values = [
    <<YAML
grafana:
  adminPassword: admin
  service:
    type: ClusterIP
  persistence:
    enabled: true
    size: 2Gi
  resources:
    requests:
      memory: "200Mi"
      cpu: "100m"
    limits:
      memory: "500Mi"
      cpu: "300m"
  additionalDataSources:
    - name: Loki
      type: loki
      url: http://loki:3100
      access: proxy
    - name: Tempo
      type: tempo
      url: http://tempo:3100
      access: proxy
prometheus:
  prometheusSpec:
    retention: 7d
    resources:
      requests:
        memory: "1Gi"
        cpu: "500m"
      limits:
        memory: "2Gi"
        cpu: "1000m"
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi

alertmanager:
  alertmanagerSpec:
    resources:
      requests:
        memory: "100Mi"
        cpu: "50m"
      limits:
        memory: "200Mi"
        cpu: "100m"
    storage:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 1Gi

# Disable some heavy components initially
kubeControllerManager:
  enabled: false
kubeScheduler:
  enabled: false
kubeEtcd:
  enabled: false
kubeProxy:
  enabled: false
    YAML
  ]

  depends_on = [
    kubernetes_namespace_v1.observability
  ]
}

# SECTION 2: LOGGING - FIXED LOKI CONFIGURATION
resource "helm_release" "loki" {
  name             = "loki"
  namespace        = kubernetes_namespace_v1.observability.metadata[0].name
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki"
  version          = "5.38.0"
  timeout          = 900  # 15 minutes
  atomic           = true
  create_namespace = false

  values = [
    <<YAML
deploymentMode: SingleBinary # in PROD use a proper storage like S3
singleBinary:
  replicas: 1
  persistence:
    enabled: true
    size: 10Gi
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 1Gi

loki:
  auth_enabled: false
  commonConfig:
    replication_factor: 1
  storage:
    type: filesystem
  schemaConfig:
    configs:
    - from: 2020-05-15
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h
  limits_config:
    retention_period: 168h
    ingestion_rate_mb: 8
    ingestion_burst_size_mb: 16

# Disable components not needed for single-binary
read:
  replicas: 0
write:
  replicas: 0
backend:
  replicas: 0
gateway:
  enabled: false

# Disable ServiceMonitor initially
monitoring:
  serviceMonitor:
    enabled: false

test:
  enabled: false
    YAML
  ]

  depends_on = [
    kubernetes_namespace_v1.observability
  ]
}

# SECTION 3: PROMTAIL - SIMPLIFIED
resource "helm_release" "promtail" {
  name             = "promtail"
  namespace        = kubernetes_namespace_v1.observability.metadata[0].name
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "promtail"
  version          = "6.15.0"
  timeout          = 600
  atomic           = true
  create_namespace = false

  values = [
    <<YAML
config:
  clients:
    - url: http://loki:3100/loki/api/v1/push
  snippets:
    pipelineStages:
      - docker: {}
# Disable ServiceMonitor initially
serviceMonitor:
  enabled: false

# Resource limits
resources:
  requests:
    cpu: 50m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi
    YAML
  ]

  depends_on = [
    helm_release.loki
  ]
}

# SECTION 4: TEMPO - SIMPLIFIED
resource "helm_release" "tempo" {
  name             = "tempo"
  namespace        = kubernetes_namespace_v1.observability.metadata[0].name
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "tempo"
  version          = "1.7.0"
  timeout          = 900  # 15 minutes
  atomic           = true
  create_namespace = false

  values = [
    <<YAML
tempo:
  storage:
    trace:
      backend: local
      local:
        path: /tmp/tempo/traces
  retention: 168h

# Single replica with resource limits
replicas: 1
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 1Gi

persistence:
  enabled: true
  size: 10Gi

# Disable ServiceMonitor initially
serviceMonitor:
  enabled: false
    YAML
  ]

  depends_on = [
    kubernetes_namespace_v1.observability
  ]
}

# SECTION 5: OPENTELEMETRY - SIMPLIFIED
resource "helm_release" "opentelemetry_collector" {
  name             = "opentelemetry-collector"
  namespace        = kubernetes_namespace_v1.observability.metadata[0].name
  repository       = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart            = "opentelemetry-collector"
  version          = "0.82.0"
  timeout          = 600
  atomic           = true
  create_namespace = false

  values = [
    <<YAML
config:
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: 0.0.0.0:4317
        http:
          endpoint: 0.0.0.0:4318
  processors:
    batch:
      timeout: 1s
      send_batch_size: 1024
    memory_limiter:
      limit_mib: 256
  exporters:
    otlp/tempo:
      endpoint: "http://tempo:4317"
      tls:
        insecure: true
  service:
    extensions: [health_check]
    pipelines:
      traces:
        receivers: [otlp]
        processors: [memory_limiter, batch]
        exporters: [otlp/tempo]

# Resource limits
resources:
  requests:
    cpu: 50m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi

ports:
  otlp:
    enabled: true
    containerPort: 4317
    servicePort: 4317
    protocol: TCP
  otlp-http:
    enabled: true
    containerPort: 4318
    servicePort: 4318
    protocol: TCP
    YAML
  ]

  depends_on = [
    helm_release.tempo
  ]
}

# SECTION 6: PIXIE - SIMPLIFIED
resource "helm_release" "pixie" {
  name             = "pixie"
  namespace        = "pl"
  repository       = "https://pixie-operator-charts.storage.googleapis.com"
  chart            = "pixie-operator-chart"
  version          = "0.1.4"
  timeout          = 900  # 15 minutes
  atomic           = true
  create_namespace = true

  values = [
    <<YAML
deployKey: "${var.pixie_deploy_key}"
clusterName: "cluster-prod"
cloudAddr: "withpixie.ai:443"
pemMemoryLimit: "1Gi"
disableAutoUpdate: false
dataAccess: "Full"
    YAML
  ]

  depends_on = [
    kubernetes_namespace_v1.observability
  ]
}

# SECTION 7: GRAFANA INGRESS - SIMPLIFIED
resource "kubernetes_ingress_v1" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
      "nginx.ingress.kubernetes.io/rewrite-target" = "/"
    }
  }
  spec {
    ingress_class_name = "nginx"
    tls {
      hosts = [
        "grafana.${var.domain}",
      ]
      secret_name = "grafana-tls"
    }
    rule {
      host = "grafana.${var.domain}"
      http {
        path {
          path = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "kube-prometheus-stack-grafana"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
  depends_on = [
    helm_release.kube_prometheus_stack
  ]
}

# COMMENT OUT ServiceMonitor for initial deployment
# Uncomment after everything is running
# resource "kubernetes_manifest" "otel_collector_service_monitor" {
#   manifest = yamldecode(<<YAML
# apiVersion: monitoring.coreos.com/v1
# kind: ServiceMonitor
# metadata:
#   name: opentelemetry-collector
#   namespace: observability
#   labels:
#     release: kube-prometheus-stack
# spec:
#   selector:
#     matchLabels:
#       app.kubernetes.io/name: opentelemetry-collector
#   endpoints:
#   - port: prometheus
#     interval: 30s
#     path: /metrics
#   YAML
#   )
# 
#   depends_on = [
#     helm_release.opentelemetry_collector,
#     helm_release.kube_prometheus_stack
#   ]
# }