## Prod-Ready Platform

 - Building a platform for deploying application on AWS with k8s.
 - Terraform will be used throughout this platform.
 - Terrafform helps us create our infrastructure and make our infra provision easier.
 - The platform will be built in layers, to address Terraform's issues with handling dependencies with resources (DAG issue).
 - Terraform state management isn't an easy task, and as a best practice, it should be stored in an external storage like s3 for example.

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
