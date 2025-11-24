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

# Pulling inSustain Docker images

We provide a minimal docker repository with TLS security to download the inSustain images. The procedure to download the images is:

Download the [docker_cert](certs/docker_ca.crt) and add them into the directory necessary to login into our docker repository. For instance in ubuntu the appropiate directory is 

## Download the certs

```bash
sudo mkdir -p /etc/docker/certs.d/89.133.95.6:5001
sudo cp docker_cert /etc/docker/certs.d/89.133.95.6:5001
sudo chmod 600 /etc/docker/certs.d/89.133.95.6:5001/*
```

## Restart the docker service using

```bash
sudo systemctl restart docker
```

## Authenticate
Once the certificates have been placed on the appropiate directory and the docker service has been restarted then login can be attempted using the credentials provided (via email)

```bash
docker login 89.133.95.6:5001 -u intend -p <password>
```

## Obtain docker images
Once login is successful images can be downloaded from the repository. For instance to a minimal installation of the inSustain tool the backend iamge is necessary and can be downloaded using the command:

```bash
docker save 89.133.95.6:5001/insustain/backend:latest -o backend.tar
```

## Import into K3s/K3s nodes
Finally, the docker image can be imported into the K8s/K3s server nodes available for pod deployment. For instance, using the following command:

```bash
sudo k3s ctr images import backend.tar
```

# Install inSustain

To install inSustain first download the helm chart from a release on this repository:

```bash
curl "https://github.com/INTEND-Project/InSustain/releases/download/v1.2.0/insustain-1.2.0.tgz" -o insustain-1.2.0.tgz
```

## Install the HELM chart
Using the standard HELM chart downloaded on the previous step
```bash
helm install <helm-chart-name> insustain
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