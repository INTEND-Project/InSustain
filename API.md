# InSustain API

The backend serves HTTP on port 8089 of the `insustain-backend` Service. Of
the Service's ports, only 8089 serves the API.

```bash
kubectl -n insustain port-forward svc/insustain-backend 8089:8089
```

The running backend describes itself at `/docs` (interactive) and
`/openapi.json`. Use those for request and response schemas.

**The API has no authentication.** Keep the Service `ClusterIP`. If you
expose it, put an authenticating proxy or Ingress in front of it.

## Endpoints

| Area | Path | Purpose |
|------|------|---------|
| Health | `GET /health` | Liveness and dependency status |
| Applications | `GET, POST /application`; `GET, DELETE /application/{id}` | Register the workloads InSustain observes |
| Analytics | `GET /analytics` | On-demand energy metrics for a microservice |
| | `GET /analytics/capabilities` | Metrics this cluster can serve |
| Prediction | `GET /predict`; `POST /predict/energy` | Predicted energy for a configuration |
| Comparison | `POST /energy/compare` | Compare a workload's resource cost across two or more arms |
| ML pipeline | `POST /api/ml/collect`, `/api/ml/train`, `/api/ml/train-models`, `/api/ml/predict`, `/api/ml/energy-study/run` | Collect data, train and query models |
| | `GET /api/ml/model-status`, `/api/ml/models`, `/api/ml/scheduler/status`, `/api/ml/dataset/{collection_id}` | Model, scheduler and dataset status |
| Intents (TMF921) | `POST, GET /tmf-api/intentManagement/v5/intent` | Create and list intents |
| | `GET, PATCH, DELETE /tmf-api/intentManagement/v5/intent/{intent_id}` | Read, update and remove an intent |
| | `GET, POST .../intent/{intent_id}/intentReport` | List and generate intent reports |
| | `POST, GET .../intent/{intent_id}/observation` | Receive and list observations |

Training and prediction need the MLflow artifact bucket. See
[INSTALL.md](INSTALL.md), step 4.
