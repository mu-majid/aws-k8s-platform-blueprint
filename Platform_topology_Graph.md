flowchart TD
    subgraph Layer1["Layer 1: Foundation"]
        EKS[EKS Cluster]
        VPC[VPC + Subnets]
        IAM[IAM Roles IRSA]
        Route53[Route53 Hosted Zone]
    end
    
    subgraph Layer2["Layer 2: Core Platform"]
        ESO[External Secrets Operator]
        CertMgr[cert-manager]
        Nginx[ingress-nginx]
        ArgoCD[ArgoCD]
        Autoscaler[Cluster Autoscaler]
        EBSCSI[EBS CSI Driver]
    end
    
    subgraph Layer3["Layer 3: Configuration"]
        DNSRecords[DNS Records]
        ClusterIssuer[Let's Encrypt ClusterIssuer]
        SecretStore[ClusterSecretStore]
    end
    
    subgraph Layer4["Layer 4: Observability"]
        PrometheusStack[Prometheus Stack]
        Grafana[Grafana]
        LokiPromtail[Loki + Promtail]
        Tempo[Tempo]
        OTelCollector[OpenTelemetry Collector]
        Pixie[Pixie]
    end
    
    subgraph Layer5["Layer 5: Resilience"]
        Velero[Velero]
        S3Backup[S3 Backup Storage]
    end
    
    subgraph Layer6["Layer 6: FinOps"]
        OpenCost[OpenCost]
        CostDashboards[Cost Dashboards]
    end
    
    subgraph Layer7["Layer 7: Security"]
        KyvernoPolicies[Kyverno Policies]
        TrivyScanning[Trivy Scanning]
        ProwlerAssessment[Prowler Assessment]
    end
    
    subgraph AppLayer["Application Layer"]
        Applications[Application Workloads]
        DataServices[Data Services Redis, Databases]
        Storage[Persistent Storage EBS]
    end
    
    %% Dependencies
    Layer1 --> Layer2
    Layer2 --> Layer3
    Layer3 --> Layer4
    Layer4 --> Layer5
    Layer5 --> Layer6
    Layer6 --> Layer7
    Layer7 --> AppLayer
    
    %% Platform Capabilities
    Layer1 -.->|provides| Infrastructure[Infrastructure Foundation]
    Layer2 -.->|provides| CoreServices[Core Platform Services]
    Layer3 -.->|provides| Configuration[Service Configuration]
    Layer4 -.->|provides| Monitoring[Full Observability]
    Layer5 -.->|provides| BackupDR[Backup & Disaster Recovery]
    Layer6 -.->|provides| CostOptimization[Cost Monitoring & Optimization]
    Layer7 -.->|provides| SecurityGovernance[Security & Governance]
    AppLayer -.->|delivers| BusinessValue[Business Applications]