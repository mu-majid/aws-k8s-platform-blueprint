sequenceDiagram
    participant User as End User
    participant DNS as Route53 DNS
    participant NLB as AWS NLB
    participant Ingress as ingress-nginx
    participant App as E-commerce Application
    participant Redis as Redis Cache
    participant Storage as Persistent Storage
    participant Secrets as External Secrets Operator
    participant ParamStore as AWS Parameter Store
    
    %% User Request Flow
    User->>DNS: 1. Resolve app.domain.com
    DNS->>User: 2. Return NLB IP
    User->>NLB: 3. HTTPS Request
    NLB->>Ingress: 4. Forward to ingress
    Ingress->>App: 5. Route to application
    
    %% Application Initialization
    Note over App,ParamStore: Application bootstraps with platform services
    App->>Secrets: 6. Request application secrets
    Secrets->>ParamStore: 7. Fetch secrets from AWS
    ParamStore->>Secrets: 8. Return secrets
    Secrets->>App: 9. Inject secrets into app
    
    %% Application Operations
    App->>Redis: 10. Store session/cache data
    Redis->>App: 11. Return cached data
    App->>Storage: 12. Persist application data
    Storage->>App: 13. Return stored data
    
    %% Response to User
    App->>User: 14. Return application response
    
    %% Background Platform Operations
    Note over App: Platform services operate continuously
    App-->>+Prometheus: Metrics collection
    App-->>+Loki: Log aggregation
    App-->>+Tempo: Distributed tracing
    
    Note over Velero,Storage: Backup operations
    Velero-->>Storage: Backup application data
    
    Note over Kyverno,App: Security enforcement
    Kyverno-->>App: Policy validation
    
    Note over Trivy,App: Security scanning
    Trivy-->>App: Vulnerability scanning