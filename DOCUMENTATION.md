# InSustain Documentation Index

Complete guide to InSustain documentation and resources.

## Getting Started

| Document | Purpose | Time Required |
|----------|---------|---------------|
| [QUICKSTART.md](QUICKSTART.md) | Get running in 5 minutes | 5-10 min |
| [README.md](README.md) | Overview and key features | 5 min read |
| [INSTALL.md](INSTALL.md) | Detailed installation guide | 15-30 min |

## Documentation

| Document | Purpose |
|----------|---------|
| [README.md](README.md) | Overview and quick start |
| [INSTALL.md](INSTALL.md) | Detailed installation guide |
| [CONFIGURATION.md](CONFIGURATION.md) | Complete configuration reference |
| [RBAC.md](RBAC.md) | RBAC permissions and security guide |
| [API_GUIDE.md](API_GUIDE.md) | API reference with examples |
| [QUICKSTART.md](QUICKSTART.md) | 5-minute quick start |
| [openapi.yaml](openapi.yaml) | OpenAPI 3.0 specification |

## Architecture & Design

| Document | Purpose |
|----------|---------|
| [API_GUIDE.md](API_GUIDE.md) | Complete API reference with examples |
| [openapi.yaml](openapi.yaml) | OpenAPI 3.0 specification |
| [workflow.png](workflow.png) | Application monitoring workflow diagram |

## Architecture & Design

| Resource | Description |
|----------|-------------|
| [arch.png](arch.png) | System architecture diagram |
| [ontology/](ontology/) | Semantic ontology definitions (RDF/Turtle) |
| [insustain/values.yaml](insustain/values.yaml) | Helm chart configuration reference |

## Reference

| Document | Purpose |
|----------|---------|
| [CHANGELOG.md](CHANGELOG.md) | Version history and changes |
| Steering files (.kiro/steering/) | Project conventions and structure |

## Documentation by Role

### System Administrator / Infrastructure Engineer
1. Start with [QUICKSTART.md](QUICKSTART.md)
2. Review [INSTALL.md](INSTALL.md) for production setup
3. Check [insustain/values.yaml](insustain/values.yaml) for configuration options
4. Reference [arch.png](arch.png) for architecture understanding
5. Contact team for registry credentials

### End User / API Consumer
1. Read [README.md](README.md) for overview
2. Study [API_GUIDE.md](API_GUIDE.md) for API usage
3. Review [workflow.png](workflow.png) for monitoring workflow
4. Use [openapi.yaml](openapi.yaml) for API reference

### Project Partner / Researcher
1. Start with [README.md](README.md) for capabilities overview
2. Review [arch.png](arch.png) and [workflow.png](workflow.png) for system design
3. Check [ontology/](ontology/) for semantic definitions
4. Reference [CHANGELOG.md](CHANGELOG.md) for latest updates

## Common Tasks

### Installation
- **Quick test**: [QUICKSTART.md](QUICKSTART.md)
- **Production setup**: [INSTALL.md](INSTALL.md) → Persistent Storage section
- **Custom configuration**: [insustain/values.yaml](insustain/values.yaml)

### API Usage
- **First API call**: [QUICKSTART.md](QUICKSTART.md) → First API Call
- **Complete reference**: [API_GUIDE.md](API_GUIDE.md)
- **Integration**: [openapi.yaml](openapi.yaml)

### Troubleshooting
- **Installation issues**: [INSTALL.md](INSTALL.md) → Troubleshooting
- **Quick fixes**: [QUICKSTART.md](QUICKSTART.md) → Troubleshooting
- **Configuration**: [insustain/values.yaml](insustain/values.yaml)

### Configuration
- **Helm values**: [insustain/values.yaml](insustain/values.yaml)
- **Custom Prometheus**: [INSTALL.md](INSTALL.md) → Step 4
- **Image registry**: [INSTALL.md](INSTALL.md) → Step 3

## Additional Resources

### Scripts
Located in `scripts/scripts/`:
- `setup-insustain.sh` - Automated installation
- `setup-insustain-k8s-native.sh` - K8s native setup
- `import-images-to-k3s.sh` - K3s image import helper

### Certificates
Located in `certs/`:
- `docker_ca.crt` - Docker registry CA certificate

### Images
Located in `images/`:
- UI screenshots for documentation
- Example API requests and responses

## Version Information

- **Current Release**: v1.2.0
- **Distribution**: Git-based versioning via GitHub releases
- **Download**: GitHub auto-generates source archives from tags
- **Helm Chart**: Source charts in `insustain/` directory

### Getting Specific Versions

**Option A: Download from GitHub Releases**
```bash
curl -L https://github.com/INTEND-Project/InSustain/archive/refs/tags/v1.2.0.tar.gz -o insustain.tar.gz
```

**Option B: Git Clone**
```bash
git clone --branch v1.2.0 --depth 1 https://github.com/INTEND-Project/InSustain.git
```

## Support

For questions, issues, or access to private Docker registry:
- Contact INTEND project team
- Provide version information from [CHANGELOG.md](CHANGELOG.md)

## Contributing

This is a distribution repository for INTEND project partners. For contributions or issues, contact the project team.

## License

Proprietary - INTEND Project
