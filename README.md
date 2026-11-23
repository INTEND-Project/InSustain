# InSustain

InSustain is the energy observability component of the EU INTEND project. It
collects energy and resource metrics for workloads in a Kubernetes cluster,
predicts the energy cost of a configuration, and answers TMF921 intents with
energy reports.

This repository holds the Helm chart and its documentation. The container
images are private and are pulled from GitHub Container Registry with a token
issued to INTEND partners.

| Document | Contents |
|----------|----------|
| [INSTALL.md](INSTALL.md) | Prerequisites, the Secrets to create, install and upgrade |
| [API.md](API.md) | The HTTP API and how to reach it |
| [LICENSE](LICENSE) | Licence of the InSustain software |

## Releases

Each release `v2.0.<n>` is published on the GitHub releases page with these
assets:

| Asset | Contents |
|-------|----------|
| `insustain-2.0.<n>.tgz` | Packaged Helm chart. It pins both images by digest. |
| `insustain-backend.spdx.json`, `insustain-frontend.spdx.json` | SPDX software bill of materials for each image |
| `insustain-backend-notices.tar.gz`, `insustain-frontend-notices.tar.gz` | Third-party notices for each image |

Each notices archive holds the third-party package inventory of its image,
the licence, copyright and notice files the image ships, and a list of
packages whose licence could not be resolved from the image. Its `README.txt`
explains what the archive does and does not establish.

The SBOMs and notices are generated from the exact images the chart pins,
and are checked by the release pipeline before publication. Licence
identifiers in them are package metadata, not legal advice.

## Components

The chart installs:

- `backend`: the InSustain API (port 8089)
- `frontend`: the dashboard (port 3000). It is optional.
- `mongodb`, `postgres`: application and MLflow storage
- `minio`: object storage for MLflow artifacts
- `mlflow`: model tracking and registry

Every Service is `ClusterIP`. Nothing is exposed outside the cluster unless
you add an Ingress or a port-forward.
