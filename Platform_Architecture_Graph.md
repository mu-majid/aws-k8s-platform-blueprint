flowchart TD
    %% External Systems
    Users[Internet Users]
    
    subgraph AWS["AWS Services"]
        Route53[Route53 DNS]
        S3Backup[S3 Backup Bucket]
        S3Prowler[S3 Prowler Reports]
        ParamStore[Parameter Store]
        NLB[AWS Load Balancer NLB]
    end
    
    subgraph EKS["EKS Cluster"]
        
        subgraph Ingress["Ingress Layer"]
            Nginx[ingress-nginx]
            CertMgr[cert-manager]
        end
        
        subgraph App["Application Workloads"]
            EcommerceApp[E-commerce Application]
        end
        
        subgraph Data["Data Layer"]
            Redis[Redis Cache]
            Storage[Persistent Storage EBS]
        end
        
        subgraph Platform["Platform Services"]
            ArgoCD[ArgoCD]
            ESO[External Secrets Operator]
        end
        
        subgraph Observability["Observability Stack"]
            Prometheus[Prometheus]
            Grafana[Grafana]
            Loki[Loki]
            Tempo[Tempo]
            OTel[OpenTelemetry Collector]
            Pixie[Pixie]
        end
        
        subgraph FinOps["FinOps & Cost"]
            OpenCost[OpenCost]
        end
        
        subgraph Security["Security Stack"]
            Kyverno[Kyverno]
            Trivy[Trivy Operator]
            Prowler[Prowler CronJob]
        end
        
        subgraph Resilience["Backup & DR"]
            Velero[Velero]
        end
        
        subgraph Infrastructure["Infrastructure Services"]
            Autoscaler[Cluster Autoscaler]
            EBSCSI[EBS CSI Driver]
        end
    end
    
    %% User Flow
    Users --> Route53
    Route53 --> NLB
    NLB --> Nginx
    Nginx --> EcommerceApp
    Nginx --> Grafana
    Nginx --> OpenCost
    Nginx --> ArgoCD
    
    %% Application Dependencies
    EcommerceApp --> Redis
    EcommerceApp --> Storage
    
    %% Platform Data Flow
    ESO --> ParamStore
    CertMgr --> Route53
    Prometheus --> EcommerceApp
    Prometheus --> Platform
    Prometheus --> Infrastructure
    Grafana --> Prometheus
    Grafana --> Loki
    Grafana --> Tempo
    Loki -.-> EcommerceApp
    Tempo -.-> OTel
    OTel -.-> EcommerceApp
    OpenCost --> Prometheus
    Velero --> S3Backup
    Velero --> Storage
    Prowler --> S3Prowler
    Trivy --> EcommerceApp
    Kyverno --> EcommerceApp
    EBSCSI --> Storage