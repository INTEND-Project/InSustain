# API Guide

Quick reference for InSustain REST API.

## Base URL

```
http://<backend-service>:8089/nnwdaf-analyticsinfo/v1
```

For local development with port-forwarding:
```
http://localhost:8089/nnwdaf-analyticsinfo/v1
```

## Interactive Documentation

Access Swagger UI at: `http://localhost:8089/docs`

## Authentication

Currently no authentication required (internal cluster use).

## Endpoints

### 1. Register Application

Register an application for energy monitoring.

**Endpoint:** `POST /application`

**Request Body:**
```json
{
  "application-id": "my-app",
  "name": "My Application",
  "metadata": {
    "cpu_cores": 4,
    "memory_gb": 8,
    "workload_type": "web-service"
  }
}
```

**Response:** `201 Created`
```json
{
  "application-id": "my-app",
  "status": "unknown",
  "message": "Application registered successfully"
}
```

**Notes:**
- `application-id` and `name` are required
- `metadata` is optional but enables ML predictions
- Status starts as "unknown" until sufficient data is collected

### 2. Get Application Status

Check application registration and model training status.

**Endpoint:** `GET /application/{application-id}`

**Response:** `200 OK`
```json
{
  "application-id": "my-app",
  "name": "My Application",
  "status": "ready",
  "model_trained": true,
  "last_updated": "2026-02-09T10:30:00Z"
}
```

**Status Values:**
- `unknown` - Insufficient data or metadata
- `training` - Model training in progress
- `ready` - Model trained, predictions available
- `error` - Training failed

### 3. Query Energy Metrics

Retrieve historical energy consumption data.

**Endpoint:** `GET /analytics`

**Query Parameters:**
- `appIds` (required) - Comma-separated application IDs or label selectors
- `metricType` (required) - One of: `CPU_JOULES`, `DRAM_JOULES`, `BPF_CPU_TIME_US`, `CPU_CYCLES`
- `appType` (optional) - One of: `CONTAINER`, `POD`, `NAMESPACE`, `NODE` (default: `POD`)
- `offsetPeriod` (required) - Minutes from current time (negative for past, positive for future)
- `startTs` (optional) - Start timestamp (ISO 8601)
- `endTs` (optional) - End timestamp (ISO 8601)

**Example Request:**
```bash
curl "http://localhost:8089/nnwdaf-analyticsinfo/v1/analytics?\
appIds=my-app&\
metricType=CPU_JOULES&\
appType=POD&\
offsetPeriod=-60"
```

**Response:** `200 OK`
```json
{
  "metrics": [
    {
      "timestamp": "2026-02-09T09:30:00Z",
      "value": 1250.5,
      "pod": "my-app-7d8f9c-abc12",
      "namespace": "default"
    },
    {
      "timestamp": "2026-02-09T09:31:00Z",
      "value": 1275.3,
      "pod": "my-app-7d8f9c-abc12",
      "namespace": "default"
    }
  ],
  "aggregation": "pod",
  "metric_type": "CPU_JOULES"
}
```

**Notes:**
- Use negative `offsetPeriod` for historical data (e.g., -60 = last 60 minutes)
- Positive `offsetPeriod` returns predictions if model is trained
- `appIds` can use Kubernetes label selectors (e.g., `app=my-app`)

### 4. Get Energy Predictions

Predict future energy consumption based on application parameters.

**Endpoint:** `GET /predict`

**Query Parameters:**
- `application-id` (required) - Registered application ID
- Application-specific parameters matching registration metadata

**Example Request:**
```bash
curl "http://localhost:8089/nnwdaf-analyticsinfo/v1/predict?\
application-id=my-app&\
cpu_cores=4&\
memory_gb=8&\
workload_type=web-service"
```

**Response:** `200 OK`
```json
{
  "application-id": "my-app",
  "predicted_energy_joules": 5420.8,
  "confidence": 0.92,
  "prediction_window_minutes": 60,
  "model_version": "v1.2.3"
}
```

**Error Response:** `400 Bad Request`
```json
{
  "error": "Model not ready",
  "message": "Application requires more training data or metadata"
}
```

**Notes:**
- Application must have status "ready"
- Parameters must match those provided during registration
- Predictions are for the next hour by default

## Metric Types

### CPU_JOULES
Total CPU energy consumption in joules. Primary metric for CPU power usage.

### DRAM_JOULES
Memory (DRAM) energy consumption in joules. Tracks memory subsystem power.

### BPF_CPU_TIME_US
CPU time in microseconds measured via eBPF. Useful for CPU utilization correlation.

### CPU_CYCLES
Total CPU cycles executed. Low-level metric for detailed analysis.

## Application Types

### CONTAINER
Metrics aggregated per container. Most granular level.

### POD
Metrics aggregated per pod. Default and most common.

### NAMESPACE
Metrics aggregated per namespace. Useful for multi-tenant analysis.

### NODE
Metrics aggregated per node. Cluster-wide infrastructure view.

## Time Ranges

### Using offsetPeriod
Simple relative time specification:
```bash
# Last 30 minutes
offsetPeriod=-30

# Next 60 minutes (predictions)
offsetPeriod=60
```

### Using Timestamps
Explicit time range:
```bash
startTs=2026-02-09T08:00:00Z
endTs=2026-02-09T10:00:00Z
```

## Error Codes

- `200 OK` - Success
- `201 Created` - Resource created
- `400 Bad Request` - Invalid parameters
- `404 Not Found` - Application not found
- `500 Internal Server Error` - Server error

## Examples

### Complete Workflow

```bash
# 1. Register application
curl -X POST http://localhost:8089/nnwdaf-analyticsinfo/v1/application \
  -H "Content-Type: application/json" \
  -d '{
    "application-id": "web-app",
    "name": "Web Application",
    "metadata": {
      "cpu_cores": 2,
      "memory_gb": 4,
      "requests_per_second": 100
    }
  }'

# 2. Check status
curl http://localhost:8089/nnwdaf-analyticsinfo/v1/application/web-app

# 3. Query last hour of CPU energy
curl "http://localhost:8089/nnwdaf-analyticsinfo/v1/analytics?\
appIds=web-app&\
metricType=CPU_JOULES&\
offsetPeriod=-60"

# 4. Get prediction (once model is ready)
curl "http://localhost:8089/nnwdaf-analyticsinfo/v1/predict?\
application-id=web-app&\
cpu_cores=2&\
memory_gb=4&\
requests_per_second=150"
```

## Best Practices

1. **Register with Metadata**: Always provide application metadata for better predictions
2. **Use Label Selectors**: Query multiple pods with `appIds=app=my-app`
3. **Start with POD Level**: Most useful aggregation for application monitoring
4. **Check Model Status**: Verify application status is "ready" before requesting predictions
5. **Use Appropriate Time Windows**: Shorter windows (15-60 min) for real-time, longer for trends

## Full API Specification

See [openapi.yaml](openapi.yaml) for complete OpenAPI 3.0 specification.
