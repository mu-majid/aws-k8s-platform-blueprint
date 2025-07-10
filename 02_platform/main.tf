resource "helm_release" "eso" {
  name             = "external-secrets"
  namespace        = "external-secrets"
  repository       = "https://external-secrets.io" # this is the operator that allows us to sync the secrets from AWS toinside of k8s
  chart            = "external-secrets"
  version          = "0.6.1"
  timeout          = 300
  atomic           = true # remove everything if failed - like an atomic transaction
  create_namespace = true
}

resource "helm_release" "certm" {
  name             = "cert-manager"
  namespace        = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "1.12.0"
  timeout          = 300
  atomic           = true
  create_namespace = true

  values = [
    <<YAML
installCRDs: true
    YAML
  ]
}


resource "helm_release" "ingress" {
  name             = "ingress-nginx"
  namespace        = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.0.5"
  timeout          = 300
  atomic           = true
  create_namespace = true

  values = [
    <<YAML
controller:
  podSecurityContext:
    runAsNonRoot: true
  service:
    enableHttp: true 
    enableHttps: true
    annotations:
      service.beta.kubernetes.io/aws-load-balancer-type: nlb
    YAML
  ]
}

resource "helm_release" "argocd" {
  name             = "argo-cd"
  namespace        = "argo-cd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "4.5.11"
  timeout          = 300
  atomic           = true
  create_namespace = true

  values = [
    <<YAML
nameOverride: argo-cd
redis-ha:
  enabled: false
controller:
  replicas: 1
server:
  replicas: 1
repoServer:
  replicas: 1
applicationSet:
  replicaCount: 1
    YAML
  ]
}
resource "helm_release" "cluster_autoscaler" {
  name             = "cluster-autoscaler"
  namespace        = "kube-system"
  repository       = "https://kubernetes.github.io/autoscaler"
  chart            = "cluster-autoscaler"
  version          = "9.29.0"
  timeout          = 300
  atomic           = true
  create_namespace = false

  values = [
    <<YAML
autoDiscovery:
  clusterName: cluster-prod
awsRegion: eu-central-1
rbac:
  create: true
  serviceAccount:
    name: cluster-autoscaler
serviceAccount:
  create: false  # Don't create, we'll manage it in step 3
  name: cluster-autoscaler
resources:
  requests:
    cpu: 100m
    memory: 300Mi
  limits:
    cpu: 100m
    memory: 300Mi
    YAML
  ]
}

resource "helm_release" "ebs_csi_driver" {
  name             = "aws-ebs-csi-driver"
  namespace        = "kube-system"
  repository       = "https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
  chart            = "aws-ebs-csi-driver"
  version          = "2.24.0"
  timeout          = 300
  atomic           = true
  create_namespace = false
}