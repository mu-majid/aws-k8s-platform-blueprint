# Production-Ready Kubernetes Platform on AWS

This repository contains a complete production-ready platform for deploying applications on AWS using Kubernetes, built with Terraform and following GitOps principles.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Architecture](#architecture)
  - [Layer Structure](#layer-structure)
- [Layer 1: Foundation](#layer-1-foundation)
  - [Components](#components)
  - [Deployment](#deployment)
  - [Understanding .terraform.lock.hcl](#understanding-terraformlockhcl)
  - [Post-Deployment](#post-deployment)
- [Layer 2: Platform](#layer-2-platform)
  - [Secret Management Options](#secret-management-options)
  - [Step 02: Software Installation](#step-02-software-installation)
  - [Step 03: Software Configuration](#step-03-software-configuration)
    - [1. DNS Configuration](#1-dns-configuration)
    - [2. Certificate Management](#2-certificate-management)
    - [3. Secret Management Configuration](#3-secret-management-configuration)
  - [Hosted Zones](#hosted-zones)
- [Layer 3: Observability and Monitoring](#layer-3-observability-and-monitoring)
  - [Components](#components-1)
  - [Observability Data Flow](#observability-data-flow)
  - [Overview](#overview-1)
  - [Details](#details)
- [Layer 4: Resilience and Backup](#layer-4-resilience)
  - [Components](#components-2)
  - [Backup Strategy](#backup-strategy)
  - [What Gets Protected](#what-gets-protected)
  - [Details](#details-1)
- [Layer 5: Cost Optimization - FinOps](#layer-5-cost-optimization---finops)
  - [Components](#components-3)
  - [Data Flow](#data-flow)
  - [Overview](#overview-2)
  - [Details](#details-2)
- [Layer 6: Security - Platform Protection](#layer-6-security---platform-protection)
  - [Components](#components-4)
  - [Key Features](#key-features)
  - [What's Included](#whats-included)
  - [Deployment](#deployment-1)
  - [Access Points](#access-points)
  - [Quick Tips](#quick-tips)
  - [Next Steps](#next-steps)
  - [Expected Impact](#expected-impact)
- [Layer 7: Application Deployment](#application-deployment)
  - [Components](#components-5)
    - [1. Creates Namespace](#1-creates-namespace)
    - [2. ArgoCD Application](#2-argocd-application)
    - [3. Ingress with TLS](#3-ingress-with-tls)
    - [4. External Secret](#4-external-secret)
  - [End Result](#end-result)
  - [How It Works](#how-it-works)
  - [Deployment](#deployment-2)
- [Traffic Flow](#traffic-flow)
- [Troubleshooting](#troubleshooting)
  - [Common Issues](#common-issues)
  - [Useful Commands](#useful-commands)
- [Cost Analysis](#platform-cost-analysis)
- [✨ Best Practices Implemented](#best-practices-implemented)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

The platform uses **Terraform** to create and manage infrastructure, making provisioning easier and more reproducible. It's built in layers to address Terraform's dependency management challenges (DAG issues) and follows best practices for state management using external storage like S3.

To Reach full production readiness, these points needs to be addressed in each of the layers below:

Foundations

- Multi-region setup for disaster recovery
- Backup strategy for EKS/RDS
- KMS encryption for EBS/secrets
- VPC Flow Logs and GuardDuty
- Network policies and security groups hardening

Platform2

- Resource quotas and limits
- Pod Security Standards
- RBAC policies (least privilege)
- Image scanning and admission controllers
- HA configurations (multi-replica ArgoCD, etc.)

Platform3

- WAF on load balancer
- Rate limiting on ingress
- Secret rotation automation
- DNS failover setup
- Certificate monitoring

Observability

- External storage (S3 for Loki/Tempo instead of local)
- HA setup (3+ replicas for critical components)
- Alerting rules and runbooks
- SLI/SLO monitoring
- Log retention policies
- Backup for monitoring data

## Prerequisites

Before getting started, ensure you have:

1. **Terraform CLI** - [Installation Guide](https://learn.hashicorp.com/tutorials/terraform/install-cli)
2. **AWS CLI** - Properly configured with credentials
3. Set these env in your .zshrc or.bashrc file:
  ```bash
  export TF_VAR_email="youremail@domain.com"
  export TF_VAR_pixie_deploy_key="PIKIE_DEPLOY_KEY" # you create and get that from the Pixit UI
  ```

## Architecture

The platform is organized into **layers**, each containing:
- `main.tf` - Resource definitions
- `providers.tf` - Provider versions and API configurations

### Layer Structure

```
├── foundation/          # Core infrastructure
├── platform/           # Kubernetes platform components
│   ├── step02/         # Software installation
│   └── step03/         # Software configuration
|   observability       # System Observability and Monitoring Stack
└── app/                # Application deployment
```

## Layer 1: Foundation

Creates the core infrastructure components required for any Kubernetes cluster.

### Components

- **VPC** - Virtual Private Cloud for network isolation
- **Subnets** - Public, private, and intra subnets across availability zones
- **IAM** - Identity and Access Management roles and policies
- **DNS** - Route53 hosted zone configuration
- **Cluster** - A collection of worker nodes and control plane (basically Kubernetes cluster)
- **NAT Gateway** - Outbound internet access for private subnets

### Deployment

```bash
cd foundation/
terraform init
terraform apply
```

### Understanding .terraform.lock.hcl

The `.terraform.lock.hcl` file is Terraform's dependency lock file. It:

- **Locks provider versions** - Records the exact versions of providers that were downloaded
- **Ensures consistency** - Makes sure everyone on your team uses the same provider versions
- **Prevents drift** - Stops providers from auto-updating to newer versions unexpectedly
- **Contains checksums** - Verifies provider authenticity and integrity

**Should you commit it?** Yes, always commit it to version control.

**When is it created?** During `terraform init` when providers are downloaded.

Example content:
```hcl
provider "registry.terraform.io/hashicorp/aws" {
  version = "5.0.0"
  hashes = [
    "h1:xyz123...",
    "zh:abc456...",
  ]
}
```

It's similar to `package-lock.json` in Node.js or `Pipfile.lock` in Python - it locks your dependencies to specific versions for reproducible builds.

### Post-Deployment

After running `terraform apply`, all resources should be created on AWS. Now run:

```bash
aws eks update-kubeconfig --region [YOUR_REGION] --name [CLUSTER_NAME]
```

This downloads the certificate that allows us to communicate with the API via kubectl. Then we can run:

```bash
kubectl get nodes
```

to check the nodes (internal Kubernetes nodes).

## Layer 2: Platform

Split into two steps: **Step02** (installing the software with basic config) and **Step03** (configuring the software).

This layer consists of the components needed for Kubernetes to be ready for production - they are defined as Helm charts:

1. **Gateway/Ingress (Ingress Nginx)** - For routing traffic inside the cluster
2. **Secret Management (External Secret Operator)** - For syncing secrets in a secure way
3. **Certificate Management (Cert Manager)** - For TLS certificate issuance
4. **Continuous Delivery (ArgoCD)** - Deploying the application with the GitOps pattern
5. **Cluster Autoscaling**

### Secret Management Options

We can handle secrets in our cluster in three different ways:

1. **Using secret manager** [Recommended] like Vault, and when the container is spun up, we query vault for the secrets, then inject them in the container.

2. **Sealed secrets**, where we encrypt the secrets and put them in our YAML manifests, and these encrypted values are committed in our git repo. [No secret manager is needed here - secret rotation is handled manually]

3. **External secret operator** [Implemented] is running inside the cluster, it is a resource that we can use to make it point to a store (KeyVault, AWS parameters, ...) - And we commit a reference to this secret in our YAML manifests (in the app)

### Step 02: Software Installation

**Note**: In the ingress resource, we set `enableHttp: true` for the cert-manager to be able to issue certificates.

**Good read on AWS load balancer types**: [Network vs Application LB](https://aws.amazon.com/compare/the-difference-between-the-difference-between-application-network-and-gateway-load-balancing/)

**ArgoCD** is a GitOps tool that monitors git, and once it sees a change (in code or config, depends how it was set up), it will deploy and update the cluster.

```bash
cd platform/step02/
terraform init
terraform apply
```

### Step 03: Software Configuration

In Step03 we will configure:

#### 1. DNS Configuration
Create a DNS record in the hosted zone on AWS Route53, and make it point to our cluster's ingress.
- Creates `app.terraform-aws-platform.xyz` → Points to your application
- Creates `grafana.terraform-aws-platform.xyz` → Points to your monitoring dashboard
- Both records point to the same AWS Load Balancer (ingress controller)

This means we have a domain, and we want to map this domain to our ingress's IP.

```bash
kubectl -n ingress-nginx get svc
```

You can see the ingress IP from this command.

#### 2. Certificate Management
Configure `cert-manager` to create TLS certificates (Let's Encrypt is used for issuing the cert).

**Automatic SSL**: When you create an Ingress with TLS, cert-manager will automatically:
1. Request a certificate from Let's Encrypt
2. Serve the challenge file via nginx
3. Get the certificate and store it in Kubernetes
4. Auto-renew before expiration

#### 3. IAM Roles for ServiceAccounts Configuration:
Service Accounts Created:
| Service Account| Namespace | Purpose | AWS Role |
|----------|----------|----------|----------|
| secret-store    | external-secrets     | Access AWS Parameter Store     | secret-store     |
| cluster-autoscaler    | kube-system     | Scale EC2 Instances     | cluster-autoscaler     |
| ebs-csi-controller-sa    | kubesystem     | Manage EBS volumes     | ebs-csi-controller     |


#### 4. Secret Management Configuration
Configure the secrets manager → external-secrets operator can fetch certificates/secrets from AWS Parameter Store.

A service account named `secret-store` (assuming the role created in foundation) will be created, and a ParameterStore as a secrets store.

**Automatic Secret Sync**: You can now create ExternalSecret resources that:
1. Reference secrets stored in AWS Parameter Store
2. Automatically sync them to Kubernetes secrets
3. Keep them updated when Parameter Store values change

```bash
cd platform/step03/
terraform init
terraform apply
```

### Hosted Zones

Hosted zones are AWS's way of organizing and managing all DNS records for a domain in one place.

```
Hosted Zone: terraform-aws-platform.xyz
├── A Record: terraform-aws-platform.xyz → 192.168.1.100
├── CNAME Record: app.terraform-aws-platform.xyz → load-balancer.aws.com
├── MX Record: mail.terraform-aws-platform.xyz → mail-server.com
├── NS Records: (nameservers that handle this zone)
└── SOA Record: (zone authority information)
```

## Layer 3: Observability and Monitoring

This part installs and configures many tools to help us monitor and check our cluster overall health.

### Components:
1. Visualization (Grafana)
2. Logging (Grafana Loki)
3. Metrics (Prometheus)
4. Auto-instrumented Tracing (Pixie)
5. Tracing (Grafana Tempo & Open Telemetry)

### Observability Data Flow:

```mermaid
graph TD
    %% Metrics Flow
    A[Applications] -->|scrapes| B[Prometheus]
    B -->|stores| B1[(Prometheus Storage)]
    C[Grafana] -->|queries| B1
    C -->|displays| D[Dashboards]
    
    %% Logs Flow
    E[Containers] -->|collects| F[Promtail]
    F -->|pushes| G[(Loki)]
    C -->|queries| G
    
    %% Traces Flow
    H[Applications] -->|sends| I[OpenTelemetry Collector]
    I -->|forwards| J[(Tempo)]
    C -->|queries| J
    
    %% OTel Self-Monitoring
    I -->|exposes /metrics| B
    
    %% Pixie Flow
    K[Cluster] -->|eBPF| L[Pixie]
    L -->|analysis| M[Pixie UI]
    
    %% Additional monitoring targets
    N[Kubernetes API] -->|scrapes| B
    O[Node Exporters] -->|scrapes| B
    P[Other Services] -->|scrapes| B
    
    %% Styling
    classDef storage fill:#e1f5fe
    classDef collector fill:#f3e5f5
    classDef ui fill:#e8f5e8
    classDef selfmon fill:#fff3e0
    
    class B1,G,J storage
    class B,F,I,L collector
    class C,D,M ui
    class I selfmon
```

### Overview
 cluster probably needs the EBS CSI driver for dynamic volume provisioning
 
 ```kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.25"```
 
Automatic Data Collection (No Code Changes):

Prometheus: Infrastructure metrics (CPU, memory, network)
Loki + Promtail: All application logs automatically
Pixie: HTTP traffic, database queries, service maps (eBPF magic!)

Requires Instrumentation:

Tempo + OpenTelemetry: Distributed tracing (needs SDK integration)

### Details:

Please head to the RAEDME file inside the `04_observability` folder for a more in depth insights about the tools and the over all architecture.

## Layer 4: Resilience

Provides automated backup and disaster recovery capabilities for the entire Kubernetes platform using Velero. I will enclose all config and resource creation for this layer here, because backup is a complete product, and in the future we can decide moving to a different technology (Longhorn, Kasten...etc), so we would have the entire solution in one place.

### Components

- **Velero Server** - Orchestrates backup and restore operations
- **S3 Backup Storage** - Encrypted storage with lifecycle policies for cost optimization
- **EBS Snapshots** - Point-in-time copies of persistent volumes
- **Node Agents** - File-level backup capabilities on worker nodes
- **IAM Roles** - Secure access via IRSA for backup operations

### Backup Strategy

| Schedule | Frequency | Retention | Type |
|----------|-----------|-----------|------|
| Daily | 2 AM | 30 days | EBS snapshots + configs |
| Weekly | Sunday 3 AM | 90 days | Full backup with file-level |
| Monthly | 1st at 4 AM | 365 days | Complete disaster recovery |

### What Gets Protected

**Application Data:**
- Database volumes (PostgreSQL, MySQL)
- User uploads and file storage
- Monitoring data (Prometheus, Grafana)

**Cluster Configuration:**
- Deployments, Services, ConfigMaps
- Secrets (encrypted)
- RBAC policies and permissions
- Custom resources (ArgoCD apps, certificates)

### Disaster Recovery Scenarios

- **Volume corruption** → Restore from EBS snapshots (5-10 min)
- **Accidental deletion** → Selective namespace restore (2-5 min)
- **Cluster failure** → Full cluster rebuild and restore (15-30 min)
- **Region outage** → Cross-region recovery (30-60 min)

### Deployment

```bash
cd resilience/
terraform init
terraform apply
```

### Usage Examples

```bash
# Check Velero namespace and pods
kubectl get namespace velero
kubectl get pods -n velero

# List available backups
velero backup get

# Restore specific namespace
velero restore create --from-backup daily-backup-20250110 \
  --include-namespaces ecommerce-app

# Manual backup before major changes
velero backup create pre-deployment-backup \
  --include-namespaces production
```

### Production Readiness

**Current Features:**
- Automated scheduled backups with appropriate retention
- Encrypted storage with lifecycle management
- Cross-service backup coordination
- Monitoring integration ready

**Still Needed for Production:**
- Cross-region backup replication
- Automated backup validation testing
- Comprehensive alerting rules
- Disaster recovery runbooks

For detailed configuration and advanced features, see the [Resilience Layer README](resilience/README.md).

## Layer 6: FinOps - Cost Optimization

### Purpose
Real-time Kubernetes cost monitoring and resource optimization foundation.

### Components

#### Deployed
- **OpenCost** - Real-time cost monitoring and allocation
- **Grafana Integration** - Cost dashboards in existing monitoring stack
- **OpenCost UI** - Standalone web interface for detailed cost analysis

#### Future Enhancements
- **KEDA** - Event-driven autoscaling (SQS, CloudWatch, etc.)
- **Karpenter** - Advanced cluster autoscaling (replace cluster-autoscaler)

### What's Included

```
├── OpenCost Helm Chart
├── Grafana Dashboard ConfigMap
├── Ingress + DNS (opencost.domain.com)
├── Prometheus ServiceMonitor
└── Cost metrics collection
```

### Deployment

```bash
# Navigate to FinOps layer
cd 06_finops

# Deploy cost monitoring
terraform init
terraform plan
terraform apply
```

### Access Points

- **OpenCost UI**: `https://opencost.terraform-aws-platform.xyz`
- **Grafana**: `https://grafana.terraform-aws-platform.xyz` (cost dashboard)
- **Metrics**: Available in Prometheus

### Key Features

- **Cost breakdown** by namespace, deployment, service
- **Resource efficiency** tracking (CPU/memory/storage costs)
- **Historical cost trends** and waste identification
- **Dual interface** - Technical (Grafana) + Business (OpenCost UI)

###  Quick Tips

- **Wait 2-4 weeks** for meaningful cost data before optimization
- **Check Grafana first** for daily cost monitoring
- **Use OpenCost UI** for detailed cost analysis and reports
- **Monitor namespace costs** to identify optimization opportunities

### Next Steps

1. Establish cost baseline over 2-4 weeks
2. Identify high-cost namespaces/workloads
3. Consider KEDA for event-driven workloads
4. Plan Karpenter migration for 20-50% cost reduction

### Expected Impact

- **Immediate**: 100% cost visibility
- **Short-term**: 10-30% waste identification
- **Long-term**: 20-50% cost reduction (with full FinOps stack)

## Layer 7: Security - Platform Protection

### Purpose
Comprehensive security layer providing policy enforcement, vulnerability scanning, cloud security assessment, and runtime threat detection.

### Components

#### Deployed
- **Kyverno** - Configuration security and policy enforcement
- **Trivy Operator** - Image vulnerability scanning and CIS compliance
- **Falco** - Runtime security monitoring and threat detection  
- **Prowler** - AWS security posture assessment (weekly scans)
- **Security Dashboard** - Unified monitoring in Grafana

#### Key Features
- **Policy enforcement** for container security standards
- **Continuous vulnerability scanning** of all images
- **Real-time threat detection** with behavioral monitoring
- **Cloud compliance** checking against CIS benchmarks
- **Integrated alerting** through existing observability stack

### What's Included

```
├── Kyverno Policy Engine (2 replicas)
├── Trivy Operator (image + config scanning)
├── Falco Runtime Security (eBPF-based) - DISABLED FOR NOW
├── Prowler CronJob (weekly AWS assessment)  
├── Security Grafana Dashboard
└── S3 bucket for security reports
```

### Deployment

```bash
# Navigate to security layer
cd layers/07_security/

# Deploy security stack
terraform init
terraform plan
terraform apply
```

### Access Points

- **Security Dashboard**: `https://grafana.terraform-aws-platform.xyz` (Security Overview)
- **Policy Reports**: `kubectl get clusterpolicies`
- **Vulnerability Reports**: `kubectl get vulnerabilityreports -A`
- **Runtime Alerts**: `kubectl logs -n falco-system -l app.kubernetes.io/name=falco`
- **Cloud Reports**: S3 bucket with weekly Prowler assessments

### Key Features

- **Zero-trust policies** - No privileged containers, resource limits enforced
- **Continuous scanning** - All images automatically scanned for vulnerabilities
- **Behavioral monitoring** - Real-time detection of suspicious runtime activity
- **Compliance automation** - Weekly AWS security posture assessment
- **Unified visibility** - All security metrics in existing Grafana dashboards

### Quick Tips

- **Monitor policy violations** in Grafana security dashboard
- **Review vulnerability reports** weekly for critical CVEs
- **Check Falco alerts** for runtime security incidents
- **Access Prowler reports** in S3 for compliance evidence
- **Use Kyverno policies** to prevent misconfigurations before deployment

### Next Steps

1. Monitor security dashboard for baseline establishment
2. Tune Falco rules based on environment-specific patterns
3. Create additional Kyverno policies for organization requirements
4. Set up automated remediation workflows for critical vulnerabilities

### Expected Impact

- **Immediate**: Policy enforcement prevents misconfigurations
- **Short-term**: Vulnerability visibility and runtime threat detection  
- **Long-term**: Compliance-ready platform with defense-in-depth security

## Application Deployment

In the `100_app` directory we have `main.tf` file which is responsible for deploying Google's Microservices Demo App.

### Components

#### 1. Creates Namespace
```hcl
resource "kubernetes_namespace_v1" "onlineboutique"
```

Creates `onlineboutique` namespace for the application.

#### 2. ArgoCD Application
```hcl
resource "kubernetes_manifest" "app_chart"
```

- Deploys Google's Online Boutique microservices demo via ArgoCD
- Uses Helm chart from Google's container registry
- Auto-sync enabled: ArgoCD automatically applies changes and heals drift
- Frontend config: Sets `externalService: false` (uses ingress instead of LoadBalancer)

#### 3. Ingress with TLS
```hcl
resource "kubernetes_ingress_v1" "frontend"
```

- Exposes the frontend service at `app.terraform-aws-platform.xyz`
- Auto SSL: cert-manager automatically gets Let's Encrypt certificate
- Routes: All traffic to the frontend service on port 80

#### 4. External Secret
```hcl
resource "kubernetes_manifest" "cluster_secret_store"
```

- Syncs secret from AWS Parameter Store (`cluster-prod-k8s-platform-tutorial-secret`)
- Creates Kubernetes secret named `onlineboutique-custom-secret`
- Auto-refresh: Updates every hour

### End Result

**Complete e-commerce demo**: A fully functional microservices application with:

- **Public access**: `https://app.terraform-aws-platform.xyz` (SSL-enabled)
- **GitOps**: Managed by ArgoCD
- **Secret management**: AWS Parameter Store integration
- **Production-ready**: Ingress, TLS, namespace isolation

### How It Works

#### 1. ArgoCD Deploys the App
```yaml
source:
  repoURL: us-docker.pkg.dev/online-boutique-ci/charts
  chart: onlineboutique
```

This Helm chart creates multiple services: `frontend`, `cartservice`, `paymentservice`, `productcatalogservice`, etc.

#### 2. The "frontend" Service Gets Created
When the Online Boutique chart deploys, it creates a service named `frontend` that looks like:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend        # <-- This is the actual service name
  namespace: onlineboutique
spec:
  ports:
  - port: 80
  selector:
    app: frontend
```

#### 3. Ingress References the Real Service
```yaml
backend {
  service {
    name = "frontend"    # <-- Must match the actual service name
    port {
      number = 80
    }
  }
}
```

#### 4. You Can Verify This
After deployment, run:

```bash
kubectl get services -n onlineboutique
```

You'll see services like:
- `frontend`
- `cartservice`
- `paymentservice`
- etc.

### Key Point

**The ingress backend service name must match an existing Kubernetes service.** Since Google's Online Boutique creates a service called `frontend`, that's what you reference in the ingress.

If you tried to use `name = "my-random-name"`, the ingress would fail because that service doesn't exist.

### Deployment

```bash
cd app/
terraform init
terraform apply
```

## Traffic Flow

```
User (https://app.terraform-aws-platform.xyz)
    ↓
DNS Resolution (Route53)
    ↓
AWS Load Balancer
    ↓
Ingress Controller (nginx)
    ↓
Frontend Service
    ↓
OnlineBoutique Pods
```

## Troubleshooting

### Common Issues

1. **DNS Resolution Problems**
   - Verify nameserver configuration at domain registrar
   - Check Route53 hosted zone records

2. **Certificate Issues**
   - Ensure HTTP traffic is enabled for cert-manager validation
   - Verify domain ownership and DNS propagation

3. **Ingress Controller Issues**
   - Check load balancer provisioning
   - Verify security group configurations

### Useful Commands

```bash
# Check cluster status
kubectl get nodes

# Check ingress controller
kubectl -n ingress-nginx get svc

# Check certificates
kubectl get certificates -A

# Check ArgoCD applications
kubectl -n argocd get applications
```

## Platform Cost Analysis

### Monthly Cost Breakdown by Layer

| Layer | Primary Cost Drivers | Estimated Monthly Cost |
|-------|---------------------|----------------------|
| **Foundation** | EKS control plane ($72), Worker nodes (~$400), NAT Gateways ($135) | **~$650** |
| **Core Platform** | Network Load Balancer ($16), EBS storage ($50) | **~$80** |
| **Configuration** | DNS queries, certificates (minimal) | **~$5** |
| **Observability** | EBS storage for Prometheus/Loki ($100), compute overhead ($100) | **~$200** |
| **Resilience** | S3 backup storage ($15), EBS snapshots ($20) | **~$35** |
| **FinOps** | OpenCost compute overhead (minimal) | **~$10** |
| **Security** | Trivy/Kyverno overhead ($25), Prowler S3 ($5) | **~$30** |
| **Total Platform Cost** | | **~$1,010/month** |

*Note: Costs based on us-east-1 pricing with 3-4 t3.xlarge worker nodes and moderate storage usage*

### Cost Optimization Strategies

#### Immediate Savings (20-40% reduction)
- **Use Spot Instances**: Replace on-demand worker nodes with spot instances for 60-90% compute savings
- **Right-size Worker Nodes**: Start with t3.large instead of t3.xlarge, scale up as needed
- **Single AZ for Development**: Use one NAT Gateway for dev environments (-$90/month)
- **Reduce EBS Storage**: Use gp3 instead of gp2, implement storage lifecycle policies

#### Medium-term Optimizations (Additional 10-20%)
- **Implement Karpenter**: Replace cluster-autoscaler for better instance selection and spot integration
- **Storage Optimization**: Compress Loki logs, reduce Prometheus retention period
- **Resource Requests/Limits**: Properly size all workloads to improve node utilization
- **Reserved Instances**: Commit to 1-year terms for predictable workloads

#### Advanced Cost Controls
- **Cluster Consolidation**: Run multiple environments on same cluster with namespace separation
- **Managed Services**: Consider EKS Fargate for specific workloads to eliminate node management
- **Backup Optimization**: Implement intelligent backup scheduling and retention policies
- **Development Environment**: Use smaller instance types and reduced replica counts for non-prod

#### Monitoring & Governance
- **Set up Cost Alerts**: Configure AWS Budgets for proactive cost monitoring
- **Regular Cost Reviews**: Weekly cost analysis using OpenCost dashboards
- **Resource Tagging**: Implement comprehensive tagging for accurate cost allocation
- **Automated Cleanup**: Schedule removal of unused resources and old backups

**Potential Total Savings**: 30-60% reduction possible with aggressive optimization, bringing monthly costs down to **$400-700/month** while maintaining production capabilities.

## Best Practices Implemented

- **Infrastructure as Code**: Everything defined in Terraform
- **Layered Architecture**: Clear separation of concerns
- **Secret Management**: External secret synchronization
- **Certificate Management**: Automatic SSL/TLS provisioning
- **State Management**: Remote state storage in S3
- **GitOps**: Automated deployments via ArgoCD

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes following the established patterns
4. Test thoroughly in a development environment
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.