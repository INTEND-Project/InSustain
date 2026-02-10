# InSustain

Energy observability for Kubernetes workloads.

## Overview

InSustain provides energy metrics and predictions for cloud-native applications:
- Real-time energy consumption monitoring
- Application registration and tracking
- Historical analytics with flexible time ranges
- ML-based energy prediction

## Components

- **Backend** - REST API (port 8089)
- **MongoDB** - Application metadata
- **MLflow** - ML model platform
- **PostgreSQL** - MLflow metadata
- **MinIO** - MLflow artifacts
- **Kepler** - Energy metrics collector

## Prerequisites

- Kubernetes v1.30.6+
- Helm v3.17.1+
- Prometheus Operator v0.80+
- Kepler v0.8+

## Quick Start

### 1. Install Prometheus & Kepler

```bash
helm install prometheus oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack \
    --version 81.4.3 \
    --namespace monitoring \
    --create-namespace \
    --wait

helm repo add kepler https://sustainable-computing-io.github.io/kepler-helm-chart
helm install kepler kepler/kepler \
    --version 0.8.0 \
    --set serviceMonitor.enabled=true \
    --set serviceMonitor.labels.release=monitoring \
    --namespace monitoring \
    --wait
```

### 2. Install InSustain

**Option A: Download**
```bash
curl -L "https://github.com/INTEND-Project/InSustain/archive/refs/tags/v1.2.0.tar.gz" -o insustain.tar.gz
tar -xzf insustain.tar.gz
cd InSustain-1.2.0
./scripts/scripts/setup-insustain-k8s-native.sh -p <password>
```

**Option B: Clone**
```bash
git clone --branch v1.2.0 --depth 1 https://github.com/INTEND-Project/InSustain.git
cd InSustain
./scripts/scripts/setup-insustain-k8s-native.sh -p <password>
```

Contact INTEND team for registry credentials.

### 3. Access API

```bash
kubectl -n insustain port-forward svc/insustain-backend 8089:8089
# Open: http://localhost:8089/docs
```

## Configuration

### Basic Installation
```bash
helm install insustain insustain/ --namespace insustain
```

### With Multi-Namespace Monitoring
```bash
helm install insustain insustain/ \
  --namespace insustain \
  --set backend.rbac.create=true
```

This allows backend to discover pods across all namespaces.

### Storage Configuration

For production, enable persistent storage:
```bash
helm install insustain insustain/ \
  --namespace insustain \
  --set mongodb.persistence.enabled=true \
  --set postgres.persistence.enabled=true \
  --set minio.persistence.enabled=true
```

See [CONFIGURATION.md](CONFIGURATION.md) for all options.

## Image Management

InSustain uses a private registry. Two options:

### Option 1: imagePullSecrets (Recommended)

Kubernetes pulls images automatically:
```bash
./scripts/scripts/setup-insustain-k8s-native.sh -p <password>
```

### Option 2: Pre-load Images

Download and import before deployment:

**Same machine (Docker + Kubernetes):**
```bash
./scripts/scripts/import-images.sh <password>
```

**Same machine (no Docker, use skopeo):**
```bash
./scripts/scripts/import-images.sh --use-skopeo <password>
```

**Separate machines:**
```bash
# On machine with Docker:
./scripts/scripts/download-images.sh <password>

# Transfer insustain-images/ directory to Kubernetes node

# On Kubernetes node:
./scripts/scripts/load-images.sh
```

Then deploy:
```bash
helm install insustain insustain/ --set backend.image.pullPolicy=IfNotPresent
```

## Usage

### Register Application
```bash
curl -X POST http://localhost:8089/nnwdaf-analyticsinfo/v1/application \
  -H "Content-Type: application/json" \
  -d '{"application-id": "my-app", "name": "My App"}'
```

### Query Metrics
```bash
curl "http://localhost:8089/nnwdaf-analyticsinfo/v1/analytics?\
appIds=my-app&metricType=CPU_JOULES&offsetPeriod=-60"
```

See [API_GUIDE.md](API_GUIDE.md) for complete API reference.

## Documentation

- [QUICKSTART.md](QUICKSTART.md) - 5-minute setup
- [INSTALL.md](INSTALL.md) - Detailed installation
- [API_GUIDE.md](API_GUIDE.md) - API reference
- [CONFIGURATION.md](CONFIGURATION.md) - Configuration options
- [RBAC.md](RBAC.md) - Security and permissions

## Architecture

![Architecture](arch.png)

InSustain integrates with Kepler for energy metrics, Prometheus for storage, and provides REST API for queries and predictions.

## Support

Contact INTEND project team for:
- Docker registry credentials
- Installation assistance
- Technical support

## License

Proprietary - INTEND Project
