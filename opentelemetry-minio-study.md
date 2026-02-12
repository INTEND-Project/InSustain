# OpenTelemetry for MinIO Content Movement Monitoring - Study Document

## Executive Summary

This study explores using OpenTelemetry (OTel) to capture content movement events between hot and cold MinIO storage instances in the GreenStreams use case, enabling inSustain to analyze the energy consumption of media transfer operations.

## Context

### Current Architecture
- **MOG API**: Independent tool managing video content caching and delivery
- **Storage Tiers**: 
  - Hot storage (MinIO instance): Frequently accessed content
  - Cold storage (MinIO instance): Archived/infrequently accessed content
- **Cache Operations**: Content moves between cache, hot, and cold storage on cache misses
- **inSustain**: Monitors energy consumption but currently lacks visibility into content movement events

### Problem Statement
inSustain needs to correlate energy consumption spikes with content movement operations to:
- Quantify energy cost of cache misses
- Optimize storage tier placement strategies
- Provide sustainability metrics for CDN operations

## OpenTelemetry Overview

### What is OpenTelemetry?
OpenTelemetry is a vendor-neutral observability framework providing:
- **Traces**: Request flow across distributed systems
- **Metrics**: Numerical measurements over time
- **Logs**: Structured event records
- **Context Propagation**: Correlation across service boundaries

### Why OpenTelemetry for This Use Case?
1. **Vendor Neutral**: Works with MinIO, Kubernetes, and custom applications
2. **Distributed Tracing**: Tracks content movement across storage tiers
3. **Metrics Export**: Can push to Prometheus (already used by inSustain)
4. **Low Overhead**: Minimal performance impact
5. **Standard Protocol**: OTLP (OpenTelemetry Protocol) widely supported

## Proposed Architecture

### System Context

The GreenStreams use case involves multiple components as shown in the INTEND architecture (see `docs/intend_architecture-Deliverable-arch.png` and `arch.png`). The MOG API operates independently from inSustain, managing video content delivery with hot/cold storage tiers.

### Component Overview

```
┌─────────────────────────────────────────────────────────────┐
│                       MOG API                                │
│  (Independent - manages cache/storage operations)            │
└───────────────────┬─────────────────────────────────────────┘
                    │
                    │ OTel SDK instrumentation
                    ↓
┌─────────────────────────────────────────────────────────────┐
│              OpenTelemetry Collector                         │
│  - Receives traces/metrics/logs                              │
│  - Processes and enriches data                               │
│  - Routes to multiple backends                               │
└───────┬─────────────────────────────────┬───────────────────┘
        │                                 │
        │ Traces/Spans                    │ Metrics
        ↓                                 ↓
┌───────────────────┐          ┌──────────────────────────┐
│   Jaeger/Tempo    │          │   Prometheus             │
│   (Trace Backend) │          │   (Metrics - existing)   │
└───────────────────┘          └──────────┬───────────────┘
                                          │
                                          │ Query API
                                          ↓
                               ┌──────────────────────────┐
                               │   inSustain Backend      │
                               │   - Correlates energy    │
                               │   - Analyzes patterns    │
                               └──────────────────────────┘
```

### Integration Points

The architecture integrates with existing inSustain components:
- **Prometheus**: Already deployed for Kepler energy metrics
- **Kubernetes API**: Used by inSustain backend for pod/node metadata
- **MongoDB**: Stores historical metrics and analysis results
- **MLflow**: Can use movement patterns for ML model training

### Data Flow

1. **Event Generation**: MOG API detects cache miss
2. **Span Creation**: OTel SDK creates span for content movement operation
3. **Span Attributes**: 
   - Source storage tier (cold/hot)
   - Destination tier
   - Content size (bytes)
   - Content ID/key
   - Operation duration
   - MinIO bucket names
4. **Export**: Span sent to OTel Collector
5. **Processing**: Collector enriches with Kubernetes metadata (pod, node, namespace)
6. **Routing**: 
   - Traces → Jaeger/Tempo for visualization
   - Metrics → Prometheus for inSustain consumption
7. **Correlation**: inSustain queries Prometheus for movement events + Kepler energy metrics

## Implementation Approaches

### Approach 1: Application-Level Instrumentation (Recommended)

**Description**: Instrument MOG API code with OTel SDK

**Pros**:
- Most accurate event capture
- Rich contextual data (content metadata, business logic)
- Fine-grained control over what's traced
- Can capture cache hit/miss ratios

**Cons**:
- Requires code changes in MOG API
- Dependency on MOG API development team

**Implementation**:
```python
# Pseudo-code example
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

# Setup
tracer_provider = TracerProvider()
otlp_exporter = OTLPSpanExporter(endpoint="otel-collector:4317")
tracer_provider.add_span_processor(BatchSpanProcessor(otlp_exporter))
trace.set_tracer_provider(tracer_provider)
tracer = trace.get_tracer(__name__)

# In cache miss handler
def handle_cache_miss(content_id, source_tier, dest_tier):
    with tracer.start_as_current_span("content_movement") as span:
        span.set_attribute("content.id", content_id)
        span.set_attribute("storage.source", source_tier)
        span.set_attribute("storage.destination", dest_tier)
        span.set_attribute("content.size_bytes", get_content_size(content_id))
        
        # Perform actual movement
        move_content(content_id, source_tier, dest_tier)
        
        span.set_attribute("operation.status", "success")
```

### Approach 2: MinIO Event Notifications + OTel Bridge

**Description**: Use MinIO's built-in event notification system, bridge to OTel

**Pros**:
- No MOG API code changes required
- MinIO native feature (stable)
- Captures all object operations

**Cons**:
- Less contextual information (no cache miss context)
- Requires correlation logic to identify "movement" vs other operations
- May miss cache-level operations

**Implementation**:
1. Configure MinIO event notifications (webhook/AMQP/NATS)
2. Create bridge service that:
   - Receives MinIO events (PUT, GET, DELETE)
   - Correlates events to identify movement patterns
   - Creates OTel spans
   - Exports to OTel Collector

**MinIO Event Example**:
```json
{
  "EventName": "s3:ObjectCreated:Put",
  "Key": "videos/content-123.mp4",
  "Records": [{
    "s3": {
      "bucket": {"name": "hot-storage"},
      "object": {
        "key": "videos/content-123.mp4",
        "size": 104857600
      }
    }
  }]
}
```

### Approach 3: Sidecar Proxy Instrumentation

**Description**: Deploy OTel-instrumented proxy alongside MinIO instances

**Pros**:
- No application code changes
- Transparent to MOG API
- Can capture network-level metrics

**Cons**:
- Additional network hop (latency)
- Complex correlation logic needed
- May not capture cache-level context

**Implementation**:
- Deploy Envoy proxy with OTel extension
- Route MinIO traffic through proxy
- Proxy generates spans for S3 API calls
- Requires pattern matching to identify movement operations

## Recommended Approach: Hybrid Strategy

Combine Approach 1 (application instrumentation) with Approach 2 (MinIO events) for comprehensive coverage:

1. **Primary**: Instrument MOG API for cache miss events
   - Captures business logic context
   - Explicit "content movement" spans
   
2. **Fallback**: MinIO event notifications for validation
   - Ensures no missed events
   - Provides object-level metrics

3. **Enrichment**: Kubernetes metadata from OTel Collector
   - Node placement
   - Resource limits
   - Namespace/labels

## Data Schema Design

### Span Attributes (Semantic Conventions)

Following OpenTelemetry semantic conventions:

```yaml
# Core attributes
span.name: "content.movement"
span.kind: "INTERNAL"

# Content attributes
content.id: "video-abc123"
content.size_bytes: 104857600
content.type: "video/mp4"
content.cache_tier: "L2"

# Storage attributes
storage.source.type: "minio"
storage.source.tier: "cold"
storage.source.bucket: "archive-videos"
storage.source.endpoint: "minio-cold:9000"

storage.destination.type: "minio"
storage.destination.tier: "hot"
storage.destination.bucket: "active-videos"
storage.destination.endpoint: "minio-hot:9000"

# Operation attributes
operation.type: "cache_miss_transfer"
operation.duration_ms: 1250
operation.bytes_transferred: 104857600
operation.status: "success"

# Kubernetes context (auto-added by collector)
k8s.namespace.name: "greenstreams"
k8s.pod.name: "cache-manager-7d8f9"
k8s.node.name: "worker-node-3"
```

### Metrics to Export

Convert spans to Prometheus metrics for inSustain consumption:

```yaml
# Counter: Total content movements
content_movements_total{
  source_tier="cold",
  dest_tier="hot",
  namespace="greenstreams"
}

# Histogram: Transfer duration
content_movement_duration_seconds{
  source_tier="cold",
  dest_tier="hot"
}

# Histogram: Transfer size
content_movement_bytes{
  source_tier="cold",
  dest_tier="hot"
}

# Gauge: Active transfers
content_movements_active{
  source_tier="cold",
  dest_tier="hot"
}
```

## Integration with inSustain

### Query Pattern

inSustain backend can correlate energy with content movement:

```python
# Pseudo-code for inSustain backend
from prometheus_api_client import PrometheusConnect

prom = PrometheusConnect(url="http://prometheus:9090")

# Query 1: Get content movement events in time window
movements = prom.custom_query(
    'rate(content_movements_total{namespace="greenstreams"}[5m])'
)

# Query 2: Get energy consumption for same pods/nodes
energy = prom.custom_query(
    'kepler_container_joules_total{namespace="greenstreams"}'
)

# Correlate by timestamp and pod/node
for movement in movements:
    timestamp = movement['timestamp']
    pod = movement['metric']['k8s_pod_name']
    
    # Find corresponding energy spike
    energy_at_time = get_energy_for_pod(energy, pod, timestamp)
    
    # Calculate energy per GB transferred
    bytes_transferred = movement['value']
    energy_per_gb = energy_at_time / (bytes_transferred / 1e9)
```

### New API Endpoint

Add to inSustain backend OpenAPI spec:

```yaml
/api/v1/analytics/content-movement-energy:
  get:
    summary: Get energy consumption analysis for content movements
    parameters:
      - name: start_time
        in: query
        schema:
          type: string
          format: date-time
      - name: end_time
        in: query
        schema:
          type: string
          format: date-time
      - name: source_tier
        in: query
        schema:
          type: string
          enum: [cold, hot, cache]
      - name: dest_tier
        in: query
        schema:
          type: string
          enum: [cold, hot, cache]
    responses:
      200:
        description: Energy analysis results
        content:
          application/json:
            schema:
              type: object
              properties:
                total_movements:
                  type: integer
                total_bytes_transferred:
                  type: integer
                total_energy_joules:
                  type: number
                energy_per_gb:
                  type: number
                movements:
                  type: array
                  items:
                    type: object
                    properties:
                      timestamp:
                        type: string
                      content_id:
                        type: string
                      size_bytes:
                        type: integer
                      duration_ms:
                        type: integer
                      energy_joules:
                        type: number
                      node:
                        type: string
```

## Deployment Considerations

### OpenTelemetry Collector Configuration

Deploy as DaemonSet or Deployment in Kubernetes:

```yaml
# otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  batch:
    timeout: 10s
    send_batch_size: 1024
  
  k8sattributes:
    auth_type: "serviceAccount"
    passthrough: false
    extract:
      metadata:
        - k8s.namespace.name
        - k8s.pod.name
        - k8s.node.name
        - k8s.deployment.name
      labels:
        - tag_name: app
          key: app.kubernetes.io/name
          from: pod
  
  resource:
    attributes:
      - key: service.name
        value: greenstreams-content-movement
        action: upsert

exporters:
  prometheus:
    endpoint: "0.0.0.0:8889"
    namespace: greenstreams
    const_labels:
      component: content_movement
  
  otlp/jaeger:
    endpoint: jaeger-collector:4317
    tls:
      insecure: true
  
  logging:
    loglevel: debug

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [k8sattributes, batch]
      exporters: [otlp/jaeger, logging]
    
    metrics:
      receivers: [otlp]
      processors: [k8sattributes, batch]
      exporters: [prometheus, logging]
```

### Resource Requirements

Estimated resource needs:

- **OTel Collector**: 
  - CPU: 200m-500m
  - Memory: 256Mi-512Mi
  - Storage: Minimal (stateless)

- **Jaeger (optional, for trace visualization)**:
  - CPU: 500m-1000m
  - Memory: 1Gi-2Gi
  - Storage: 10Gi-50Gi (depends on retention)

### Security Considerations

1. **Authentication**: Use mTLS between OTel SDK and Collector
2. **Authorization**: RBAC for Collector to access K8s API
3. **Data Privacy**: Avoid logging sensitive content metadata
4. **Network Policies**: Restrict Collector ingress/egress

## Benefits Analysis

### For inSustain

1. **Precise Correlation**: Link energy spikes to specific operations
2. **Granular Metrics**: Per-tier, per-content-type energy analysis
3. **Predictive Modeling**: Train ML models on movement patterns
4. **Cost Attribution**: Energy cost per cache miss
5. **Optimization Insights**: Identify inefficient movement patterns

### For MOG API / GreenStreams UC

1. **Observability**: Visibility into content movement operations
2. **Performance Analysis**: Identify slow transfers
3. **Debugging**: Trace failed movements
4. **Capacity Planning**: Understand storage tier usage patterns

## Challenges and Mitigations

| Challenge | Mitigation |
|-----------|------------|
| **Performance overhead** | Use sampling (e.g., 10% of movements), batch exports |
| **Data volume** | Implement retention policies, aggregate old data |
| **Coordination with MOG API team** | Provide instrumentation library, minimal code changes |
| **Correlation complexity** | Use span context propagation, consistent timestamps |
| **MinIO event noise** | Filter events at bridge service, focus on movement patterns |

## Alternative Open-Source Tools Comparison

### 1. OpenTelemetry (Recommended)

**Overview**: Vendor-neutral observability framework with traces, metrics, and logs.

**Why Recommended**:
- Industry standard (CNCF graduated project)
- Native Prometheus export (already used by inSustain)
- Rich Kubernetes metadata enrichment
- Supports both traces and metrics in one solution
- Future-proof with active community

**Trade-offs**:
- Requires OTel Collector deployment
- Slightly more complex initial setup

---

### 2. Grafana Tempo + Grafana Agent

**Overview**: Grafana's distributed tracing backend with unified agent.

**Why Consider**:
- Excellent integration if Grafana already deployed
- Supports OTLP protocol (compatible with OTel)
- Cost-effective storage (object storage backend)
- Exemplars link traces to Prometheus metrics

**Trade-offs**:
- Grafana-specific ecosystem
- Metrics export to Prometheus requires additional configuration

**When to Choose**: If Grafana is already deployed and team is familiar with it

---

### 3. Prometheus Pushgateway + Custom Instrumentation

**Overview**: Push metrics directly to Prometheus without additional infrastructure.

**Why Consider**:
- Minimal infrastructure (Prometheus already exists)
- Simple integration
- Low latency

**Trade-offs**:
- No distributed tracing capability
- No span context or correlation
- Missing automatic Kubernetes metadata
- Limited observability (metrics only, no trace visualization)

**When to Choose**: Only if tracing is not needed and simple counters are sufficient

---

## Recommendation Summary

**Primary Choice: OpenTelemetry** - Industry standard with native Prometheus support, provides both traces and metrics, future-proof architecture.

**Alternative: Grafana Tempo + Agent** - Good option if Grafana is already deployed, simpler setup but Grafana-specific.

**Not Recommended: Pushgateway** - Too limited for comprehensive observability, missing tracing and correlation capabilities essential for energy analysis.

---

## Alternative Approaches (Not Recommended)

### 1. Direct MinIO Metrics Scraping
- **Why not**: MinIO metrics don't capture cache miss context
- **Missing**: Business logic, cache tier information

### 2. Log Parsing
- **Why not**: Brittle, high latency, difficult to correlate
- **Missing**: Structured data, real-time capabilities

### 3. Custom Event Bus
- **Why not**: Reinventing the wheel, vendor lock-in
- **Missing**: Standard tooling, community support

## Conclusion

OpenTelemetry provides a robust, vendor-neutral solution for capturing content movement events between MinIO storage tiers. The recommended hybrid approach (application instrumentation + MinIO events) offers comprehensive coverage of content movement operations with rich contextual data for energy correlation.

### Key Takeaways

- **Standard Protocol**: OTLP ensures compatibility and future-proofing
- **Native Integration**: Works seamlessly with existing Prometheus infrastructure
- **Rich Context**: Captures business logic and Kubernetes metadata
- **Minimal Overhead**: Proper configuration keeps performance impact low

### Next Steps

1. Confirm approach with MOG API team
2. Evaluate resource requirements for OTel Collector
3. Design span attributes schema
4. Plan inSustain backend API extensions

## References

- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [MinIO Event Notifications](https://min.io/docs/minio/linux/administration/monitoring/bucket-notifications.html)
- [Kepler Metrics](https://sustainable-computing.io/)
- [Prometheus Semantic Conventions](https://prometheus.io/docs/practices/naming/)
- [OTel Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/)
