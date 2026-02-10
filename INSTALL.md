# Installation Guide

Complete installation instructions for InSustain.

## Prerequisites

- Kubernetes v1.30.6+
- Helm v3.17.1+
- kubectl configured with cluster access
- Docker registry credentials (from INTEND team)

## Installation Methods

**Method 1: Automated Script** (Recommended) - Quick setup with scripts  
**Method 2: Manual Installation** - Step-by-step for custom needs

---

## Method 1: Automated Installation (Recommended)

### Choose Your Script

**Option A: Kubernetes Native** (Recommended)
```bash
./scripts/scripts/setup-insustain-k8s-native.sh -p <password>
```

**Option B: K3s Direct Import**
```bash
sudo ./scripts/scripts/setup-insustain.sh
```

### Script Options

```bash
-p, --password PASSWORD    # Docker registry password
-y, --yes                  # Auto-answer yes to prompts
--enable-full-rbac         # Enable multi-namespace monitoring
-h, --help                 # Show help
```

### What the Scripts Do

1. Install Prometheus (if not present)
2. Install Kepler (if not present)
3. Configure registry access
4. Deploy InSustain components
5. Display access information

---

## Method 2: Manual Installation

### Step 1: Install Prometheus

```bash
helm install prometheus oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack \
    --version 81.4.3 \
    --namespace monitoring \
    --create-namespace \
    --wait
```

### Step 2: Install Kepler

**Option A: Via InSustain** (Recommended)
```bash
# Skip this step, enable in InSustain install
helm install insustain insustain/ --set kepler.enabled=true
```

**Option B: Separately**
```bash
helm repo add kepler https://sustainable-computing-io.github.io/kepler-helm-chart
helm install kepler kepler/kepler \
    --version 0.8.0 \
    --set serviceMonitor.enabled=true \
    --set serviceMonitor.labels.release=monitoring \
    --namespace monitoring \
    --wait
```

### Step 3: Get InSustain

**Download:**
```bash
curl -L "https://github.com/INTEND-Project/InSustain/archive/refs/tags/v1.2.0.tar.gz" -o insustain.tar.gz
tar -xzf insustain.tar.gz
cd InSustain-1.2.0
```

**Or Clone:**
```bash
git clone --branch v1.2.0 --depth 1 https://github.com/INTEND-Project/InSustain.git
cd InSustain
```

### Step 4: Install Helm Chart

**Basic:**
```bash
helm install insustain insustain/ --namespace insustain --create-namespace
```

**With Multi-Namespace Monitoring:**
```bash
helm install insustain insustain/ \
  --namespace insustain \
  --create-namespace \
  --set backend.rbac.create=true \
  --set backend.serviceAccount.create=true
```

**With Persistent Storage:**
```bash
helm install insustain insustain/ \
  --namespace insustain \
  --create-namespace \
  --set mongodb.persistence.enabled=true \
  --set postgres.persistence.enabled=true \
  --set minio.persistence.enabled=true
```

### Step 5: Verify

```bash
kubectl -n insustain get pods
kubectl -n insustain get svc
```

### Step 6: Access API

```bash
kubectl -n insustain port-forward svc/insustain-backend 8089:8089
# Open: http://localhost:8089/docs
```

---

## Configuration Options

### Multi-Namespace Monitoring

Enable backend to discover pods across all namespaces:
```bash
--set backend.rbac.create=true \
--set backend.serviceAccount.create=true
```

See [RBAC.md](RBAC.md) for details.

### Custom Prometheus

```bash
--set prometheus.namespace=<namespace> \
--set prometheus.serviceName=<service-name>
```

### Custom Registry

```bash
--set global.image.repository=<registry-url>
```

### Persistent Storage

```bash
--set mongodb.persistence.enabled=true \
--set mongodb.persistence.storageClass=<class> \
--set postgres.persistence.enabled=true \
--set minio.persistence.enabled=true
```

---

---

## Manual Image Import (Optional)

For pre-loading images before Helm deployment.

### Scenario 1: Same Machine (Docker + Kubernetes)

```bash
./scripts/scripts/import-images.sh <password>
```

### Scenario 2: Same Machine (No Docker)

Use skopeo instead:
```bash
# Install skopeo
sudo apt install skopeo

# Download and import
./scripts/scripts/import-images.sh --use-skopeo <password>
```

### Scenario 3: Separate Machines

**On machine with Docker:**
```bash
./scripts/scripts/download-images.sh <password>
```

**Transfer `insustain-images/` directory to Kubernetes node**

**On Kubernetes node:**
```bash
./scripts/scripts/load-images.sh
```

### Deploy

After importing images:
```bash
helm install insustain insustain/ --set backend.image.pullPolicy=IfNotPresent
```

---

---

## Troubleshooting

**Test registry access first:**
```bash
./scripts/scripts/test-registry-access.sh <password>
```

This diagnostic script checks:
- Network connectivity to registry
- Certificate configuration
- Authentication
- Runtime detection and configuration

**Pods not starting:**
```bash
kubectl -n insustain describe pod <pod-name>
kubectl -n insustain logs <pod-name>
```

**Image pull errors:**
- Verify credentials with INTEND team
- Check certificate is installed correctly for your runtime
- Ensure registry is accessible: `ping 89.133.95.6`
- Test manual pull with your runtime's CLI

**Certificate/TLS errors when pulling images:**

For K3s:
```bash
# Check registries config
cat /etc/rancher/k3s/registries.yaml

# Verify certificate path is correct
ls -la $(pwd)/certs/docker_ca.crt

# Restart K3s after config changes
sudo systemctl restart k3s
```

For containerd:
```bash
# Check certificate directory
ls -la /etc/containerd/certs.d/89.133.95.6:5001/

# Verify certificate is readable
sudo cat /etc/containerd/certs.d/89.133.95.6:5001/ca.crt

# Restart containerd
sudo systemctl restart containerd
```

For CRI-O:
```bash
# Check registries config
cat /etc/containers/registries.conf

# Verify certificate path
cat $(pwd)/certs/docker_ca.crt

# Restart CRI-O
sudo systemctl restart crio
```

**Authentication errors:**
- Double-check username is "intend"
- Verify password with INTEND team
- Ensure no extra spaces in credentials
- Try escaping special characters in password

**No metrics:**
- Wait 5-10 minutes for data collection
- Check Kepler: `kubectl -n monitoring get pods -l app.kubernetes.io/name=kepler`
- Check Prometheus: `kubectl -n monitoring get svc`

---

## Uninstallation

```bash
helm uninstall insustain -n insustain
kubectl delete namespace insustain
```

---

## Next Steps

- [API Guide](API_GUIDE.md) - API reference
- [Configuration](CONFIGURATION.md) - Advanced options
- [RBAC](RBAC.md) - Security and permissions
