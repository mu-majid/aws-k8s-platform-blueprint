resource "kubernetes_namespace_v1" "onlineboutique" {
  metadata {
    name = "onlineboutique"
  }
}

# https://github.com/GoogleCloudPlatform/microservices-demo/tree/main
resource "kubernetes_manifest" "app_chart" {
  manifest = yamldecode(<<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: onlineboutique
  namespace: argo-cd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  source:
    repoURL: us-docker.pkg.dev/online-boutique-ci/charts
    chart: onlineboutique
    targetRevision: 0.8.1
    helm:
      releaseName: onlineboutique
      values: |
        frontend:
            externalService: false
  destination:
    namespace: onlineboutique
    server: https://kubernetes.default.svc
  project: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - PruneLast=true
    retry:
      limit: 5
  YAML
  )

  depends_on = [
    kubernetes_namespace_v1.onlineboutique,
  ]
}


resource "kubernetes_ingress_v1" "frontend" {
  metadata {
    name      = "frontend"
    namespace = "onlineboutique"
    annotations = {
      "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
    }
  }
  spec {
    ingress_class_name = "nginx"
    tls {
      hosts = [
        "app.terraform-aws-platform.xyz",
      ]
      secret_name = "app-terraform-aws-platform-tls"
    }
    rule {
      host = "app.terraform-aws-platform.xyz"
      http {
        path {
          backend {
            service {
              name = "frontend"
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
    kubernetes_manifest.app_chart,
    kubernetes_namespace_v1.onlineboutique,
  ]
}

resource "kubernetes_manifest" "cluster_secret_store" {
  manifest = yamldecode(<<YAML
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: onlineboutique-custom-secret
  namespace: onlineboutique
spec:
  refreshInterval: 1h          
  secretStoreRef:
    kind: ClusterSecretStore
    name: aws-store              
  target:
    name: onlineboutique-custom-secret
  data:
    - secretKey: THE_ANSWER
      remoteRef:
        key: cluster-prod-k8s-platform-example-secret
  YAML
  )

  depends_on = [
    kubernetes_namespace_v1.onlineboutique,
  ]
}