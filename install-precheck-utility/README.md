# Pre-installation Validation Utilities

IBM Fusion HCI pre-installation validation utilities provide automated checks to verify environment readiness for IBM Fusion HCI deployments. These scripts validate critical software dependencies, network configuration, connectivity, credentials, and external access requirements, helping identify and resolve issues before installation.

## IBM Fusion HCI Management Software Precheck and Validation

### openshift-fusion-mgmt-software-prechecks.py

The `openshift-fusion-mgmt-software-prechecks.py` script is an interactive pre-installation validation utility designed to assess readiness for IBM Fusion HCI management cluster deployment. The script guides users through environment-specific inputs and validates required software, registry access, credentials, certificates, and external connectivity for both connected and air-gapped installations.

The script validates the following areas to ensure installation readiness:

- **Container registry validation** - Verifies registry connectivity, authentication, and image pull capability
- **Credential and configuration validation** - Tests registry credentials, pull secrets, and IBM entitlement keys
- **X.509 Certificate validation** - Validates certificate files for registries and ingress
- **Network and endpoint connectivity** - Checks access to required external endpoints and services
- **Firewall validation** - Verifies firewall status and registry access through firewall (for connected installs)
- **Proxy validation** - Tests proxy configuration and endpoint reachability (for connected installs)
- **Installation mode validation** - Supports both airgap (disconnected) and connected (online) installation modes
- **Validation result tracking and summarization** - Provides comprehensive summary report with installation readiness status
- **Log generation for audit and troubleshooting** - Creates detailed log file for all validation activities

**Documentation:** See [openshift-fusion-mgmt-software-prechecks.md](openshift-fusion-mgmt-software-prechecks.md) for detailed usage instructions, functional flow, and API reference.

## IBM Fusion HCI Network Precheck and Validation

### fusion-hci-network-prechecks.py

The `fusion-hci-network-prechecks.py` script is a network validation utility that verifies connectivity, configuration, and infrastructure readiness for IBM Fusion HCI deployments. The script supports both interactive and CLI execution modes and performs comprehensive network-level checks across addressing, name resolution, connectivity, and time synchronization.

The script includes the following network validation capabilities:

- **IP configuration validation** - Verifies IP addressing, subnet masks, and network interface configuration
- **DNS validation** - Tests DNS resolution for cluster endpoints and external services
- **Network connectivity validation** - Checks connectivity between cluster nodes and required endpoints
- **NTP configuration and synchronization checks** - Validates time synchronization across cluster nodes
- **Network interface validation** - Verifies network interface status and configuration
- **Parallel execution of validation tasks** - Performs multiple checks concurrently for efficiency
- **Input validation and error handling** - Provides clear error messages and troubleshooting guidance
- **Logging and output reporting** - Generates detailed logs and summary reports

## Documentation Files

### openshift-fusion-mgmt-software-prechecks.md

Comprehensive documentation for the management software precheck utility, including:

- **USAGE section** - Quick start guide with step-by-step instructions for cloning, installing prerequisites, and running the script
- **Overview and key features** - Detailed description of capabilities and enhancements in Version 2.0
- **Prerequisites** - Required packages and system dependencies
- **Script structure** - Organization of code sections and functions
- **Functional flow** - Detailed walkthrough of validation workflows for different installation modes
- **Function reference** - Complete API documentation for all validation functions
- **Error handling and exit behavior** - Information on error messages and graceful exit mechanisms
- **Version history** - Changes and improvements across versions

### openshift-fusion-mgmt-software-prechecks-flow-document.md

Flow diagram and decision tree documentation showing the logical flow of the management software precheck script, including:

- Installation type selection paths
- Conditional validation branches
- Decision points and user prompts
- Validation sequences for different configurations

## Getting Started

### Quick Start for Management Software Prechecks

```bash
# Clone the repository
git clone https://github.com/IBM/storage-fusion.git
cd storage-fusion/install-precheck-utility

# Install prerequisites
sudo dnf install -y python3 podman openssl curl  # RHEL/CentOS/Fedora
# OR
sudo apt-get install -y python3 podman openssl curl  # Ubuntu/Debian

# Run the validation script
python3 openshift-fusion-mgmt-software-prechecks.py
```

### Quick Start for Network Prechecks

```bash
# Navigate to the utility directory
cd storage-fusion/install-precheck-utility

# Run the network validation script
python3 fusion-hci-network-prechecks.py
```

## Support

For issues, questions, or contributions, please refer to the main [storage-fusion repository](https://github.com/IBM/storage-fusion).

## License

See the [LICENSE](../LICENSE) file in the root of the repository for license information.