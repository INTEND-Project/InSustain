# inSustain - A tool of the INTEND project

InSustain provide estimated energy metrics for cloud native deployments. The erngy metrics can be queried using our API or the webservice UI. Prediction of energy metrics is under development but it will be available soon. 

# Pre-requisites

- Kubernetes cluster v1.30.6+
- HELM v3.17.1+
- prometheus-operator v0.80+ (or any other equivalent Prometheus server)
- [Kepler](https://sustainable-computing.io/) v0.7+ (Installed with inSustain)

# Prometheus installation

We recommend the Kube Prometheus Stack helm chart, which includes the Node Exporter, Grafana and other helpful stuff to provide easy to operate end-to-end Kubernetes cluster monitoring with Prometheus using the Prometheus Operator.

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --create-namespace \
    --wait
```

# Install inSustain

```bash
helm install <helm-chart-name> insustain --create-namespace --namespace insustain --set backend.enabled=true --set frontend.enabled=true --set kepler.enabled=true
```
If there is already a prometheus server installed in a different namespace then inSustain can use this deployment by setting the following values in the HELM installation

```bash
helm install <helm-chart-name> insustain --create-namespace --namespace insustain --set backend.enabled=true --set frontend.enabled=true --set kepler.enabled=true --set prometheus.namespace= <prometheus-namespace> --set prometheus.servceName=<prometheus-name>
```

# Accessing the cluster (WIP)
To provide support for the inSustain app we are working on enbling a kubernetes pod with a NetBird client that can be used to connect securely using a private VPN.
[NetBird](https://netbird.io/)

# Backend
Using the default values of the inSustain HELM chart the backend service is a kubernetes service using port 8089.
This service can be inspected using kubernetes port-forwarding.

# Frontend
Using the default values of the inSustain HELM chart the frontend service is a kubernetes service using port 8080.
This service can be inspected using kubernetes port-forwarding.

# Architecture
This is an architecture example of the inSustain application
![](arch.png)