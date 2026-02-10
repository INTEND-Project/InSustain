# Configuration Guide

Complete configuration reference for InSustain Helm chart.

## Chart Information

- **Chart Name**: insustain
- **Chart Version**: 0.1.0
- **App Version**: 1.16.0
- **Type**: Application chart

## Component Overview

InSustain consists of the following components:

### Core Components (All Enabled by Default)

| Component | Purpose | Default Port(s) | Storage |
|-----------|---------|-----------------|---------|
| **backend** | REST API service | 8089, 8888, 8887 | None |
| **mongodb** | Application metadata | 27017 | Ephemeral |
| **mlflow** | ML model platform | 5000 | Via MinIO/PostgreSQL |
| **postgres** | MLflow metadata DB | 5432 | Ephemeral |
| **minio** | MLflow artifact storage | 9000, 9001 | Ephemeral |

### Energy Metrics Component

| Component | Purpose | Installation Options |
|-----------|---------|---------------------|
| **kepler** | Node-level energy metrics | Via InSustain chart (recommended) or separately |

Kepler v0.5.13 is included as a Helm dependency and can be installed with InSustain by setting `kepler.enabled=true`, or you can install it separately in your cluster.

## Global Configuration

### Image Registry

Configure the Docker registry for all images:

```yaml
global:
  image:
    repository: 89.133.95.6:5001  # Your private registry
```

### Monitoring Labels

Configure Prometheus ServiceMonitor labels:

```yaml
global:
  monitoring:
    labels:
      release: monitoring  # Must match your Prometheus release name
```

### Shared Credentials

Credentials shared across components:

```yaml
global:
  minio:
    rootUser: "rootUser"
    rootPassword: "rootpass123"
  
  postgresql:
    user: "user"
    password: "password"
    database: "appdb"
```

## Backend Configuration

### Basic Settings

```yaml
backend:
  enabled: true
  
  image:
    tag: latest
    pullPolicy: Always  # or IfNotPresent for imported images
  
  service:
    backend:
      port: 8089  # Main API endpoint
    jupyter:
      port: 8888  # Jupyter notebook interface
    pm:
      port: 8887  # Prometheus metrics endpoint
```

### RBAC Configuration

Enable cluster-wide permissions for pod discovery:

```yaml
backend:
  rbac:
    create: true  # Creates ClusterRole and ClusterRoleBinding
  
  serviceAccount:
    create: true  # Creates ServiceAccount for backend
```

**When to enable:**
- You want backend to discover pods across all namespaces
- You need application monitoring beyond the insustain namespace

**Security note:** This grants cluster-wide read permissions for pods.

### MongoDB Connection

```yaml
backend:
  mongo:
    db: monitoring  # Database name in MongoDB
```

### Prometheus Metrics

```yaml
backend:
  serviceMonitor:
    enabled: true  # Enable Prometheus scraping
    portName: pm   # Port name for metrics (8887)
```



## Kepler Integration

InSustain requires Kepler for energy metrics collection. You have two options:

### Option 1: Install via InSustain Chart (Recommended)

Kepler v0.5.13 is included as a dependency and can be installed automatically:

```bash
helm install insustain insustain/ \
    --namespace insustain \
    --set kepler.enabled=true \
    --set kepler.serviceMonitor.enabled=true \
    --set kepler.serviceMonitor.labels.release=monitoring
```

The automated installation scripts will detect if Kepler is already installed and offer to install it via InSustain if not present.

### Option 2: Install Separately

If you prefer to manage Kepler independently:

```bash
helm repo add kepler https://sustainable-computing-io.github.io/kepler-helm-chart
helm install kepler kepler/kepler \
    --version 0.8.0 \
    --set serviceMonitor.enabled=true \
    --set serviceMonitor.labels.release=monitoring \
    --namespace monitoring
```

Then install InSustain with Kepler disabled:
```bash
helm install insustain insustain/ \
    --namespace insustain \
    --set kepler.enabled=false
```

InSustain will automatically discover and use Kepler metrics from Prometheus regardless of installation method.

## RBAC Configuration

The backend component can optionally be granted cluster-wide permissions to discover and monitor pods across all namespaces.

### Default Behavior (No RBAC)

By default, RBAC is disabled:

```yaml
backend:
  rbac:
    create: false
  serviceAccount:
    create: false
```

In this mode:
- Backend runs with default service account
- Can only access pods in the `insustain` namespace
- Suitable for single-namespace deployments

### Enabling Cluster-Wide RBAC

To monitor applications across all namespaces:

```yaml
backend:
  rbac:
    create: true
  serviceAccount:
    create: true
```

This creates:
- **ServiceAccount**: `insustain-backend` in the `insustain` namespace
- **ClusterRole**: Grants read-only access to pods cluster-wide
- **ClusterRoleBinding**: Binds the ServiceAccount to the ClusterRole

**Permissions granted:**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: insustain-backend
rules:
- apiGroups: [""]
  resources:
    - services
    - endpoints
    - pods
  verbs:
    - get
    - list
    - watch
```

The backend can read services, endpoints, and pods across all namespaces but cannot modify them.

### Installation with RBAC

**Using Helm:**
```bash
helm install insustain insustain/ \
    --namespace insustain \
    --set backend.rbac.create=true \
    --set backend.serviceAccount.create=true
```

**Using automated script:**
```bash
./scripts/scripts/setup-insustain-k8s-native.sh \
    -p <password> \
    --enable-full-rbac
```

### When to Enable RBAC

**Enable RBAC when:**
- You want to monitor applications across multiple namespaces
- You need cluster-wide energy consumption visibility
- You're deploying InSustain as a central monitoring solution

**Keep RBAC disabled when:**
- You only monitor applications in the `insustain` namespace
- You want to minimize cluster-wide permissions
- You're testing or developing locally

### Security Considerations

- RBAC grants **read-only** access to pods, services, and endpoints
- No write or delete permissions are granted
- Access is limited to core API resources only
- ServiceAccount is namespace-scoped but ClusterRole is cluster-wide
- Follows principle of least privilege for monitoring use case

### Verifying RBAC

Check if RBAC is enabled:
```bash
# Check ServiceAccount
kubectl get serviceaccount insustain-backend -n insustain

# Check ClusterRole
kubectl get clusterrole insustain-backend

# Check ClusterRoleBinding
kubectl get clusterrolebinding insustain-backend

# View ClusterRole permissions
kubectl describe clusterrole insustain-backend

# Test permissions
kubectl auth can-i list pods --as=system:serviceaccount:insustain:insustain-backend -n default
kubectl auth can-i list services --as=system:serviceaccount:insustain:insustain-backend -n default
kubectl auth can-i delete pods --as=system:serviceaccount:insustain:insustain-backend -n default
# Should return: no
```

## MongoDB Configuration

```yaml
mongodb:
  enabled: true
  
  image:
    repository: docker.io
    prefix: mongo
    tag: "8.0"
  
  service:
    type: ClusterIP
    port: 27017
  
  persistence:
    enabled: false  # Set to true for production
    storageClass: ""  # Specify your storage class
    size: 10Gi
```

## PostgreSQL Configuration

```yaml
postgres:
  enabled: true
  
  postgresUser: "user"
  postgresPassword: "password"
  postgresDb: "appdb"
  
  persistence:
    enabled: false  # Set to true for production
    storageClass: ""
    size: 5Gi
```

## MLflow Configuration

```yaml
mlflow:
  image:
    tag: 3.5.1
  
  log:
    enabled: true
    level: debug
  
  backendStore:
    databaseConnectionCheck: true
    postgres:
      enabled: true
      host: "postgres"
      port: 5432
      database: "appdb"
      user: "user"
      password: "password"
  
  artifactRoot:
    s3:
      enabled: true
      bucket: "mlflow"
      awsAccessKeyId: "rootUser"
      awsSecretAccessKey: "rootpass123"
  
  extraEnvVars:
    MLFLOW_S3_ENDPOINT_URL: "http://minio.insustain.svc.cluster.local:9000"
    MLFLOW_S3_IGNORE_TLS: "true"
    MLFLOW_SERVER_ALLOWED_HOSTS: "*"
  
  service:
    type: ClusterIP
    port: 5000
  
  auth:
    enabled: false
```

## MinIO Configuration

```yaml
minio:
  enabled: true
  
  resources:
    requests:
      memory: 1024Mi
  
  replicas: 1
  mode: standalone
  
  rootUser: "rootUser"
  rootPassword: "rootpass123"
  
  persistence:
    enabled: false  # Set to true for production
    storageClass: ""
    size: 20Gi
```

## Production Configuration Example

For production deployments with persistent storage:

```yaml
global:
  image:
    repository: 89.133.95.6:5001
  monitoring:
    labels:
      release: prometheus

backend:
  enabled: true
  rbac:
    create: true
  serviceAccount:
    create: true
  image:
    pullPolicy: IfNotPresent
  serviceMonitor:
    enabled: true

mongodb:
  enabled: true
  persistence:
    enabled: true
    storageClass: "fast-ssd"
    size: 20Gi

postgres:
  enabled: true
  persistence:
    enabled: true
    storageClass: "fast-ssd"
    size: 10Gi

minio:
  enabled: true
  persistence:
    enabled: true
    storageClass: "standard"
    size: 50Gi
  resources:
    requests:
      memory: 2048Mi
      cpu: 1000m

mlflow:
  enabled: true
  log:
    level: info
```

## Minimal Configuration Example

For testing or development with minimal resources (uses default ephemeral storage):

```yaml
backend:
  enabled: true
  image:
    pullPolicy: IfNotPresent

mongodb:
  enabled: true
  persistence:
    enabled: false

postgres:
  enabled: true
  persistence:
    enabled: false

minio:
  enabled: true
  persistence:
    enabled: false
  resources:
    requests:
      memory: 512Mi

mlflow:
  enabled: true
```

## Image Pull Configuration

### Using imagePullSecrets (Recommended)

```yaml
backend:
  imagePullSecrets:
    - name: insustain-registry-secret
```

Create the secret:
```bash
kubectl create secret docker-registry insustain-registry-secret \
  --docker-server=89.133.95.6:5001 \
  --docker-username=intend \
  --docker-password=<password> \
  --namespace insustain
```

### Using Pre-imported Images

For air-gapped or restricted environments, import images directly to your container runtime:

**Automated (All Runtimes):**
```bash
./scripts/scripts/import-images.sh -p <password>
```

Pulls images directly to your runtime (K3s, containerd, or CRI-O). No Docker required!

**Manual Pull:**
```bash
# K3s
sudo k3s ctr images pull --user intend:<password> 89.133.95.6:5001/insustain/backend:latest

# containerd
sudo ctr -n k8s.io images pull --user intend:<password> 89.133.95.6:5001/insustain/backend:latest

# CRI-O
sudo crictl pull --creds intend:<password> 89.133.95.6:5001/insustain/backend:latest
```

Then configure Helm to use local images:
```yaml
backend:
  image:
    pullPolicy: IfNotPresent  # or Never
```

## Service Types

### ClusterIP (Default)

Services accessible only within the cluster:

```yaml
backend:
  service:
    type: ClusterIP
```

Access via port-forward:
```bash
kubectl port-forward -n insustain svc/insustain-backend 8089:8089
```

### NodePort

Services accessible via node IP:

```yaml
backend:
  service:
    type: NodePort
    nodePort: 30089
```

### LoadBalancer

Services with external IP (requires cloud provider):

```yaml
backend:
  service:
    type: LoadBalancer
```

## Helm Installation Examples

### Minimal Installation

```bash
helm install insustain insustain/ \
  --namespace insustain \
  --create-namespace
```

### With Custom Registry

```bash
helm install insustain insustain/ \
  --namespace insustain \
  --set global.image.repository=your-registry.com \
  --set backend.image.pullPolicy=IfNotPresent
```

### With Full RBAC

```bash
helm install insustain insustain/ \
  --namespace insustain \
  --set backend.rbac.create=true \
  --set backend.serviceAccount.create=true
```

### With Persistent Storage

```bash
helm install insustain insustain/ \
  --namespace insustain \
  --set mongodb.persistence.enabled=true \
  --set mongodb.persistence.storageClass=fast-ssd \
  --set postgres.persistence.enabled=true \
  --set minio.persistence.enabled=true
```

### Using Values File

Create `my-values.yaml`:
```yaml
global:
  image:
    repository: 89.133.95.6:5001

backend:
  enabled: true
  rbac:
    create: true

kepler:
  enabled: true

mongodb:
  persistence:
    enabled: true
    storageClass: fast-ssd
```

Install:
```bash
helm install insustain insustain/ \
  --namespace insustain \
  --values my-values.yaml
```

## Upgrading Configuration

```bash
# Upgrade with new values
helm upgrade insustain insustain/ \
  --namespace insustain \
  --set kepler.enabled=true \
  --reuse-values

# Upgrade with values file
helm upgrade insustain insustain/ \
  --namespace insustain \
  --values my-values.yaml
```

## Viewing Current Configuration

```bash
# Get all values
helm get values insustain -n insustain

# Get all values including defaults
helm get values insustain -n insustain --all
```

## Configuration Validation

```bash
# Lint the chart
helm lint insustain/

# Dry-run installation
helm install insustain insustain/ \
  --namespace insustain \
  --dry-run \
  --debug
```

## Common Configuration Patterns

### Development Environment

- Ephemeral storage
- Image pull policy: Always
- Debug logging enabled
- All optional components disabled

### Production Environment

- Persistent storage enabled
- Image pull policy: IfNotPresent
- Info/Warning logging
- RBAC enabled
- Resource limits set
- Kepler enabled for metrics

### Testing Environment

- Ephemeral storage
- Optional simulators enabled
- Load testing tools enabled
- Debug logging

## Troubleshooting Configuration

### Check Applied Configuration

```bash
kubectl get configmap -n insustain
kubectl describe configmap <name> -n insustain
```

### Check Secrets

```bash
kubectl get secrets -n insustain
kubectl describe secret <name> -n insustain
```

### Verify Service Configuration

```bash
kubectl get svc -n insustain
kubectl describe svc insustain-backend -n insustain
```

### Check ServiceMonitor

```bash
kubectl get servicemonitor -n insustain
kubectl describe servicemonitor insustain-backend -n insustain
```

## Reference

- Full values reference: [insustain/values.yaml](insustain/values.yaml)
- Chart metadata: [insustain/Chart.yaml](insustain/Chart.yaml)
- Installation guide: [INSTALL.md](INSTALL.md)
