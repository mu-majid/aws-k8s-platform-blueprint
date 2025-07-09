# Variables for observability configuration
variable "domain" {
  description = "Domain name for Grafana ingress"
  type        = string
  default     = "terraform-aws-platform.xyz"
}

# Assumption: Pixie deploy key should be obtained from https://withpixie.ai/
# Create account, create project, and get deploy key from the admin panel
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

# SECTION 1: METRICS & VISUALIZATION
# Deploys Prometheus + Grafana stack for metrics collection and visualization
# Uses kube-prometheus-stack which includes Prometheus, Grafana, and Alertmanager
resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  namespace        = kubernetes_namespace_v1.observability.metadata[0].name
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "55.0.0"
  timeout          = 600
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
    size: 10Gi
  # Pre-configure data sources for Loki and Tempo
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
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 20Gi
    retention: 7d
alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 5Gi
    YAML
  ]

  depends_on = [
    kubernetes_namespace_v1.observability
  ]
}

# SECTION 2: LOGGING
# Deploys Loki for log aggregation and storage
resource "helm_release" "loki" {
  name             = "loki"
  namespace        = kubernetes_namespace_v1.observability.metadata[0].name
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki"
  version          = "5.38.0"
  timeout          = 600
  atomic           = true
  create_namespace = false

  values = [
    <<YAML
loki:
  auth_enabled: false
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
    retention_period: 168h  # 7 days
persistence:
  enabled: true
  size: 20Gi
serviceMonitor:
  enabled: true
  labels:
    release: kube-prometheus-stack
    YAML
  ]

  depends_on = [
    kubernetes_namespace_v1.observability
  ]
}

# Deploys Promtail for log collection from Kubernetes pods
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
serviceMonitor:
  enabled: true
  labels:
    release: kube-prometheus-stack
    YAML
  ]

  depends_on = [
    helm_release.loki
  ]
}

# SECTION 3: TRACING
# Deploys Tempo for distributed tracing storage
resource "helm_release" "tempo" {
  name             = "tempo"
  namespace        = kubernetes_namespace_v1.observability.metadata[0].name
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "tempo"
  version          = "1.7.0"
  timeout          = 600
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
  retention: 168h  # 7 days
persistence:
  enabled: true
  size: 20Gi
serviceMonitor:
  enabled: true
  labels:
    release: kube-prometheus-stack
    YAML
  ]

  depends_on = [
    kubernetes_namespace_v1.observability
  ]
}

# SECTION 4: OPENTELEMETRY
# Deploys OpenTelemetry Collector for trace and metrics collection
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
    jaeger:
      protocols:
        grpc:
          endpoint: 0.0.0.0:14250
        thrift_http:
          endpoint: 0.0.0.0:14268
  processors:
    batch:
      timeout: 1s
      send_batch_size: 1024
    memory_limiter:
      limit_mib: 512
  exporters:
    loki:
      endpoint: "http://loki:3100/loki/api/v1/push"
    otlp/tempo:
      endpoint: "http://tempo:4317"
      tls:
        insecure: true
    prometheus:
      endpoint: "0.0.0.0:8889"
  service:
    extensions: [health_check, pprof, zpages]
    pipelines:
      traces:
        receivers: [otlp, jaeger]
        processors: [memory_limiter, batch]
        exporters: [otlp/tempo]
      metrics:
        receivers: [otlp]
        processors: [memory_limiter, batch]
        exporters: [prometheus]
      logs:
        receivers: [otlp]
        processors: [memory_limiter, batch]
        exporters: [loki]
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
  jaeger-grpc:
    enabled: true
    containerPort: 14250
    servicePort: 14250
    protocol: TCP
  jaeger-thrift:
    enabled: true
    containerPort: 14268
    servicePort: 14268
    protocol: TCP
  prometheus:
    enabled: true
    containerPort: 8889
    servicePort: 8889
    protocol: TCP
    YAML
  ]

  depends_on = [
    helm_release.loki,
    helm_release.tempo
  ]
}

# SECTION 5: AUTO-INSTRUMENTED TRACING
# Deploys Pixie for automatic application observability using eBPF
# Assumption: Pixie requires a deploy key from https://withpixie.ai/
resource "helm_release" "pixie" {
  name             = "pixie"
  namespace        = "pl"
  repository       = "https://pixie-operator-charts.storage.googleapis.com"
  chart            = "pixie-operator-chart"
  version          = "0.1.4"
  timeout          = 600
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

# SECTION 6: GRAFANA INGRESS
# Assumption: cert-manager and nginx-ingress are already deployed from platform layer
# Creates ingress for Grafana with TLS termination
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

# SECTION 7: MONITORING CONFIGURATION
# Creates ServiceMonitor for OpenTelemetry Collector metrics
resource "kubernetes_manifest" "otel_collector_service_monitor" {
  manifest = yamldecode(<<YAML
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: opentelemetry-collector
  namespace: observability
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: opentelemetry-collector
  endpoints:
  - port: prometheus
    interval: 30s
    path: /metrics
  YAML
  )

  depends_on = [
    helm_release.opentelemetry_collector,
    helm_release.kube_prometheus_stack
  ]
}