# Security Layer - Platform Protection & Compliance

## Purpose

The Security layer provides comprehensive protection for your Kubernetes platform through policy enforcement, vulnerability scanning, cloud security assessment, and runtime threat detection.

## Security Components

### Deployed Tools

#### 1. **Kyverno - Configuration Security**
- **Purpose**: Policy engine for Kubernetes configuration validation
- **Features**:
  - Prevents privileged containers
  - Enforces resource limits
  - Validates security contexts
  - Mutates resources automatically
- **Integration**: Metrics exposed to Prometheus

#### 2. **Trivy Operator - Image Security**
- **Purpose**: Vulnerability scanning for container images and configurations
- **Features**:
  - Continuous image scanning
  - CIS benchmark compliance
  - Configuration assessment
  - SBOM generation
- **Storage**: Uses gp2-csi storage class for scan cache

#### 3. **Falco - Runtime Monitoring**
- **Purpose**: Real-time threat detection and runtime security
- **Features**:
  - Syscall monitoring via eBPF
  - Behavioral anomaly detection
  - Security rule violations
  - Real-time alerting
- **Integration**: Events sent to Grafana via Falcosidekick

#### 4. **Prowler - Cloud Security Posture**
- **Purpose**: AWS security assessment and compliance checking
- **Features**:
  - CIS AWS benchmarks
  - Security best practices validation
  - Compliance reporting
  - Automated weekly scans
- **Storage**: Reports saved to dedicated S3 bucket

#### 5. **Security Dashboard**
- **Purpose**: Unified security monitoring in Grafana
- **Features**:
  - Policy violation metrics
  - Vulnerability summaries
  - Runtime alert tracking
  - Security events timeline

---

## Deployment

### Prerequisites
- Existing observability layer (Prometheus/Grafana)
- Storage class `gp2-csi` available
- AWS IAM permissions for security assessment

### Deploy Security Layer
```bash
# Navigate to security layer
cd layers/07_security/

# Initialize and deploy
terraform init
terraform plan
terraform apply
```

### Verify Deployment
```bash
# Check all security tools
kubectl get pods -n kyverno
kubectl get pods -n trivy-system  
kubectl get pods -n falco-system

# Verify Prowler CronJob
kubectl get cronjob prowler-security-scan -n kube-system
```

---

## Monitoring & Access

### Security Dashboard
- **Grafana**: `https://grafana.terraform-aws-platform.xyz`
- **Dashboard**: "Security Overview - Platform Security Monitoring"
- **Metrics**: Policy violations, vulnerabilities, runtime alerts

### Security Reports
```bash
# View Kyverno policies
kubectl get clusterpolicies

# Check policy violations
kubectl get events --field-selector reason=PolicyViolation -A

# View vulnerability reports
kubectl get vulnerabilityreports -A
kubectl get configauditreports -A

# Check Falco alerts
kubectl logs -n falco-system -l app.kubernetes.io/name=falco | grep "Priority:Critical"

# Access Prowler reports
aws s3 ls s3://$(terraform output -raw prowler_s3_bucket)/
```

---

## Policy Management

### Kyverno Policies

#### View Active Policies
```bash
kubectl get clusterpolicies
kubectl describe clusterpolicy disallow-privileged-containers
```

#### Test Policy Enforcement
```bash
# This should be blocked by Kyverno
kubectl run test-privileged --image=nginx --privileged=true
```

#### Add Custom Policies
```yaml
# Example: Require specific labels
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-labels
spec:
  validationFailureAction: enforce
  rules:
    - name: check-labels
      match:
        any:
        - resources:
            kinds: [Pod]
      validate:
        message: "Required labels missing"
        pattern:
          metadata:
            labels:
              app: "?*"
              version: "?*"
```

---

## Vulnerability Management

### Trivy Scanning

#### View Vulnerability Reports
```bash
# List all vulnerability reports
kubectl get vulnerabilityreports -A

# Get detailed vulnerability info
kubectl describe vulnerabilityreport <report-name> -n <namespace>

# View by severity
kubectl get vulnerabilityreports -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.report.summary}{"\n"}{end}'
```

#### Scan Specific Images
```bash
# Trivy will automatically scan all images
# Manual scanning can be triggered by creating VulnerabilityReport resources
```

#### Compliance Reports
```bash
# View CIS benchmark reports
kubectl get configauditreports -A
kubectl describe configauditreport <report-name> -n <namespace>
```

---

## Runtime Security

### Falco Monitoring

#### View Real-time Alerts
```bash
# Stream Falco alerts
kubectl logs -f -n falco-system -l app.kubernetes.io/name=falco

# Filter by priority
kubectl logs -n falco-system -l app.kubernetes.io/name=falco | grep "Priority:Critical"
kubectl logs -n falco-system -l app.kubernetes.io/name=falco | grep "Priority:Warning"
```

#### Common Alert Types
- **Privilege escalation attempts**
- **Unexpected network connections**
- **File system modifications in containers**
- **Shell execution in containers**
- **Suspicious process spawning**

#### Custom Falco Rules
```yaml
# Add to custom rules ConfigMap
- rule: Detect crypto mining
  desc: Detect cryptocurrency mining activity
  condition: >
    spawned_process and 
    (proc.name in (crypto_miners))
  output: >
    Crypto mining detected (user=%user.name command=%proc.cmdline)
  priority: WARNING
```

---

## Cloud Security Assessment

### Prowler Reports

#### Access Reports
```bash
# List available reports
aws s3 ls s3://$(terraform output -raw prowler_s3_bucket)/

# Download latest report
aws s3 cp s3://$(terraform output -raw prowler_s3_bucket)/$(date +%Y-%m-%d)/ ./prowler-reports/ --recursive
```

#### Manual Prowler Scan
```bash
# Run immediate scan
kubectl create job prowler-manual-scan --from=cronjob/prowler-security-scan -n kube-system
```

#### Key Security Areas Assessed
- **IAM policies and roles**
- **Network security groups**
- **Encryption at rest and in transit**
- **Logging and monitoring**
- **Access management**
- **Resource configuration**

---

## Security Metrics

### Grafana Dashboard Metrics

#### Policy Enforcement
- Total policy violations
- Violations by policy type
- Namespace violation trends
- Policy enforcement rate

#### Vulnerability Management  
- Vulnerability count by severity
- Images with critical vulnerabilities
- Vulnerability trends over time
- Compliance score

#### Runtime Security
- Falco alert frequency
- Alert types distribution
- High-priority incidents
- Response time metrics

---

## Troubleshooting

### Common Issues

#### Kyverno Policy Failures
```bash
# Check policy validation errors
kubectl get events --field-selector reason=PolicyViolation -A

# Validate policy syntax
kubectl apply --dry-run=server -f policy.yaml
```

#### Trivy Scanning Issues
```bash
# Check scanner pod logs
kubectl logs -n trivy-system -l app.kubernetes.io/name=trivy-operator

# Verify storage
kubectl get pvc -n trivy-system
```

#### Falco Not Detecting Events
```bash
# Check Falco driver
kubectl logs -n falco-system -l app.kubernetes.io/name=falco | grep driver

# Verify eBPF probe
kubectl exec -n falco-system -l app.kubernetes.io/name=falco -- falco --version
```

#### Prowler Job Failures
```bash
# Check job status
kubectl describe job -n kube-system -l job-name=prowler-security-scan

# View job logs
kubectl logs -n kube-system -l job-name=prowler-security-scan
```

---

## Maintenance

### Regular Tasks

#### Weekly
- Review Prowler reports for new security issues
- Check Trivy vulnerability reports for critical CVEs
- Analyze Falco alerts for patterns

#### Monthly  
- Update Kyverno policies based on violations
- Review and tune Falco rules
- Update security baselines

#### Quarterly
- Review and update security tool versions
- Conduct security posture assessment
- Update compliance requirements

---

## Incident Response

### Security Event Response

#### High-Priority Falco Alert
1. **Investigate**: Check alert details and affected resources
2. **Isolate**: Network policies to contain potential threat
3. **Analyze**: Review container logs and system calls
4. **Remediate**: Remove malicious workloads if confirmed
5. **Document**: Record incident for future prevention

#### Critical Vulnerability Discovery
1. **Assess**: Check vulnerability impact and exploitability
2. **Prioritize**: Based on CVSS score and exposure
3. **Patch**: Update base images and redeploy
4. **Verify**: Confirm vulnerability remediation
5. **Monitor**: Watch for related exploitation attempts

---

## Integration Points

- **Observability Layer**: Metrics collection and alerting
- **FinOps Layer**: Security cost tracking and optimization
- **Platform Layers**: Policy enforcement for all deployments
- **Resilience Layer**: Security considerations in backup/restore

---

## Additional Resources

- [Kyverno Policy Library](https://kyverno.io/policies/)
- [Trivy Vulnerability Database](https://github.com/aquasecurity/trivy-db)
- [Falco Rules Repository](https://github.com/falcosecurity/rules)
- [Prowler Checks Documentation](https://github.com/prowler-cloud/prowler)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)

---