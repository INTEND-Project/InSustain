# RBAC Configuration Guide

Complete guide to Role-Based Access Control (RBAC) configuration for InSustain.

## Overview

InSustain's backend component can optionally be granted cluster-wide permissions to discover and monitor applications across all namespaces. This is controlled via RBAC (Role-Based Access Control) settings.

## Default Configuration

By default, RBAC is **disabled**:

```yaml
backend:
  rbac:
    create: false
  serviceAccount:
    create: false
```

In this mode:
- Backend runs with the default Kubernetes service account
- Can only access resources in the `insustain` namespace
- Suitable for single-namespace deployments or testing

## Enabling Cluster-Wide RBAC

### Why Enable RBAC?

Enable RBAC when you need to:
- Monitor applications deployed across multiple namespaces
- Get cluster-wide energy consumption visibility
- Use InSustain as a central monitoring solution
- Register and track applications in different namespaces

### What Gets Created

When you enable RBAC (`rbac.create=true`), InSustain creates:

1. **ServiceAccount**: `insustain-backend` in the `insustain` namespace
2. **ClusterRole**: `insustain-backend` with read-only permissions
3. **ClusterRoleBinding**: Binds the ServiceAccount to the ClusterRole

### Permissions Granted

The ClusterRole grants read-only access to:

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
    - get      # Read individual resources
    - list     # List all resources
    - watch    # Watch for changes
```

**What this means:**
- Backend can **read** pods, services, and endpoints in all namespaces
- Backend **cannot** create, update, or delete any resources
- Backend **cannot** access secrets, configmaps, or other sensitive resources
- Follows the principle of least privilege

## Installation Methods

### Method 1: Using Automated Script (Recommended)

```bash
./scripts/scripts/setup-insustain-k8s-native.sh \
    -p <password> \
    --enable-full-rbac
```

The script will:
- Create the ServiceAccount
- Create the ClusterRole with appropriate permissions
- Create the ClusterRoleBinding
- Deploy InSustain with RBAC enabled

### Method 2: Using Helm Directly

```bash
helm install insustain insustain/ \
    --namespace insustain \
    --create-namespace \
    --set backend.rbac.create=true \
    --set backend.serviceAccount.create=true
```

### Method 3: Using Values File

Create `rbac-values.yaml`:
```yaml
backend:
  rbac:
    create: true
  serviceAccount:
    create: true
```

Install:
```bash
helm install insustain insustain/ \
    --namespace insustain \
    --values rbac-values.yaml
```

## Verification

### Check RBAC Resources

```bash
# Check if ServiceAccount exists
kubectl get serviceaccount insustain-backend -n insustain

# Check ClusterRole
kubectl get clusterrole insustain-backend

# Check ClusterRoleBinding
kubectl get clusterrolebinding insustain-backend

# View detailed ClusterRole permissions
kubectl describe clusterrole insustain-backend
```

Expected output for ClusterRole:
```
Name:         insustain-backend
Labels:       <none>
Annotations:  <none>
PolicyRule:
  Resources  Non-Resource URLs  Resource Names  Verbs
  ---------  -----------------  --------------  -----
  endpoints  []                 []              [get list watch]
  pods       []                 []              [get list watch]
  services   []                 []              [get list watch]
```

### Test Permissions

```bash
# Test if backend can list pods in default namespace (should succeed)
kubectl auth can-i list pods \
    --as=system:serviceaccount:insustain:insustain-backend \
    -n default

# Test if backend can list services (should succeed)
kubectl auth can-i list services \
    --as=system:serviceaccount:insustain:insustain-backend \
    -n default

# Test if backend can delete pods (should fail)
kubectl auth can-i delete pods \
    --as=system:serviceaccount:insustain:insustain-backend \
    -n default

# Test if backend can read secrets (should fail)
kubectl auth can-i get secrets \
    --as=system:serviceaccount:insustain:insustain-backend \
    -n default
```

### Check Backend Pod

Verify the backend pod is using the correct ServiceAccount:

```bash
kubectl get pod -n insustain -l app.kubernetes.io/name=backend -o yaml | grep serviceAccount
```

Expected output:
```yaml
serviceAccount: insustain-backend
serviceAccountName: insustain-backend
```

## Use Cases

### Single Namespace Deployment

**Scenario:** All applications run in the `insustain` namespace

**Configuration:**
```yaml
backend:
  rbac:
    create: false  # Default service account is sufficient
```

**Pros:**
- Minimal permissions
- Simpler security model
- Faster to set up

**Cons:**
- Cannot monitor apps in other namespaces

### Multi-Namespace Deployment

**Scenario:** Applications run across multiple namespaces (e.g., `production`, `staging`, `development`)

**Configuration:**
```yaml
backend:
  rbac:
    create: true
  serviceAccount:
    create: true
```

**Pros:**
- Cluster-wide visibility
- Central monitoring solution
- Can track all applications

**Cons:**
- Requires cluster-wide permissions
- More complex security model

### Restricted Environment

**Scenario:** Security policies restrict cluster-wide permissions

**Options:**
1. Deploy InSustain per namespace
2. Use namespace-scoped Roles instead of ClusterRole (requires chart modification)
3. Request exception from security team with justification

## Security Best Practices

### 1. Principle of Least Privilege

- Only enable RBAC if you need multi-namespace monitoring
- Review permissions regularly
- Document why RBAC is enabled

### 2. Audit and Monitoring

Monitor ServiceAccount usage:
```bash
# Check recent API calls by the ServiceAccount
kubectl get events --all-namespaces --field-selector involvedObject.name=insustain-backend
```

### 3. Network Policies

Combine RBAC with NetworkPolicies to restrict network access:
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: insustain-backend
  namespace: insustain
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: backend
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 443  # Kubernetes API
```

### 4. Regular Reviews

Periodically review:
- Who has access to modify RBAC resources
- Whether cluster-wide permissions are still needed
- Audit logs for unusual access patterns

## Troubleshooting

### Backend Cannot Access Pods in Other Namespaces

**Symptoms:**
- API returns empty results for applications in other namespaces
- Logs show permission denied errors

**Solution:**
```bash
# Check if RBAC is enabled
helm get values insustain -n insustain | grep rbac

# If false, upgrade with RBAC enabled
helm upgrade insustain insustain/ \
    --namespace insustain \
    --set backend.rbac.create=true \
    --set backend.serviceAccount.create=true \
    --reuse-values
```

### ClusterRole Already Exists

**Symptoms:**
- Helm install fails with "ClusterRole already exists"

**Solution:**
```bash
# Check existing ClusterRole
kubectl get clusterrole insustain-backend

# If from old installation, delete it
kubectl delete clusterrole insustain-backend
kubectl delete clusterrolebinding insustain-backend

# Reinstall
helm install insustain insustain/ \
    --namespace insustain \
    --set backend.rbac.create=true
```

### Permission Denied Errors

**Symptoms:**
- Backend logs show "forbidden" or "permission denied"

**Solution:**
```bash
# Verify ClusterRoleBinding
kubectl describe clusterrolebinding insustain-backend

# Check if ServiceAccount is correct
kubectl get pod -n insustain -l app.kubernetes.io/name=backend \
    -o jsonpath='{.items[0].spec.serviceAccountName}'

# Should output: insustain-backend
```

## Upgrading RBAC Configuration

### Enable RBAC on Existing Installation

```bash
helm upgrade insustain insustain/ \
    --namespace insustain \
    --set backend.rbac.create=true \
    --set backend.serviceAccount.create=true \
    --reuse-values
```

### Disable RBAC

```bash
# First, delete RBAC resources
kubectl delete clusterrolebinding insustain-backend
kubectl delete clusterrole insustain-backend
kubectl delete serviceaccount insustain-backend -n insustain

# Then upgrade
helm upgrade insustain insustain/ \
    --namespace insustain \
    --set backend.rbac.create=false \
    --set backend.serviceAccount.create=false \
    --reuse-values
```

## Compliance and Auditing

### Generating RBAC Report

```bash
# List all permissions for the ServiceAccount
kubectl describe clusterrole insustain-backend

# Export for documentation
kubectl get clusterrole insustain-backend -o yaml > insustain-rbac-report.yaml
```

### Audit Log Queries

If audit logging is enabled in your cluster:

```bash
# Find all API calls by InSustain backend
kubectl logs -n kube-system kube-apiserver-* | \
    grep "system:serviceaccount:insustain:insustain-backend"
```

## Reference

- **Kubernetes RBAC Documentation**: https://kubernetes.io/docs/reference/access-authn-authz/rbac/
- **ServiceAccount Documentation**: https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/
- **Security Best Practices**: https://kubernetes.io/docs/concepts/security/rbac-good-practices/

## Summary

| Configuration | Use Case | Permissions | Security Level |
|--------------|----------|-------------|----------------|
| `rbac.create=false` | Single namespace | Namespace-scoped | High |
| `rbac.create=true` | Multi-namespace | Cluster-wide read | Medium |

Choose the configuration that matches your deployment needs and security requirements.
