## Prod-Ready Platform

 - Building a platform for deploying application on AWS with k8s.
 - Terraform will be used throughout this platform.
 - Terrafform helps us create our infrastructure and make our infra provision easier.
 - The platform will be built in layers, to address Terraform's issues with handling dependencies with resources (DAG issue).
 - Terraform state management isn't an easy task, and as a best practice, it should be stored in an external storage like s3 for example.

## Prerequistes:
  1. terraform cli.
  2. aws-cli. (configured properly)

### Layers

  - in each layer there will be two files `main.tf` and `providers.tf`.
  - `main.tf` file will hold the definitions of the resources to be created.
  - `providers.tf` file will hold the versions of the providers to be used, helps terraform communicate with APIs.

  #### 1. Foundation
  - This layer holds all the necessary components for any cluster
      - VPC
      - Subnets
      - IAM
      - DNS
      - Cluster (a collection of worker nodes, and control plane. cluster is basically k8s cluster)
      - NAT
  - RUN `terraform init` inside the foundation folder
  - The `.terraform.lock.hcl` file is Terraform's dependency lock file. It:

      - Locks provider versions - Records the exact versions of providers that were downloaded
      - Ensures consistency - Makes sure everyone on your team uses the same provider versions
      - Prevents drift - Stops providers from auto-updating to newer versions unexpectedly
      - Contains checksums - Verifies provider authenticity and integrity

      **Should you commit it?** Yes, always commit it to version control.
      **When is it created?** During terraform init when providers are downloaded.
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

  - After running `terraform apply`, all resources should be created on AWS.
  - now we run `aws eks update-kubeconfig --region [YOUR_REGION] --name [CLUSTER_NAME]` to download the certificate that allows us to communicate with the API via kubectl. Then we can run kubectl get nodes to check the nodes (internal k8s nodes.)

  #### 2. Platform
  - Split into two steps: **Step02** installing the software with basic config, and **Step03**: configuring the software
  - This layer will consist of the components needed for k8s to be ready for PROD - they are defined as helm charts.
      1. Gateway/Ingress (Ingress Nginx) // For routing traffic inside the cluster
      2. Secret Management (External Secret Operator) // for syncing secrets in a secure way
      3. Certificate Management (Cert Manager) // For TLS certificate issuance
      4. Continous Delivery (Argo CD) // deploying the application with the GitOps pattern
      5. Cluster Autoscaling

  - We can handle secrets in our cluster in three different ways:
    1. Using secret manager like Vault, and when the container is spinned up, we query vault for the secrets, then inject them in the container.
    2. Sealed secrets, where we encrypt the secrets and put them in our yaml manifests, and these encrypted values are commited in our git repo. [No secret manager is needed here - secret rotation is handled manually]
    3. external secret operator is running inside the cluster, it is a resource that we can use to make it point to a store (KeyVault, AWS parameters, ...) - And we commit a reference to this secret in our yaml manifests (in the app)

  - Note in the ingress resource, we set `enableHttp: true` for the certManager to be able to issue certificates.
  - Good read on aws load balancer types: [Network vs Application LB](https://aws.amazon.com/compare/the-difference-between-the-difference-between-application-network-and-gateway-load-balancing/)

  -  ArgoCD is a GitOps tool that monitors git, and once it sees a change (in code or config, depends how it was set up), it will deploy and update the cluster.
  - RUN `terraform init` to configure the providers.
  - RUN `terraform apply` to create the resources.
  - in Step03 we will configure:
    1. DNS -> create a DNS record in the hostedZone on AWSRoute53, and make it point to our cluster's ingress
      This means we have a domain, and we want to map this domain to our ingress's ip
      RUN `kubectl -n ingress-nginx get svc` -> you can see the ingress IP
    2. configure `cert-manager` to create TLS certificates (Let's encrypt is used for issuing the cert)
      Automatic SSL: When you create an Ingress with TLS, cert-manager will automatically:
      a. Request a certificate from Let's Encrypt
      b. Serve the challenge file via nginx
      c. Get the certificate and store it in Kubernetes
      d. Auto-renew before expiration
    3. Configure the secrets manager -> external-secrets operator can fetch certificates/secrest from aws parameter store
      A serviceAccount named secret-store (assuming the role created in foundation) will be created, and a ParameterStore as a secrets store.
      Automatic Secret Sync: You can now create ExternalSecret resources that:
      a. Reference secrets stored in AWS Parameter Store
      b. Automatically sync them to Kubernetes secrets
      c. Keep them updated when Parameter Store values change

  - Hosted zones are AWS's way of organizing and managing all DNS records for a domain in one place.
      Hosted Zone: terraform-aws-platform.xyz
          ├── A Record: terraform-aws-platform.xyz → 192.168.1.100
          ├── CNAME Record: app.terraform-aws-platform.xyz → load-balancer.aws.com
          ├── MX Record: mail.terraform-aws-platform.xyz → mail-server.com
          ├── NS Records: (nameservers that handle this zone)
          └── SOA Record: (zone authority information)