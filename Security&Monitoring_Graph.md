flowchart TD
    subgraph Security["Security Layer"]
        Kyverno[Kyverno]
        Trivy[Trivy Operator]
        Prowler[Prowler]
    end
    
    subgraph Observability["Observability Stack"]
        Prometheus[Prometheus]
        Grafana[Grafana]
        Loki[Loki]
        OTel[OpenTelemetry Collector]
        Pixie[Pixie]
    end
    
    subgraph Application["Application Workloads"]
        EcommerceApp[E-commerce Application]
        Redis[Redis Cache]
        Storage[Persistent Storage]
    end
    
    subgraph Platform["Platform Services"]
        Nginx[ingress-nginx]
        ArgoCD[ArgoCD]
        OpenCost[OpenCost]
        ESO[External Secrets Operator]
        CertMgr[cert-manager]
        Autoscaler[Cluster Autoscaler]
        EBSCSI[EBS CSI Driver]
        Velero[Velero]
    end
    
    subgraph External["External Storage & APIs"]
        S3Reports[S3 Prowler Reports]
        S3Backup[S3 Backup Bucket]
        ParamStore[Parameter Store]
        Route53[Route53 DNS]
    end
    
    %% Security Enforcement
    Kyverno -->|policy validation| EcommerceApp
    Kyverno -->|policy validation| Redis
    Kyverno -->|policy validation| Platform
    
    Trivy -->|vulnerability scanning| EcommerceApp
    Trivy -->|image scanning| Platform
    
    Prowler -->|AWS security assessment| S3Reports
    
    %% Monitoring Collection - Applications
    EcommerceApp -->|/metrics endpoint| Prometheus
    Redis -->|metrics| Prometheus
    Storage -->|storage metrics| Prometheus
    
    %% Monitoring Collection - Platform Services
    Nginx -->|ingress metrics| Prometheus
    ArgoCD -->|deployment metrics| Prometheus
    OpenCost -->|cost metrics| Prometheus
    ESO -->|secret sync metrics| Prometheus
    CertMgr -->|certificate metrics| Prometheus
    Autoscaler -->|scaling metrics| Prometheus
    EBSCSI -->|storage metrics| Prometheus
    Velero -->|backup metrics| Prometheus
    
    %% Log Collection
    EcommerceApp -->|application logs| Loki
    Platform -->|platform logs| Loki
    
    %% Distributed Tracing
    EcommerceApp -->|traces & spans| OTel
    
    %% Real-time Debugging
    EcommerceApp -.->|runtime observability| Pixie
    Platform -.->|system observability| Pixie
    
    %% Observability Queries
    Grafana -->|metrics queries| Prometheus
    Grafana -->|log queries| Loki
    Grafana -->|trace queries| OTel
    Grafana -.->|real-time data| Pixie
    
    %% Platform Operations
    ESO -->|fetch secrets| ParamStore
    CertMgr -->|DNS challenges| Route53
    Velero -->|backup storage| S3Backup
    
    %% Cost Monitoring
    OpenCost -->|resource usage| Prometheus
    OpenCost -->|cost allocation| EcommerceApp