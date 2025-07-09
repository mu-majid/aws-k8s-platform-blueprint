# Observability Layer - Production-Ready Kubernetes Monitoring Stack

This layer deploys a comprehensive observability stack on your EKS cluster, providing metrics, logs, traces, and automatic application monitoring. The stack follows the **LGTM** (Loki, Grafana, Tempo, Mimir) + **Pixie** approach for complete observability coverage.

## 🛠️ Tools Overview & Benefits

### **1. Prometheus** 📊
**What it does:** Metrics collection and storage system with powerful querying language (PromQL)

**Benefits:**
- **Automatic Discovery**: Finds and scrapes metrics from Kubernetes services automatically
- **Powerful Alerting**: Define complex alerting rules based on metric thresholds
- **Rich Ecosystem**: Thousands of exporters for different services and applications
- **Time Series Database**: Efficiently stores and queries time-based metrics data

**What you get out-of-the-box:**
- Node CPU, memory, disk, network usage
- Pod resource consumption and limits
- Kubernetes API server metrics
- Cluster health and capacity metrics

### **2. Grafana** 📈
**What it does:** Data visualization and dashboard platform

**Benefits:**
- **Unified Interface**: Single pane of glass for all observability data
- **Pre-built Dashboards**: Thousands of community dashboards available
- **Alerting Integration**: Visual alerts with multiple notification channels
- **Query Correlation**: Jump between metrics, logs, and traces seamlessly

**What you get out-of-the-box:**
- Kubernetes cluster overview dashboards
- Node and pod resource utilization
- Pre-configured data sources for Loki and Tempo

### **3. Loki** 📝
**What it does:** Log aggregation system inspired by Prometheus

**Benefits:**
- **Cost Effective**: Doesn't index log content, only metadata (labels)
- **Kubernetes Native**: Automatically adds pod labels and metadata
- **LogQL**: Prometheus-like query language for logs
- **Grafana Integration**: Seamless log correlation with metrics

**What you get out-of-the-box:**
- All container logs from every pod in the cluster
- Automatic labeling with namespace, pod name, container name
- Log retention and compression

### **4. Promtail** 🚚
**What it does:** Log collection agent that feeds Loki

**Benefits:**
- **Automatic Discovery**: Finds and tails all pod logs automatically
- **Label Enhancement**: Adds Kubernetes metadata to log entries
- **Efficient**: Low resource overhead, designed for Kubernetes
- **Reliable**: Handles log rotation and pod restarts gracefully

### **5. Tempo** 🔍
**What it does:** Distributed tracing backend

**Benefits:**
- **Trace Storage**: Stores distributed traces for debugging complex requests
- **Grafana Integration**: View traces directly in Grafana dashboards
- **Correlation**: Link traces with logs and metrics using trace IDs
- **Scalable**: Designed for high-volume trace data

**What you need to do:**
- Instrument your applications with OpenTelemetry SDKs
- Configure trace exporters to send data to OpenTelemetry Collector

### **6. OpenTelemetry Collector** 🔄
**What it does:** Vendor-agnostic data collection and processing pipeline

**Benefits:**
- **Multi-Protocol**: Accepts traces in OTLP, Jaeger, Zipkin formats
- **Data Processing**: Batch, filter, and enhance telemetry data
- **Flexible Routing**: Send data to multiple backends
- **Standards Based**: Implements OpenTelemetry specification

### **7. Pixie** ✨ (The Game Changer)
**What it does:** Automatic application observability using eBPF

**Benefits:**
- **Zero Code Changes**: Uses eBPF to automatically capture application data
- **Full Visibility**: HTTP requests, database queries, network flows
- **Real-time**: Live debugging and monitoring without performance impact
- **Secure**: Data stays in your cluster, never sent to external services

**What you get automatically:**
- HTTP/HTTPS request tracing with full request/response bodies
- Database query monitoring (MySQL, PostgreSQL, Redis, Cassandra)
- Service dependency mapping
- Network traffic analysis
- Application profiling and flame graphs
- DNS request monitoring

## 🏗️ Overall Cluster Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                                 AWS VPC (10.0.0.0/16)                           │
├─────────────────────────────────────────────────────────────────────────────────┤
│  Public Subnets (10.0.101-103.0/24)      │    Private Subnets (10.0.1-3.0/24)   │
│  ┌─────────────────────────────────┐     │    ┌─────────────────────────────────┐
│  │         Internet Gateway        │     │    │         NAT Gateway             │   
│  │         Load Balancers          │     │    │                               │ │
│  │    ┌─────────────────────────┐  │     │    │    ┌─────────────────────────┐  │ 
│  │    │    Network Load         │  │     │    │    │      Worker Nodes       │  │ 
│  │    │    Balancer (NLB)       │  │     │    │    │   (Bottlerocket)        │  │ 
│  │    │                         │  │     │    │    │   t3.xlarge (2-5)       │  │ 
│  │    └─────────────────────────┘  │     │    │    └─────────────────────────┘  │ 
│  └─────────────────────────────────┘     │    └─────────────────────────────────┘ 
└─────────────────────────────────────────────────────────────────────────────────┘
│  Intra Subnets (10.0.51-53.0/24)         │
│  ┌─────────────────────────────────┐     │
│  │        EKS Control Plane        │     │
│  │     (Managed by AWS)            │     │
│  └─────────────────────────────────┘     │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                            Kubernetes Cluster                                   │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐                  │
│  │   Platform      │  │  Observability  │  │  Applications   │                  │
│  │   Services      │  │     Stack       │  │                 │                  │
│  │                 │  │                 │  │                 │                  │
│  │ • ArgoCD        │  │ • Prometheus    │  │ • Online        │                  │
│  │ • Ingress-Nginx │  │ • Grafana       │  │   Boutique      │                  │
│  │ • Cert-Manager  │  │ • Loki/Promtail │  │ • Your Apps     │                  │
│  │ • External-     │  │ • Tempo         │  │                 │                  │
│  │   Secrets       │  │ • OpenTelemetry │  │                 │                  │
│  │                 │  │ • Pixie         │  │                 │                  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘                  │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘

External Services:
├── Route53 (DNS)
├── AWS Parameter Store (Secrets)
├── Let's Encrypt (TLS Certificates)
└── Pixie Cloud (Trace Correlation)
```

## 📋 Prerequisites

Before deploying the observability layer, ensure you have:

1. **Foundation Layer** deployed (VPC, EKS cluster, IAM roles)
2. **Platform Layer (Step 02)** deployed (ArgoCD, Ingress, Cert-Manager, External-Secrets)
3. **Platform Layer (Step 03)** deployed (DNS records, certificate issuer, secret store)
4. **Pixie Deploy Key** from [withpixie.ai](https://withpixie.ai/)

### Getting a Pixie Deploy Key

1. Visit [withpixie.ai](https://withpixie.ai/) and create an account
2. Create a new project for your cluster
3. Go to Admin → Deploy Keys
4. Create a new deploy key and copy the value
5. This key will be used in the terraform variable

## 🚀 Deployment Instructions

### Step 1: Configure Variables

Create a `terraform.tfvars` file:

```hcl
domain = "your-domain.xyz"
pixie_deploy_key = "your-pixie-deploy-key-here"
```

### Step 2: Deploy the Stack

```bash
cd observability/
terraform init
terraform plan
terraform apply
```

### Step 3: Access Grafana

After deployment, access Grafana at:
- **URL**: `https://grafana.your-domain.xyz`
- **Username**: `admin`
- **Password**: `admin`

**⚠️ IMPORTANT**: Change the default password immediately after first login!

### Step 4: Verify Data Sources

In Grafana, go to Configuration → Data Sources and verify:
- ✅ Prometheus (metrics)
- ✅ Loki (logs)
- ✅ Tempo (traces)

## 📊 What You'll See Immediately

### **Grafana Dashboards Available:**

1. **Kubernetes Cluster Overview**
   - Node health and resource usage
   - Pod status across namespaces
   - Cluster capacity and utilization

2. **Application Logs** (via Loki)
   - Real-time log streaming
   - Log search and filtering
   - Error rate analysis

3. **HTTP Traffic Analysis** (via Pixie)
   - Request rate and latency
   - Error rate monitoring
   - Service dependency maps

4. **Database Performance** (via Pixie)
   - Query execution times
   - Slow query identification
   - Connection pool monitoring

### **Pixie Auto-Discovery:**

Pixie automatically discovers and monitors:
- HTTP/HTTPS services
- MySQL, PostgreSQL, Redis, Cassandra databases
- gRPC services
- DNS queries
- Network connections

## ⚠️ Important Notes & Gotchas

### **🔐 Security Considerations**

1. **Change Default Passwords**
   ```bash
   # Grafana admin password is set to 'admin' - CHANGE THIS!
   kubectl exec -n observability deployment/kube-prometheus-stack-grafana -- \
     grafana-cli admin reset-admin-password NEW_PASSWORD
   ```

2. **Pixie Data Privacy**
   - Pixie captures full HTTP request/response bodies
   - Ensure sensitive data is not logged in URLs or headers
   - Configure data access policies if needed

3. **Network Policies**
   - Consider implementing network policies to restrict traffic
   - Observability namespace should be isolated from application namespaces

### **💾 Storage & Retention**

1. **Persistent Volume Requirements**
   - Prometheus: 20GB (7-day retention)
   - Loki: 20GB (7-day retention)
   - Tempo: 20GB (7-day retention)
   - Grafana: 10GB (dashboards and config)

2. **Data Retention Policies**
   ```yaml
   # Adjust retention in values if needed
   prometheus:
     prometheusSpec:
       retention: 7d  # Increase for longer retention
   ```

### **🚨 Resource Usage**

1. **Node Requirements**
   - Minimum 3 nodes recommended for HA
   - Each node should have at least 4GB RAM available
   - Pixie requires minimum 1GB memory per node

2. **CPU Usage**
   - Pixie: ~2-5% CPU overhead per node
   - Prometheus: ~0.5-1 CPU core
   - Total stack: ~2-3 CPU cores cluster-wide

### **🔧 Common Issues & Solutions**

#### **Issue: Pixie Pods Stuck in Pending**
```bash
# Check node resources
kubectl describe nodes
# Pixie requires 1GB+ memory per node
kubectl edit deployment pixie-operator -n pl
```

#### **Issue: Grafana Shows No Data**
```bash
# Check Prometheus targets
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n observability
# Visit http://localhost:9090/targets
```

#### **Issue: Loki Not Receiving Logs**
```bash
# Check Promtail status
kubectl logs daemonset/promtail -n observability
kubectl get pods -l app=promtail -n observability
```

#### **Issue: TLS Certificate Not Issued**
```bash
# Check cert-manager logs
kubectl logs deployment/cert-manager -n cert-manager
kubectl describe certificate grafana-tls -n observability
```

### **🔄 Scaling Considerations**

1. **High Availability**
   ```yaml
   # For production, increase replicas
   prometheus:
     prometheusSpec:
       replicas: 2
   grafana:
     replicas: 2
   ```

2. **Storage Scaling**
   - Monitor disk usage regularly
   - Implement log rotation policies
   - Consider using AWS EBS with auto-scaling

### **📈 Performance Tuning**

1. **Prometheus Optimization**
   ```yaml
   # Adjust scrape intervals for large clusters
   prometheus:
     prometheusSpec:
       scrapeInterval: 30s  # Default 15s
       evaluationInterval: 30s
   ```

2. **Loki Optimization**
   ```yaml
   # For high log volume
   loki:
     limits_config:
       ingestion_rate_mb: 10
       ingestion_burst_size_mb: 20
   ```

## 🛠️ Maintenance Tasks

### **Daily**
- Monitor cluster resource usage
- Check for failed pods in observability namespace
- Review Grafana alerts

### **Weekly**
- Review storage usage and retention policies
- Update dashboards and queries
- Check Pixie cluster health

### **Monthly**
- Update Helm chart versions
- Review and optimize retention policies
- Backup Grafana dashboards and configurations

## 📚 Useful Commands

```bash
# Check all observability pods
kubectl get pods -n observability

# Access Grafana locally
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n observability

# Check Pixie status
kubectl get pods -n pl

# View Prometheus targets
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n observability

# Check Loki logs
kubectl logs deployment/loki -n observability

# Monitor resource usage
kubectl top nodes
kubectl top pods -n observability
```

## 🎯 Next Steps

1. **Add Custom Dashboards**
   - Import community dashboards for your specific applications
   - Create custom business metric dashboards

2. **Configure Alerting**
   - Set up AlertManager with Slack/email notifications
   - Define SLO-based alerting rules

3. **Application Instrumentation**
   - Add OpenTelemetry to your applications for distributed tracing
   - Configure custom metrics in your application code

4. **Advanced Pixie Usage**
   - Explore Pixie's PxL scripting language
   - Create custom monitoring scripts for your applications

## 🆘 Troubleshooting

If you encounter issues, check:

1. **Terraform State**: Ensure all resources are properly created
2. **Pod Status**: All pods should be in Running state
3. **PVC Status**: All persistent volume claims should be Bound
4. **Ingress**: DNS should resolve to the correct load balancer
5. **Certificates**: TLS certificates should be issued successfully

For additional help:
- Check the Grafana logs for data source connection issues
- Verify Pixie connectivity to Pixie Cloud
- Ensure sufficient cluster resources for all components

---

**🎉 Congratulations!** You now have a production-ready observability stack that provides comprehensive monitoring, logging, and tracing capabilities for your Kubernetes cluster and applications!