New version 1.3.0
# Changelog

## [1.3.0] - 2026-02-09

### Added
- 

### Changed
- 

### Fixed
- 


## [1.2.0] - 2026-02-09

### Distribution Changes

**Git-Based Versioning:**
- Moved to Git tags for version management
- GitHub automatically generates source archives
- No more manual packaging of .tgz files
- Partners download from GitHub releases or clone specific tags

**Download Options:**
- Option A: `curl -L https://github.com/INTEND-Project/InSustain/archive/refs/tags/v1.2.0.tar.gz`
- Option B: `git clone --branch v1.2.0 --depth 1 https://github.com/INTEND-Project/InSustain.git`

### Repository Cleanup

**Removed Files:**
- Old Helm chart versions (insustain-0.1.0.tgz, insustain-1.0.0.tgz, insustain-1.1.0.tgz)
- Duplicate extracted directory (InSustain-1.2.0/)
- Generated documentation files (README_user.pdf, README_user.html, docs.html)
- LaTeX artifacts (listting-setup.tex)
- Misnamed archive file (ubuntu@10.13.14.10)
- Duplicate image files (image.png)
- Duplicate README (README_user.md)

**Documentation Improvements:**
- Consolidated README.md with clear structure and quick start
- Created INSTALL.md with detailed step-by-step installation guide
- Created API_GUIDE.md with comprehensive API reference and examples
- Updated steering files with current repository structure
- Added this CHANGELOG for tracking changes

**Current Structure:**
- Single release artifact: InSustain-1.2.0.tar.gz
- Source Helm charts in insustain/ directory
- Clear separation of documentation, scripts, and configuration
- Organized images in images/ directory

### Features

- Energy metrics collection (CPU_JOULES, DRAM_JOULES, BPF_CPU_TIME_US, CPU_CYCLES)
- Application registration with metadata
- Historical analytics API with flexible time ranges
- ML-based energy prediction (when metadata available)
- Multi-level aggregation (CONTAINER, POD, NAMESPACE, NODE)

### Components

- Backend API (FastAPI) - Port 8089
- MongoDB - Application metadata storage
- MLflow - ML model training and serving
- Kepler 0.5.13 - Energy metrics collection
- Prometheus - Time-series metrics storage
- Frontend (optional) - Web UI

### Requirements

- Kubernetes v1.30.6+
- Helm v3.17.1+
- Prometheus Operator v0.80+
- Kepler v0.8+

### Known Issues

- Images hosted on private registry (credentials required)
- No authentication on API endpoints (internal cluster use only)
- Predictions require sufficient application metadata

### Migration Notes

If upgrading from previous versions:
1. Uninstall old version: `helm uninstall insustain -n insustain`
2. Follow new installation guide in INSTALL.md
3. Re-register applications with updated metadata schema
