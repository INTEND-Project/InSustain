# InSustain Quick Start

Get InSustain running in 5 minutes.

## Prerequisites

```bash
# Verify tools
kubectl version --short
helm version --short
```

## Installation

### 1. Install Prometheus & Kepler

```bash
# Prometheus
helm install prometheus oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack \
    --version 81.4.3 \
    --namespace monitoring \
    --create-namespace \
    --wait

# Kepler
helm repo add kepler https://sustainable-computing-io.github.io/kepler-helm-chart
helm install kepler kepler/kepler \
    --version 0.8.0 \
    --set serviceMonitor.enabled=true \
    --set serviceMonitor.labels.release=monitoring \
    --namespace monitoring \
    --wait
```

### 2. Get InSustain

Contact INTEND team for registry credentials.

**Option A: Download**
```bash
curl -L "https://github.com/INTEND-Project/InSustain/archive/refs/tags/v1.2.0.tar.gz" -o insustain.tar.gz
tar -xzf insustain.tar.gz
cd InSustain-1.2.0
```

**Option B: Clone**
```bash
git clone --branch v1.2.0 --depth 1 https://github.com/INTEND-Project/InSustain.git
cd InSustain
```

### 3. Run Setup Script

```bash
./scripts/scripts/setup-insustain-k8s-native.sh -p <password> -y
```

The script installs all components automatically.

## Verify

```bash
# Check pods
kubectl -n insustain get pods

# Access API
kubectl -n insustain port-forward svc/insustain-backend 8089:8089
# Open: http://localhost:8089/docs
```

## First API Call

Register an application:
```bash
curl -X POST http://localhost:8089/nnwdaf-analyticsinfo/v1/application \
  -H "Content-Type: application/json" \
  -d '{
    "application-id": "test-app",
    "name": "Test Application"
  }'
```

Query metrics (after a few minutes):
```bash
curl "http://localhost:8089/nnwdaf-analyticsinfo/v1/analytics?\
appIds=test-app&\
metricType=CPU_JOULES&\
offsetPeriod=-60"
```

## Troubleshooting

**Pods not starting?**
```bash
kubectl -n insustain describe pod <pod-name>
kubectl -n insustain logs <pod-name>
```

**No metrics?**
- Wait 5-10 minutes for data collection
- Check Kepler: `kubectl -n monitoring get pods -l app.kubernetes.io/name=kepler`

## Next Steps

- [Installation Guide](INSTALL.md) - Detailed setup options
- [API Guide](API_GUIDE.md) - Complete API reference
- [Configuration](CONFIGURATION.md) - Advanced configuration
