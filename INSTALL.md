# Installing InSustain

## Prerequisites

- A Kubernetes cluster and Helm 3.
- A default StorageClass. MongoDB, PostgreSQL and MinIO each claim a volume.
- A registry token with `read:packages` for the private InSustain images,
  issued by the INTEND project.
- Prometheus Operator CRDs, unless you turn monitoring off (see below). The
  backend reads metrics from Prometheus at
  `prometheus-operated.monitoring.svc.cluster.local:9090`. Set
  `backend.prometheus.namespace` and `backend.prometheus.serviceName` to
  point at yours.

The backend's ClusterRole can read pods, services and endpoints in every
namespace. It uses this to discover workloads.

## 1. Download the chart

```bash
gh release download v2.0.<n> --repo INTEND-Project/InSustain --pattern 'insustain-*.tgz'
helm show values insustain-2.0.<n>.tgz | grep digest
```

The two `digest` values are the exact images this release runs.

## 2. Create the Secrets

The chart creates no credentials. Before you install, create these four
Secrets in the release namespace, with these exact names and keys:

| Secret | Keys | Used by |
|--------|------|---------|
| `insustain-ghcr-pull` | type `kubernetes.io/dockerconfigjson` | image pulls for backend and frontend |
| `insustain-object-store` | `rootUser`, `rootPassword` | MinIO, backend, MLflow artifact store |
| `insustain-postgres` | `username`, `password` | PostgreSQL, MLflow backend store |
| `insustain-mongodb` | `username`, `password` | MongoDB, backend |

```bash
NS=insustain
kubectl create namespace "$NS"
kubectl -n "$NS" create secret docker-registry insustain-ghcr-pull \
  --docker-server=ghcr.io --docker-username=<github-user> --docker-password=<token>
kubectl -n "$NS" create secret generic insustain-object-store \
  --from-literal=rootUser=<user> --from-literal=rootPassword=<password>
kubectl -n "$NS" create secret generic insustain-postgres \
  --from-literal=username=<user> --from-literal=password=<password>
kubectl -n "$NS" create secret generic insustain-mongodb \
  --from-literal=username=<user> --from-literal=password=<password>
```

Choose your own values. Use a MinIO `rootPassword` of at least 8 characters.

## 3. Install

```bash
helm install insustain insustain-2.0.<n>.tgz -n "$NS"
```

Useful options:

| Option | Effect |
|--------|--------|
| `--set frontend.enabled=false` | Install without the dashboard |
| `--set backend.serviceMonitor.enabled=false --set minio.metrics.serviceMonitor.enabled=false` | No Prometheus Operator objects. Use this if the CRDs are absent. |
| `--set backend.trainingScheduler.enabled=true` | Train models in the background |

## 4. Create the MLflow artifact bucket

The chart does not create MinIO buckets or users. MLflow stores artifacts in
the bucket `mlflow`, and training and prediction fail until it exists. Create
it once with the object-store credentials:

```bash
kubectl -n "$NS" port-forward svc/insustain-minio 9000:9000 &
mc alias set insustain http://localhost:9000 <user> <password>
mc mb insustain/mlflow
```

To use another name, set `mlflow.artifactRoot.s3.bucket`.

## 5. Check

```bash
kubectl -n "$NS" get pods
kubectl -n "$NS" port-forward svc/insustain-backend 8089:8089 &
curl http://localhost:8089/health
```

## Upgrade and uninstall

```bash
helm upgrade insustain insustain-2.0.<m>.tgz -n "$NS"
helm uninstall insustain -n "$NS"
```

Uninstalling keeps the Secrets. The volume claims may also remain, depending
on your StorageClass. Delete them yourself if you want the data gone.
