# NAM-PROD EKS Cluster - Comprehensive Guide

## Table of Contents
1. [Cluster Overview](#cluster-overview)
2. [How Kubernetes Applications Connect](#1-how-kubernetes-applications-connect)
3. [Application Connections via KMS and External Secrets](#2-application-connections-via-kms-and-external-secrets)
4. [Helm in the Deployment Pipeline](#3-helm-in-the-deployment-pipeline)
5. [Deployment Strategies](#4-deployment-strategies)
6. [End-to-End Flow Diagram](#5-end-to-end-flow-diagram)
7. [CI/CD Pipeline](#6-cicd-pipeline)
8. [Authentication Mechanisms](#7-authentication-mechanisms)

---

## Cluster Overview

The **nam-prod EKS cluster** is a production-grade Amazon Elastic Kubernetes Service (EKS) cluster deployed in the `ap-southeast-2` region.

### Core Infrastructure
- **Cluster Name**: `nam-prod-cluster`
- **Kubernetes Version**: 1.32
- **Environment**: Production (`nam-prod`)
- **Region**: ap-southeast-2 (Sydney)
- **Node Group**: 3 nodes (min 2, max 6) using `c7i.4xlarge` instances
- **Capacity Type**: ON_DEMAND
- **Networking**: VPC with private subnets, public endpoint access enabled

### Key Add-ons
- CoreDNS
- VPC CNI
- EBS CSI Driver
- Kube Proxy
- Pod Identity Agent

### Storage
- 100GB GP3 encrypted EBS volumes per node
- KMS encryption for all storage

---

## 1. How Kubernetes Applications Connect

### Pod-to-Pod Communication
```
Application Pod A → Service (ClusterIP) → Application Pod B
                    ↓
                DNS Resolution (CoreDNS)
```

**Process:**
1. Pod A sends request to service name (e.g., `database-service`)
2. CoreDNS resolves service name to ClusterIP
3. kube-proxy routes traffic to healthy backend pods
4. VPC CNI provides native AWS networking (each pod gets a VPC IP)

### Pod-to-External Services
```
Application Pod → Service → AWS Service (S3, RDS, Secrets Manager)
                   ↓
              IRSA (IAM Role) → AWS API
```

**Key Components:**
- **IRSA (IAM Roles for Service Accounts)**: Allows pods to assume AWS IAM roles
- **ServiceAccount**: Kubernetes identity mapped to AWS IAM role
- **OIDC Provider**: EKS-managed authentication bridge between K8s and AWS

### External-to-Pod Communication
```
User/Internet → AWS Load Balancer → Ingress Controller → Service → Pod
                                          ↓
                                    TLS Termination
```

**Components:**
- **AWS Load Balancer Controller**: Manages ALB/NLB creation
- **Ingress Resources**: Define HTTP/HTTPS routing rules
- **Services**: Expose pods within the cluster
- **Network Policies**: Control traffic between namespaces

---

## 2. Application Connections via KMS and External Secrets

### Complete Secret Management Flow

```
┌─────────────────────────────────────────────────────────────────┐
│  AWS Secrets Manager / Parameter Store                          │
│  (Encrypted with KMS Key)                                       │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        │ (1) External Secrets Operator queries
                        │     using IRSA role
                        ↓
┌─────────────────────────────────────────────────────────────────┐
│  External Secrets Operator Pod                                  │
│  ServiceAccount: external-secrets                               │
│  IRSA Role: irsa-external-secrets-operator                      │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        │ (2) Fetches secret and creates
                        │     Kubernetes Secret
                        ↓
┌─────────────────────────────────────────────────────────────────┐
│  Kubernetes Secret (Base64 encoded)                             │
│  Created in target namespace                                    │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        │ (3) Mounted as volume or env var
                        ↓
┌─────────────────────────────────────────────────────────────────┐
│  Application Pod                                                │
│  Reads secret from /mnt/secrets/ or ENV                         │
└─────────────────────────────────────────────────────────────────┘
```

### Step-by-Step Process

#### Step 1: Secret Storage (AWS Side)
```yaml
AWS Secrets Manager Secret:
  Name: prod/database/password
  Encryption: KMS key (nam-prod-eks-cluster-key)
  IAM Policy: Allows irsa-external-secrets-operator role to read
  Content: {
    "username": "admin",
    "password": "securePassword123",
    "host": "database.example.com"
  }
```

#### Step 2: IRSA Authentication
```yaml
ServiceAccount Configuration:
  apiVersion: v1
  kind: ServiceAccount
  metadata:
    name: external-secrets
    namespace: external-secrets
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::803103365620:role/irsa-external-secrets-operator
```

**Authentication Flow:**
1. Pod starts with ServiceAccount `external-secrets`
2. EKS mutating webhook injects AWS credentials path
3. Pod reads OIDC token from `/var/run/secrets/eks.amazonaws.com/serviceaccount/token`
4. AWS SDK calls STS `AssumeRoleWithWebIdentity`
5. STS validates token against EKS OIDC provider
6. Returns temporary credentials (valid 1 hour)

#### Step 3: ExternalSecret Resource
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-database-secret
  namespace: fsai-os
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secretsmanager
    kind: ClusterSecretStore
  target:
    name: database-credentials
    creationPolicy: Owner
  data:
  - secretKey: username
    remoteRef:
      key: prod/database/password
      property: username
  - secretKey: password
    remoteRef:
      key: prod/database/password
      property: password
```

#### Step 4: Application Consumption
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: application
  namespace: fsai-os
spec:
  template:
    spec:
      containers:
      - name: app
        image: myapp:v1.0
        env:
        - name: DB_USERNAME
          valueFrom:
            secretKeyRef:
              name: database-credentials
              key: username
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: database-credentials
              key: password
```

### KMS Encryption Flow
```
Plaintext Secret 
    ↓
KMS Encrypt (using Customer Managed Key)
    ↓
Encrypted Secret → AWS Secrets Manager
    ↓
External Secrets Operator fetches via IRSA
    ↓
KMS Decrypt (automatic via AWS SDK)
    ↓
Plaintext → Kubernetes Secret (Base64 encoded)
    ↓
Pod mounts/reads secret
```

**KMS Key Administrators:**
- `FutureSecureAI-Admin-GitHub-actions-runner` (for automation)
- `AWSReservedSSO_AWSAdministratorAccess_xxx` (for manual operations)

---

## 3. Helm in the Deployment Pipeline

### Helm Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Git Repository (cloud-platforms)                               │
│  ├── helmfile/external-secrets/                                 │
│  ├── helmfile/argocd-core/                                      │
│  ├── helmfile/monitoring/                                       │
│  └── helmfile/logging/                                          │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        │ (1) Helmfile reads configuration
                        ↓
┌─────────────────────────────────────────────────────────────────┐
│  Helmfile (Local or GitHub Actions)                             │
│  - Aggregates multiple Helm releases                            │
│  - Manages dependencies between charts                          │
│  - Handles environment-specific values                          │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        │ (2) Generates Helm commands
                        ↓
┌─────────────────────────────────────────────────────────────────┐
│  Helm CLI                                                        │
│  - helm upgrade --install                                        │
│  - Connects to EKS cluster                                       │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        │ (3) Sends Kubernetes manifests
                        ↓
┌─────────────────────────────────────────────────────────────────┐
│  Kubernetes API Server (EKS)                                    │
│  - Creates/updates resources                                    │
│  - Stores release info in Secrets                               │
└─────────────────────────────────────────────────────────────────┘
```

### Helmfile Structure
```yaml
# helmfile/external-secrets/helmfile.yaml.gotmpl
repositories:
  - name: external-secrets
    url: https://charts.external-secrets.io

releases:
  - name: external-secrets
    namespace: external-secrets
    chart: external-secrets/external-secrets
    version: 0.10.0
    values:
      - values/common.yaml
      - values/aws/nam-prod.yaml  # Environment-specific overrides
```

### Directory Structure
```
helmfile/
├── external-secrets/
│   ├── helmfile.yaml.gotmpl
│   ├── values/
│   │   ├── common.yaml
│   │   └── aws/
│   │       └── nam-prod.yaml
│   └── versions.yaml
├── argocd-core/
├── monitoring/
└── logging/
```

### Why Helm?

1. **Templating**: Reuse charts across environments (dev, staging, prod)
2. **Versioning**: Rollback to previous releases with `helm rollback`
3. **Dependency Management**: Install prerequisites automatically
4. **Values Hierarchy**: Override defaults with environment-specific configs
5. **Package Management**: Use community charts from ArtifactHub
6. **Release Management**: Track deployment history

### Helm vs. Helmfile

| **Helm** | **Helmfile** |
|----------|--------------|
| Deploys single chart | Deploys multiple charts |
| Manual dependency management | Automatic dependency resolution |
| Multiple commands for multi-chart apps | Single command for all charts |
| No environment management | Built-in environment support |

---

## 4. Deployment Strategies

### Strategy 1: GitOps with ArgoCD (Preferred)

```
Developer → Git Push → GitHub Repo
                          ↓
                    ArgoCD watches repo
                          ↓
                    ArgoCD detects changes
                          ↓
                    ArgoCD syncs to cluster
                          ↓
                    Kubernetes applies manifests
                          ↓
                    Rolling update of pods
```

**Configuration:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: monitoring
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/org/cloud-platforms
    targetRevision: main
    path: helmfile/monitoring
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
```

**Benefits:**
- Declarative: Git is the single source of truth
- Self-healing: Automatically reverts manual changes
- Audit trail: All changes tracked in Git
- Rollback: Simple git revert

### Strategy 2: GitHub Actions CI/CD

```
Developer → Git Push → GitHub Actions Workflow
                          ↓
                    (1) Authenticate to AWS (OIDC)
                          ↓
                    (2) Assume IAM role
                          ↓
                    (3) Update kubeconfig
                          ↓
                    (4) Run helmfile apply
                          ↓
                    Kubernetes deploys application
```

**Workflow Example:**
```yaml
name: Deploy to EKS
on:
  push:
    branches: [main]
    paths:
      - 'helmfile/**'

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::803103365620:role/FutureSecureAI-Admin-GitHub-actions-runner
          aws-region: ap-southeast-2
      
      - name: Update kubeconfig
        run: aws eks update-kubeconfig --name nam-prod-cluster --region ap-southeast-2
      
      - name: Deploy with Helmfile
        run: |
          helmfile --environment nam-prod apply
```

### Strategy 3: Manual Deployment

```bash
# Using Taskfile
task tf-base-apply PROVIDER=aws ACCOUNT=nam-prod TF_STACK=eks

# Using Helmfile directly
export CLOUD_PROVIDER=aws
export CLUSTER=nam-prod
export ENVIRONMENT=nam-prod
helmfile apply
```

### Kubernetes Deployment Strategies

#### Rolling Update (Default)
```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1
```

**Flow:**
```
Old Pod v1.0 ─┐
Old Pod v1.0 ─┤ (Running)
Old Pod v1.0 ─┘
     ↓
Old Pod v1.0 ─┐
Old Pod v1.0 ─┤ 
New Pod v1.1 ─┘ (Created)
     ↓
Old Pod v1.0 ─┐
New Pod v1.1 ─┤ (All healthy)
New Pod v1.1 ─┘
     ↓
New Pod v1.1 ─┐
New Pod v1.1 ─┤ (Old pods terminated)
New Pod v1.1 ─┘
```

#### Blue-Green Deployment
```yaml
# Blue (current)
Deployment: app-blue (replicas: 3)
Service: app → selector: version=blue

# Deploy Green
Deployment: app-green (replicas: 3)
Service: app → selector: version=blue (no change yet)

# Switch traffic
Service: app → selector: version=green

# Cleanup
Delete Deployment: app-blue
```

#### Canary Deployment
```yaml
# Production: 90% traffic
Deployment: app-stable (replicas: 9)

# Canary: 10% traffic
Deployment: app-canary (replicas: 1)

# Same service routes to both
Service: app → selector: app=myapp (no version)

# Monitor metrics, gradually increase canary
```

---

## 5. End-to-End Flow Diagram

```
┌────────────────────────────────────────────────────────────────────────────┐
│                          DEVELOPER / OPERATIONS                            │
│  Developer Laptop  │  GitHub Actions  │  SSO Admin via AWS Console        │
└────────┬──────────────────┬─────────────────────┬──────────────────────────┘
         │                  │                     │
         │ (1) Git Push     │ (2) Workflow        │ (3) AWS SSO Login
         │                  │     Triggered       │
         ↓                  ↓                     ↓
┌────────────────────────────────────────────────────────────────────────────┐
│                        AUTHENTICATION LAYER                                │
│  ┌──────────────┐   ┌──────────────┐   ┌────────────────────────┐        │
│  │  GitHub      │   │  GitHub      │   │  AWS IAM Identity      │        │
│  │  Repository  │   │  OIDC        │   │  Center (SSO)          │        │
│  └──────┬───────┘   └──────┬───────┘   └────────┬───────────────┘        │
└─────────┼──────────────────┼────────────────────┼────────────────────────┘
          │                  │                    │
          │                  │ AssumeRole         │ AssumeRole
          ↓                  ↓                    ↓
┌────────────────────────────────────────────────────────────────────────────┐
│                          AWS IAM ROLES                                     │
│  ┌────────────────────────────────────────────────────────────┐           │
│  │  FutureSecureAI-Admin-GitHub-actions-runner (IAM Role)     │           │
│  │  AWSReservedSSO_AWSAdministratorAccess (IAM Role)          │           │
│  │  AWSReservedSSO_PowerUserAccess (IAM Role)                 │           │
│  └────────────────────────┬───────────────────────────────────┘           │
└───────────────────────────┼───────────────────────────────────────────────┘
                            │
                            │ (4) EKS Access Entry
                            │     Cluster Admin Policy
                            ↓
┌────────────────────────────────────────────────────────────────────────────┐
│                     EKS CONTROL PLANE (nam-prod-cluster)                   │
│  Kubernetes API Server  │  OIDC Provider  │  KMS Encryption               │
└────────┬───────────────────────┬───────────────────┬───────────────────────┘
         │                       │                   │
         │ (5) Deploy            │ (6) IRSA Auth     │ (7) Encrypt Secrets
         │     Manifests         │                   │
         ↓                       ↓                   ↓
┌────────────────────────────────────────────────────────────────────────────┐
│                    EKS DATA PLANE (Worker Nodes)                           │
│  ┌─────────────────────────────────────────────────────────────┐          │
│  │  VPC (nam-prod) - Private Subnets                           │          │
│  │  ┌──────────────────────────────────────────────────┐       │          │
│  │  │  Node Group: 3x c7i.4xlarge (ON_DEMAND)         │       │          │
│  │  │  ├── EBS CSI Driver                             │       │          │
│  │  │  ├── VPC CNI (Pod networking)                   │       │          │
│  │  │  └── Auto Scaling (2-6 nodes)                   │       │          │
│  │  └──────────────────────────────────────────────────┘       │          │
│  └─────────────────────────────────────────────────────────────┘          │
│                              │                                             │
│                              │ (8) Pods Running                            │
│                              ↓                                             │
│  ┌──────────────────────────────────────────────────────────────────┐    │
│  │                     KUBERNETES NAMESPACES                        │    │
│  │                                                                  │    │
│  │  ┌─────────────────────────────────────────────────────────┐    │    │
│  │  │  argocd (GitOps)                                        │    │    │
│  │  │  - ArgoCD Server, Repo Server, Controller              │    │    │
│  │  │  - Watches Git repos for changes                       │    │    │
│  │  └─────────────────────────────────────────────────────────┘    │    │
│  │                                                                  │    │
│  │  ┌─────────────────────────────────────────────────────────┐    │    │
│  │  │  external-secrets                                       │    │    │
│  │  │  - External Secrets Operator (IRSA enabled)            │    │    │
│  │  │  - ClusterSecretStore (AWS Secrets Manager)            │    │    │
│  │  └──────────────┬──────────────────────────────────────────┘    │    │
│  │                 │                                               │    │
│  │  ┌─────────────────────────────────────────────────────────┐    │    │
│  │  │  monitoring                                             │    │    │
│  │  │  - Prometheus, Grafana, AlertManager                   │    │    │
│  │  └─────────────────────────────────────────────────────────┘    │    │
│  │                                                                  │    │
│  │  ┌─────────────────────────────────────────────────────────┐    │    │
│  │  │  logging                                                │    │    │
│  │  │  - Fluent Bit, Loki                                     │    │    │
│  │  └─────────────────────────────────────────────────────────┘    │    │
│  │                                                                  │    │
│  │  ┌─────────────────────────────────────────────────────────┐    │    │
│  │  │  fsai-os (Application Namespace)                        │    │    │
│  │  │  - Application Pods                                     │    │    │
│  │  │  - Secrets mounted from External Secrets               │    │    │
│  │  └──────────────┬──────────────────────────────────────────┘    │    │
│  │                 │                                               │    │
│  └─────────────────┼───────────────────────────────────────────────┘    │
└───────────────────┼────────────────────────────────────────────────────┘
                    │
                    │ (9) Access AWS Services via IRSA
                    ↓
┌────────────────────────────────────────────────────────────────────────────┐
│                          AWS SERVICES                                      │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐        │
│  │  Secrets Manager │  │  S3 Buckets      │  │  RDS Databases   │        │
│  │  (KMS Encrypted) │  │                  │  │                  │        │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘        │
│                                                                            │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐        │
│  │  ECR (Container  │  │  CloudWatch      │  │  KMS Keys        │        │
│  │  Registry)       │  │  (Logs/Metrics)  │  │                  │        │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘        │
└────────────────────────────────────────────────────────────────────────────┘
                    │
                    │ (10) External Traffic
                    ↓
┌────────────────────────────────────────────────────────────────────────────┐
│                      INGRESS / LOAD BALANCING                              │
│  ┌──────────────────────────────────────────────────────────────┐         │
│  │  AWS Application Load Balancer                               │         │
│  │  - TLS Termination                                           │         │
│  │  - Route to Ingress Controller                               │         │
│  └──────────────────────────────────────────────────────────────┘         │
└────────────────────────────────────────────────────────────────────────────┘
                    │
                    │ (11) Users Access Applications
                    ↓
┌────────────────────────────────────────────────────────────────────────────┐
│                          END USERS                                         │
│  Browser  │  Mobile App  │  API Clients                                   │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## 6. CI/CD Pipeline

### Complete CI/CD Flow

```
STEP 1: CODE COMMIT
──────────────────────────────────────────────────────────────────────────
  Developer
     │
     │ git push origin main
     ↓
  GitHub Repository (cloud-platforms)
     │
     │ Webhook triggers
     ↓
  GitHub Actions Workflow
     ├── terraform-aws-apply-overlay.yaml
     ├── terraform-aws-plan-overlay.yaml
     └── helmfile-manual.yaml


STEP 2: AUTHENTICATION & AUTHORIZATION
──────────────────────────────────────────────────────────────────────────
  GitHub Actions Runner
     │
     │ (1) OIDC Authentication
     ↓
  ┌────────────────────────────────────────────────────────────┐
  │  GitHub OIDC Provider                                      │
  │  Token: {"sub": "repo:org/cloud-platforms:ref:main"}      │
  └────────────────┬───────────────────────────────────────────┘
                   │
                   │ (2) AssumeRoleWithWebIdentity
                   ↓
  ┌────────────────────────────────────────────────────────────┐
  │  AWS STS (Security Token Service)                          │
  │  Validates token against IAM trust policy                  │
  └────────────────┬───────────────────────────────────────────┘
                   │
                   │ (3) Returns temporary credentials
                   ↓
  ┌────────────────────────────────────────────────────────────┐
  │  IAM Role: FutureSecureAI-Admin-GitHub-actions-runner      │
  │  Permissions:                                              │
  │  - EKS Full Access                                         │
  │  - S3 (Terraform state)                                    │
  │  - KMS (for encryption)                                    │
  └────────────────┬───────────────────────────────────────────┘
                   │
                   │ AWS_ACCESS_KEY_ID
                   │ AWS_SECRET_ACCESS_KEY
                   │ AWS_SESSION_TOKEN
                   ↓


STEP 3: INFRASTRUCTURE DEPLOYMENT (Terraform)
──────────────────────────────────────────────────────────────────────────
  GitHub Actions Workflow
     │
     │ (4) terraform init -backend-config
     ↓
  ┌────────────────────────────────────────────────────────────┐
  │  S3 Backend (terraf0rmstate1)                              │
  │  Key: Terraform/nam-prod/eks/terraform.tfstate            │
  │  Encrypted: true (KMS)                                     │
  └────────────────┬───────────────────────────────────────────┘
                   │
                   │ (5) terraform plan/apply
                   ↓
  ┌────────────────────────────────────────────────────────────┐
  │  AWS API                                                   │
  │  - Creates/Updates EKS cluster                            │
  │  - Provisions VPC, Subnets, Security Groups               │
  │  - Sets up IAM roles (IRSA)                               │
  └────────────────┬───────────────────────────────────────────┘
                   │
                   │ (6) Cluster ready
                   ↓


STEP 4: KUBERNETES DEPLOYMENT (Helmfile)
──────────────────────────────────────────────────────────────────────────
  GitHub Actions Workflow
     │
     │ (7) aws eks update-kubeconfig
     ↓
  ┌────────────────────────────────────────────────────────────┐
  │  EKS API Server                                            │
  │  Validates IAM credentials via EKS Access Entry           │
  └────────────────┬───────────────────────────────────────────┘
                   │
                   │ (8) kubectl authentication successful
                   ↓
  GitHub Actions Runner
     │
     │ (9) helmfile apply
     ↓
  ┌────────────────────────────────────────────────────────────┐
  │  Helmfile                                                  │
  │  - Reads helmfile/*/helmfile.yaml.gotmpl                  │
  │  - Renders templates with environment variables           │
  │  - Generates Helm charts                                  │
  └────────────────┬───────────────────────────────────────────┘
                   │
                   │ (10) helm upgrade --install
                   ↓
  ┌────────────────────────────────────────────────────────────┐
  │  Helm (Client)                                             │
  │  - Connects to Kubernetes API                             │
  │  - Sends manifests (Deployments, Services, etc.)          │
  └────────────────┬───────────────────────────────────────────┘
                   │
                   │ (11) Create/Update resources
                   ↓
  ┌────────────────────────────────────────────────────────────┐
  │  Kubernetes API Server                                     │
  │  - Validates manifests                                     │
  │  - Stores in etcd                                          │
  │  - Schedules pods on nodes                                 │
  └────────────────┬───────────────────────────────────────────┘
                   │
                   │ (12) Pods created
                   ↓


STEP 5: APPLICATION RUNTIME
──────────────────────────────────────────────────────────────────────────
  ┌────────────────────────────────────────────────────────────┐
  │  Worker Nodes (EKS Managed Node Group)                     │
  │                                                            │
  │  ┌──────────────────────────────────────────────┐         │
  │  │  Pod: external-secrets-operator              │         │
  │  │  ServiceAccount: external-secrets            │         │
  │  │  ────────────────────────────────────────────│         │
  │  │  (13) Fetches secrets from AWS               │         │
  │  │  IRSA → AssumeRole → Secrets Manager         │         │
  │  └──────────────────────────────────────────────┘         │
  │                      │                                     │
  │                      │ Creates K8s Secrets                │
  │                      ↓                                     │
  │  ┌──────────────────────────────────────────────┐         │
  │  │  Pod: application                            │         │
  │  │  Mounts secrets as volumes/env vars          │         │
  │  │  ────────────────────────────────────────────│         │
  │  │  (14) Reads DB password, API keys            │         │
  │  │  (15) Connects to AWS services (S3, RDS)     │         │
  │  └──────────────────────────────────────────────┘         │
  └────────────────────────────────────────────────────────────┘
                   │
                   │ (16) Health checks pass
                   ↓


STEP 6: MONITORING & OBSERVABILITY
──────────────────────────────────────────────────────────────────────────
  ┌────────────────────────────────────────────────────────────┐
  │  Prometheus                                                │
  │  - Scrapes metrics from pods                              │
  │  - Stores in time-series DB                               │
  └────────────────┬───────────────────────────────────────────┘
                   │
                   ↓
  ┌────────────────────────────────────────────────────────────┐
  │  Grafana                                                   │
  │  - Visualizes metrics                                      │
  │  - Dashboards for cluster health                          │
  └────────────────────────────────────────────────────────────┘

  ┌────────────────────────────────────────────────────────────┐
  │  Fluent Bit / Loki                                         │
  │  - Collects logs from all pods                            │
  │  - Centralized log storage                                │
  └────────────────────────────────────────────────────────────┘


STEP 7: GITOPS RECONCILIATION (Continuous)
──────────────────────────────────────────────────────────────────────────
  ┌────────────────────────────────────────────────────────────┐
  │  ArgoCD                                                    │
  │  - Watches Git repo every 3 minutes                       │
  │  - Detects drift between Git and cluster                  │
  │  - Auto-syncs if enabled                                  │
  └────────────────┬───────────────────────────────────────────┘
                   │
                   │ (17) Drift detected
                   ↓
  ┌────────────────────────────────────────────────────────────┐
  │  ArgoCD applies changes                                    │
  │  - Self-healing enabled                                   │
  │  - Prunes deleted resources                               │
  └────────────────────────────────────────────────────────────┘
```

### GitHub Actions Workflow Example

```yaml
name: Deploy EKS Infrastructure
on:
  push:
    branches: [main]
    paths:
      - 'terraform/aws/overlay/nam-prod/eks/**'

jobs:
  terraform-apply:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::803103365620:role/FutureSecureAI-Admin-GitHub-actions-runner
          aws-region: ap-southeast-2
          role-session-name: GitHubActions
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.7.0
      
      - name: Terraform Init
        run: |
          terraform -chdir=terraform/aws/overlay/nam-prod/eks init \
            -backend-config=backend.tf
      
      - name: Terraform Plan
        run: |
          terraform -chdir=terraform/aws/overlay/nam-prod/eks plan \
            -var-file=terraform.tfvars
      
      - name: Terraform Apply
        run: |
          terraform -chdir=terraform/aws/overlay/nam-prod/eks apply \
            -var-file=terraform.tfvars -auto-approve
```

---

## 7. Authentication Mechanisms

### Authentication Matrix

| **Process** | **Authentication Method** | **Flow** |
|-------------|---------------------------|----------|
| **GitHub Actions → AWS** | OIDC (OpenID Connect) | GitHub generates JWT token → AWS STS validates → IAM role assumed |
| **GitHub Actions → EKS** | EKS Access Entry + IAM | IAM role maps to Kubernetes user → ClusterAdminPolicy grants permissions |
| **Developer → AWS** | AWS SSO (IAM Identity Center) | SAML/SSO login → Assume role → Temporary credentials |
| **Developer → EKS** | AWS SSO + EKS Access Entry | SSO role → EKS access entry → kubectl authentication |
| **Pod → AWS Services** | IRSA (IAM Roles for Service Accounts) | ServiceAccount annotation → OIDC token → AssumeRoleWithWebIdentity |
| **External Secrets → Secrets Manager** | IRSA | Pod assumes `irsa-external-secrets-operator` role → Fetch secrets |
| **ArgoCD → Git Repo** | SSH Key / Token | Deploy key stored in Kubernetes Secret |
| **Ingress Controller → ALB** | IAM Role (via IRSA) | Creates/manages ALBs using `irsa-aws-lb-controller` role |
| **User → Application** | ALB → Ingress → Auth proxy | OAuth2/OIDC, API keys, or service mesh mTLS |

---

### Detailed Authentication Flows

#### A. GitHub Actions to AWS (OIDC)

```
GitHub Actions Workflow
  │
  │ (1) Request OIDC token from GitHub
  ↓
GitHub OIDC Provider
  │ Returns JWT token with claims:
  │ {
  │   "sub": "repo:org/cloud-platforms:ref:refs/heads/main",
  │   "aud": "sts.amazonaws.com",
  │   "iss": "https://token.actions.githubusercontent.com"
  │ }
  ↓
AWS STS AssumeRoleWithWebIdentity API
  │
  │ (2) Validates token against IAM trust policy:
  │ {
  │   "Effect": "Allow",
  │   "Principal": {
  │     "Federated": "arn:aws:iam::803103365620:oidc-provider/token.actions.githubusercontent.com"
  │   },
  │   "Action": "sts:AssumeRoleWithWebIdentity",
  │   "Condition": {
  │     "StringLike": {
  │       "token.actions.githubusercontent.com:sub": "repo:org/cloud-platforms:*"
  │     }
  │   }
  │ }
  ↓
Returns Temporary Credentials
  │ AWS_ACCESS_KEY_ID
  │ AWS_SECRET_ACCESS_KEY
  │ AWS_SESSION_TOKEN (valid for 1 hour)
  ↓
GitHub Actions uses credentials for AWS API calls
```

**IAM Trust Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::803103365620:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:org/cloud-platforms:*"
        }
      }
    }
  ]
}
```

#### B. Pod to AWS Services (IRSA)

```
Application Pod starts
  │
  │ ServiceAccount: external-secrets
  │ Annotation: eks.amazonaws.com/role-arn=arn:aws:iam::803103365620:role/irsa-external-secrets-operator
  ↓
EKS Mutating Webhook injects:
  │ - AWS_ROLE_ARN environment variable
  │ - AWS_WEB_IDENTITY_TOKEN_FILE volume mount
  │ - Token mounted at /var/run/secrets/eks.amazonaws.com/serviceaccount/token
  ↓
Pod makes AWS API call
  │
  │ AWS SDK automatically reads:
  │ - AWS_ROLE_ARN
  │ - Token from AWS_WEB_IDENTITY_TOKEN_FILE
  ↓
AWS STS AssumeRoleWithWebIdentity
  │
  │ Validates token against EKS OIDC provider:
  │ {
  │   "Effect": "Allow",
  │   "Principal": {
  │     "Federated": "arn:aws:iam::803103365620:oidc-provider/oidc.eks.ap-southeast-2.amazonaws.com/id/XXX"
  │   },
  │   "Action": "sts:AssumeRoleWithWebIdentity",
  │   "Condition": {
  │     "StringEquals": {
  │       "oidc.eks.ap-southeast-2.amazonaws.com/id/XXX:aud": "sts.amazonaws.com",
  │       "oidc.eks.ap-southeast-2.amazonaws.com/id/XXX:sub": "system:serviceaccount:external-secrets:external-secrets"
  │     }
  │   }
  │ }
  ↓
Returns Temporary Credentials
  │ Valid for 1 hour, auto-renewed by AWS SDK
  ↓
Pod accesses Secrets Manager with temporary credentials
  │
  │ GetSecretValue(SecretId="prod/database/password")
  ↓
AWS KMS decrypts secret
  │
  │ IAM policy on KMS key allows:
  │ {
  │   "Effect": "Allow",
  │   "Principal": {
  │     "AWS": "arn:aws:iam::803103365620:role/irsa-external-secrets-operator"
  │   },
  │   "Action": "kms:Decrypt"
  │ }
  ↓
Returns plaintext secret to pod
```

**ServiceAccount Configuration:**
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-secrets
  namespace: external-secrets
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::803103365620:role/irsa-external-secrets-operator
```

**IAM Role Trust Policy (IRSA):**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::803103365620:oidc-provider/oidc.eks.ap-southeast-2.amazonaws.com/id/XXX"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.ap-southeast-2.amazonaws.com/id/XXX:aud": "sts.amazonaws.com",
          "oidc.eks.ap-southeast-2.amazonaws.com/id/XXX:sub": "system:serviceaccount:external-secrets:external-secrets"
        }
      }
    }
  ]
}
```

#### C. Developer to EKS (AWS SSO)

```
Developer runs: aws sso login --profile winfo
  │
  ↓
AWS SSO Portal Opens in Browser
  │
  │ User authenticates (SAML/OIDC with IdP)
  ↓
AWS IAM Identity Center
  │
  │ Issues temporary credentials for role:
  │ AWSReservedSSO_AWSAdministratorAccess_75a94e69949591d1
  ↓
Credentials cached locally (~/.aws/sso/cache/)
  │
  ↓
Developer runs: aws eks update-kubeconfig --name nam-prod-cluster --profile winfo
  │
  │ Updates ~/.kube/config with:
  │ exec:
  │   command: aws
  │   args: ["eks", "get-token", "--cluster-name", "nam-prod-cluster", "--region", "ap-southeast-2"]
  ↓
kubectl makes API call (e.g., kubectl get pods)
  │
  │ aws eks get-token generates bearer token
  ↓
EKS API Server receives token
  │
  │ Validates against IAM (caller identity)
  ↓
EKS Access Entry maps IAM role to Kubernetes user
  │
  │ # Terraform configuration in main.tf
  │ access_entries = {
  │   "admin" = {
  │     kubernetes_groups = ["admins"]
  │     principal_arn = "arn:aws:iam::803103365620:role/aws-reserved/sso.amazonaws.com/ap-southeast-2/AWSReservedSSO_AWSAdministratorAccess_75a94e69949591d1"
  │     policy_associations = {
  │       "clusterAdmin" = {
  │         policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  │         access_scope = {
  │           type = "cluster"
  │         }
  │       }
  │     }
  │   }
  │ }
  ↓
kubectl command executes with cluster-admin permissions
```

**Kubeconfig Example:**
```yaml
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: <BASE64_CA_CERT>
    server: https://<EKS_ENDPOINT>.ap-southeast-2.eks.amazonaws.com
  name: nam-prod-cluster
contexts:
- context:
    cluster: nam-prod-cluster
    user: nam-prod-cluster
  name: nam-prod-cluster
current-context: nam-prod-cluster
users:
- name: nam-prod-cluster
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: aws
      args:
        - eks
        - get-token
        - --cluster-name
        - nam-prod-cluster
        - --region
        - ap-southeast-2
        - --profile
        - winfo
```

#### D. External Secrets Fetching Secrets

```
External Secrets Operator Pod
  │
  │ Reads ExternalSecret resource:
  │ apiVersion: external-secrets.io/v1beta1
  │ kind: ExternalSecret
  │ metadata:
  │   name: app-database-secret
  │   namespace: fsai-os
  │ spec:
  │   refreshInterval: 1h
  │   secretStoreRef:
  │     name: aws-secretsmanager
  │     kind: ClusterSecretStore
  │   target:
  │     name: database-credentials
  │   data:
  │   - secretKey: password
  │     remoteRef:
  │       key: prod/database/password
  ↓
Uses IRSA to authenticate
  │ (See IRSA flow above)
  │ ServiceAccount: external-secrets
  │ IAM Role: irsa-external-secrets-operator
  ↓
AWS Secrets Manager API call
  │ GetSecretValue(SecretId="prod/database/password")
  │
  │ IAM policy on role allows:
  │ {
  │   "Effect": "Allow",
  │   "Action": "secretsmanager:GetSecretValue",
  │   "Resource": "arn:aws:secretsmanager:ap-southeast-2:803103365620:secret:prod/*"
  │ }
  ↓
AWS KMS decrypts secret
  │
  │ Secret is encrypted with KMS key: nam-prod-eks-cluster-key
  │ IAM policy on KMS key allows:
  │ {
  │   "Effect": "Allow",
  │   "Principal": {"AWS": "arn:aws:iam::803103365620:role/irsa-external-secrets-operator"},
  │   "Action": "kms:Decrypt",
  │   "Resource": "*"
  │ }
  ↓
Returns plaintext secret value
  │ {"username": "admin", "password": "securePass123"}
  ↓
External Secrets Operator creates Kubernetes Secret
  │
  │ kubectl create secret generic database-credentials \
  │   --namespace=fsai-os \
  │   --from-literal=username=admin \
  │   --from-literal=password=securePass123
  ↓
Application Pod mounts secret
  │
  │ env:
  │   - name: DB_PASSWORD
  │     valueFrom:
  │       secretKeyRef:
  │         name: database-credentials
  │         key: password
```

**ClusterSecretStore Configuration:**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secretsmanager
spec:
  provider:
    aws:
      service: SecretsManager
      region: ap-southeast-2
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
```

---

## Key Security Principles

### 1. Least Privilege
- Each component has only the permissions it needs
- IAM policies scoped to specific resources
- Namespace-level RBAC for PowerUser access

### 2. Short-Lived Credentials
- OIDC tokens expire in 1 hour
- Force regular re-authentication
- No static access keys stored anywhere

### 3. No Static Credentials
- No long-lived access keys in code or config
- All authentication via temporary credentials
- Secrets rotated automatically

### 4. Encryption at Rest
- KMS encrypts:
  - Secrets Manager secrets
  - EBS volumes
  - EKS etcd
  - S3 Terraform state

### 5. Encryption in Transit
- TLS everywhere:
  - HTTPS for external traffic
  - Pod-to-pod encryption (if service mesh enabled)
  - AWS API calls over HTTPS

### 6. Audit Logging
- CloudTrail logs all AWS API calls
- EKS audit logs for Kubernetes API
- Application logs centralized in Loki

### 7. Multi-Factor Authentication
- AWS SSO requires MFA
- GitHub requires 2FA for org members

### 8. Network Isolation
- Private subnets for worker nodes
- Security groups restrict traffic
- Network policies control pod-to-pod traffic

---

## Related Services and Integrations

### 1. Networking
- **VPC**: nam-prod VPC with private subnets
- **Transit Gateway**: Connectivity to other VPCs
- **VPC CNI**: Native AWS networking for pods

### 2. Security & Access
- **IAM Roles**: GitHub Actions, SSO, IRSA
- **KMS**: Encryption key management
- **Secrets Manager**: Centralized secret storage

### 3. Kubernetes Applications (Helmfile)
- **ArgoCD**: GitOps continuous delivery
- **CloudNativePG**: PostgreSQL operator
- **External Secrets**: Secret synchronization
- **MinIO**: Object storage
- **Prometheus/Grafana**: Monitoring
- **Fluent Bit/Loki**: Logging
- **Vault**: Secret management

### 4. Supporting AWS Services
- **ECR**: Container registry
- **CloudWatch**: Logs and metrics
- **S3**: Terraform state, backups

---

## Appendix: Useful Commands

### EKS Access
```bash
# Login to AWS SSO
aws sso login --profile winfo

# Update kubeconfig
aws eks update-kubeconfig --name nam-prod-cluster --region ap-southeast-2 --profile winfo

# Verify access
kubectl get nodes
kubectl get pods --all-namespaces
```

### Terraform Operations
```bash
# Using Taskfile
task tf-base-plan PROVIDER=aws ACCOUNT=nam-prod TF_STACK=eks
task tf-base-apply PROVIDER=aws ACCOUNT=nam-prod TF_STACK=eks

# Direct Terraform
cd terraform/aws/overlay/nam-prod/eks
terraform init -backend-config=backend.tf
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

### Helmfile Operations
```bash
# Set environment variables
export CLOUD_PROVIDER=aws
export CLUSTER=nam-prod
export ENVIRONMENT=nam-prod
export BASE_DOMAIN=example.com

# Deploy all charts
helmfile apply

# Deploy specific release
helmfile -l name=external-secrets apply

# Diff changes
helmfile diff

# List releases
helmfile list
```

### Debug External Secrets
```bash
# Check External Secrets Operator logs
kubectl logs -n external-secrets deployment/external-secrets -f

# Check ExternalSecret status
kubectl get externalsecret -n fsai-os
kubectl describe externalsecret app-database-secret -n fsai-os

# Check ClusterSecretStore
kubectl get clustersecretstore
kubectl describe clustersecretstore aws-secretsmanager

# Check created Kubernetes secret
kubectl get secret database-credentials -n fsai-os -o yaml
```

### Verify IRSA
```bash
# Check ServiceAccount annotation
kubectl get sa external-secrets -n external-secrets -o yaml | grep eks.amazonaws.com/role-arn

# Check pod environment variables
kubectl get pod -n external-secrets -l app.kubernetes.io/name=external-secrets -o yaml | grep -A5 env

# Test AWS access from pod
kubectl run -it --rm debug --image=amazon/aws-cli --restart=Never \
  --overrides='{"spec":{"serviceAccount":"external-secrets"}}' \
  --namespace=external-secrets \
  -- sts get-caller-identity
```

---

## Troubleshooting

### Issue: kubectl authentication fails
**Solution:**
```bash
# Re-login to AWS SSO
aws sso login --profile winfo

# Update kubeconfig
aws eks update-kubeconfig --name nam-prod-cluster --region ap-southeast-2 --profile winfo

# Verify IAM identity
aws sts get-caller-identity --profile winfo
```

### Issue: External Secrets not syncing
**Solution:**
```bash
# Check operator logs
kubectl logs -n external-secrets deployment/external-secrets

# Verify IRSA is working
kubectl describe sa external-secrets -n external-secrets

# Check IAM role permissions
aws iam get-role --role-name irsa-external-secrets-operator
aws iam list-attached-role-policies --role-name irsa-external-secrets-operator
```

### Issue: Helm deployment fails
**Solution:**
```bash
# Check Helm release status
helm list -n <namespace>

# Get release history
helm history <release-name> -n <namespace>

# Rollback if needed
helm rollback <release-name> <revision> -n <namespace>

# Debug
helmfile --debug apply
```

---

## Document Information

- **Last Updated**: February 3, 2026
- **Cluster Version**: 1.32
- **Terraform Version**: ~> 1.7
- **Helm Version**: ~> 3.14
- **Helmfile Version**: ~> 0.160

---

**End of Document**
