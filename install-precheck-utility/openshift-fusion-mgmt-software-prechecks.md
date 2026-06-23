# openshift-fusion-mgmt-software-prechecks

## Overview

[`openshift-fusion-mgmt-software-prechecks.py`](openshift-fusion-mgmt-software-prechecks.py) is an interactive Python-based network validation utility for IBM Fusion HCI cluster installation preparation. It guides users through installation-specific questions with enhanced prompts and validates registry access, certificate files, pull secrets, proxy-based connectivity, and required external endpoints.

The script supports two major installation modes:

- Air-gapped installation (disconnected/offline)
- Connected installation (online with internet access)

It creates a log file named [`installer_validation.log`](installer_validation.log) during execution to record all actions, outcomes, warnings, and errors.

## USAGE

### Quick Start Guide

Follow these steps to run the pre-installation validation tool:

#### 1. Clone the Repository

```bash
git clone https://github.com/IBM/storage-fusion.git
cd storage-fusion/install-precheck-utility
```

#### 2. Install Prerequisites

Ensure the following packages are installed on your system:

```bash
# For RHEL/CentOS/Fedora
sudo dnf install -y python3 podman openssl curl

# For Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y python3 podman openssl curl
```

**Required packages:**
- **Python 3** - Script runtime
- **podman** - Container registry authentication and image pull testing
- **openssl** - Certificate validation
- **curl** - Website/endpoint reachability checks

#### 3. Prepare Required Files

Before running the validation script, ensure you have the necessary files ready on your jumphost:

**For Connected (Online) Installations:**
- **pull-secret.json** - Download your OpenShift pull secret from [Red Hat Console](https://console.redhat.com/openshift/install/pull-secret)
  - Place the file in an accessible location on your jumphost
  - Note down the full file path (e.g., `/home/user/pull-secret.json`)
  - You will need to provide this path during script execution

**For Airgap (Offline) Installations with Self-Signed Certificates:**
- **Registry certificate file (.crt)** - If using a self-signed certificate for your registry (e.g., Quay)
  - Place the certificate file in an accessible location on your jumphost
  - Note down the full file path (e.g., `/home/user/registry-ca.crt`)
  - You will need to provide this path during script execution
  - The certificate should be in PEM format (X.509)

**Optional Files (if applicable):**
- **Ingress certificate and key files** - For custom ingress certificates (connected installs)
- **Additional registry certificates** - If using multiple registries with different certificates

#### 4. Run the Validation Script

```bash
python3 openshift-fusion-mgmt-software-prechecks.py
```

#### 5. Follow Interactive Prompts

The script will guide you through:
- Entering cluster name and base domain
- Selecting installation type (Airgap or Connected)
- Providing registry credentials and certificates (if applicable)
- Validating firewall and proxy configurations (for connected installs)
- Checking access to required endpoints

**Tip:** Have your file paths ready from Step 3 to quickly provide them when prompted.

#### 6. Review Results

- **Console Output**: Real-time validation results with ✓ (success) or ✗ (failure) indicators
- **Log File**: Detailed execution log saved to `installer_validation.log`
- **Summary Report**: Comprehensive validation summary displayed at completion

#### 7. Exit Anytime

Press **Ctrl+C** to exit the script at any point.

### What Gets Validated

- ✓ Registry connectivity and authentication
- ✓ Certificate validity
- ✓ Pull secret format and content
- ✓ Firewall status and registry access (for connected installs with firewall)
- ✓ Proxy configuration and endpoint reachability (for connected installs with proxy)
- ✓ Required external endpoints based on your configuration
- ✓ GPU, China region, Metro DR, Call Home, and Remote Support requirements (if applicable)

## Key Features

### User Experience Enhancements (Version 2.0)
- **Enhanced input prompts** with context, purpose, format examples, and requirements
- **Actionable error messages** with possible causes and troubleshooting steps
- **Informative success messages** with validation details and next steps
- **Progress indicators** showing current step and validation progress
- **Contextual help** explaining technical terms and choice implications
- **Comprehensive summary report** at completion with installation readiness status
- **Standard exit mechanism** using Ctrl+C (no longer requires typing "I want to exit")
- **Validation result tracking** throughout execution for detailed reporting

### Core Validation Capabilities
- Interactive CLI prompts for installation setup
- Logging of validation flow and outcomes
- Registry reachability checks using sockets
- Registry authentication testing with `podman login`
- Image pull validation using `podman pull`
- Certificate validation using `openssl`
- Website reachability validation using `curl`
- Pull-secret JSON validation
- Authentication file generation for `cp.icr.io`
- Conditional validation flows for:
  - Airgap install with single registry
  - Airgap install with multiple registries
  - Connected install with firewall
  - Connected install with proxy
  - Connected install without proxy
  - GPU-enabled cluster requirements
  - China-specific endpoint requirements
  - Metro DR site requirements
  - Call Home and Remote Support requirements

## Prerequisites

Before running [`openshift-fusion-mgmt-software-prechecks.py`](openshift-fusion-mgmt-software-prechecks.py), ensure the following are available on the system:

- Python 3
- [`podman`](openshift-fusion-mgmt-software-prechecks.py:179)
- [`openssl`](openshift-fusion-mgmt-software-prechecks.py:273)
- [`curl`](openshift-fusion-mgmt-software-prechecks.py:324)

The script also expects valid access to:
- Container registries
- Certificate files
- Pull-secret JSON files
- External internet or proxy-restricted endpoints depending on installation mode

## Script Structure

The script is organized into the following major sections:

### Logging Setup

- [`LOG_FILE`](openshift-fusion-mgmt-software-prechecks.py:27) defines the output log file
- [`log_and_print()`](openshift-fusion-mgmt-software-prechecks.py:37) prints messages to the terminal and writes them to the log

### Input Helper Functions

- [`print_section_header()`](openshift-fusion-mgmt-software-prechecks.py) displays formatted section headers with step numbers and descriptions
- [`print_prompt()`](openshift-fusion-mgmt-software-prechecks.py) displays formatted input prompts with context, purpose, and format information
- [`get_user_input()`](openshift-fusion-mgmt-software-prechecks.py) collects user input with enhanced prompts showing context, purpose, format, and notes
- [`get_password_input()`](openshift-fusion-mgmt-software-prechecks.py) securely captures passwords with contextual information
- [`get_choice_input()`](openshift-fusion-mgmt-software-prechecks.py) restricts user input to allowed options with detailed option descriptions

### Validation Functions

All validation functions now include:
- Progress indicators (e.g., "[1/3] Testing connectivity...")
- Detailed success messages with configuration details
- Actionable error messages with troubleshooting steps
- Result tracking for summary report

- [`check_firewall_status()`](openshift-fusion-mgmt-software-prechecks.py) checks if firewall is active/running on the system (firewalld, iptables, or ufw)
- [`check_registry_reachability()`](openshift-fusion-mgmt-software-prechecks.py) checks socket-level connectivity to a registry with detailed error diagnostics
- [`podman_login_test()`](openshift-fusion-mgmt-software-prechecks.py) validates registry login using Podman with authentication troubleshooting
- [`podman_pull_test()`](openshift-fusion-mgmt-software-prechecks.py) validates image pull capability from a registry with specific error scenarios
- [`validate_file_path()`](openshift-fusion-mgmt-software-prechecks.py) checks file existence and readability with access troubleshooting
- [`validate_certificate()`](openshift-fusion-mgmt-software-prechecks.py) validates X.509 certificate content using OpenSSL with format guidance
- [`check_site_reachability()`](openshift-fusion-mgmt-software-prechecks.py) validates website access with optional proxy support (concise output format)
- [`create_auth_file()`](openshift-fusion-mgmt-software-prechecks.py) creates an auth JSON file by merging pull-secret content with IBM entitlement credentials
- [`validate_json_file()`](openshift-fusion-mgmt-software-prechecks.py) checks whether a file contains valid JSON with syntax troubleshooting

### Result Tracking and Reporting

- [`add_validation_result()`](openshift-fusion-mgmt-software-prechecks.py) tracks validation results by category and severity for summary report
- [`print_validation_summary()`](openshift-fusion-mgmt-software-prechecks.py) generates comprehensive end-of-run summary with installation readiness status

### Main Execution Flow

- [`main()`](openshift-fusion-mgmt-software-prechecks.py:403) orchestrates the full validation workflow
- The script entry point starts execution in [`if __name__ == "__main__":`](openshift-fusion-mgmt-software-prechecks.py:829)

## Functional Flow

## 1. Cluster Information

The script first collects:

- Cluster name
- Base domain

These values are later used to build cluster-specific URLs for connected installation validation.

## 2. Installation Type Selection

The user selects one of the following:

- `1` = Airgap install
- `2` = Connected install

Based on this choice, the script enters the corresponding workflow.

## 3. Airgap Installation Flow

When `airgap_install` is selected, the script asks whether the deployment uses:

- A single registry
- Multiple registries

### Single Registry Path

The script collects:

- Registry URL
- Registry username
- Registry password

Then it performs:

- Registry reachability validation
- Podman login validation
- OpenShift image pull validation

If a certificate is used, it also collects a certificate file path and validates it.

### Multiple Registries Path

The script separately collects and validates details for:

- OpenShift registry
- Fusion registry

For each registry, it performs:

- Reachability checks
- Podman login validation
- Image pull validation

If certificates are used, each certificate path is validated separately.

## 4. Connected Installation Flow

When `connected_install` is selected, the script first asks whether installation uses:

- Firewall
- No firewall

### Connected Install With Firewall

If firewall is selected, the script performs:

- **Firewall Status Check**: Validates that the firewall is active and running using one of the following methods:
  - `firewall-cmd --state` (for firewalld)
  - `iptables -L -n` (for iptables)
  - `ufw status` (for ufw)

- **Registry Access Validation**: Checks connectivity to all required registries through the firewall:
  - `icr.io` - IBM Container Registry
  - `cp.icr.io` - IBM Cloud Pak Container Registry
  - `gcr.io` - Google Container Registry
  - `registry.redhat.io` - Red Hat Container Registry
  - `quay.io` - Quay.io Container Registry
  - `cdn01.quay.io`, `cdn02.quay.io`, `cdn03.quay.io`, `cdn04.quay.io`, `cdn05.quay.io`, `cdn06.quay.io` - Quay.io CDN endpoints
  - `access.redhat.com` - Red Hat Access Portal
  - `api.access.redhat.com` - Red Hat API Access
  - `cert-api.access.redhat.com` - Red Hat Certificate API
  - `infogw.api.openshift.com` - OpenShift Info Gateway
  - `console.redhat.com` - Red Hat Console (including `/api/ingress`)
  - `cloud.redhat.com` - Red Hat Cloud (including `/api/ingress`)
  - `mirror.openshift.com` - OpenShift Mirror
  - `storage.googleapis.com` - Google Storage (for `/openshift-release`)
  - `oauth-openshift.apps.<cluster_name>.<base_domain>` - Cluster OAuth endpoint
  - `console-openshift-console.apps.<cluster_name>.<base_domain>` - Cluster console endpoint
  - `quayio-production-s3.s3.amazonaws.com` - Quay.io S3 Storage
  - `api.openshift.com` - OpenShift API
  - `art-rhcos-ci.s3.amazonaws.com` - RHCOS CI S3 Storage
  - `registry.access.redhat.com` - Red Hat Registry Access
  - `sso.redhat.com` - Red Hat SSO
  - `esupport.ibm.com` - IBM Support Portal
  - `www.ecurep.ibm.com` - IBM eCuRep

After firewall checks, the script then asks whether installation uses:

- Proxy
- No proxy

### Connected Install With Proxy

The script asks whether the proxy is:

- Authenticated
- Unauthenticated

It then collects proxy host and port, and optionally username and password.

Additional environment-specific selections include:

- GPU cluster
- China region
- Metro DR
- Call Home
- Remote Support

The script validates access to a base list of sites, plus additional sites depending on the selected options.

#### Base sites checked

Examples include:

- `icr.io`
- `cp.icr.io`
- `registry.redhat.io`
- `quay.io`
- `docker.io`
- `api.openshift.com`

It also validates cluster-specific generated endpoints such as:

- `oauth-openshift.apps.<cluster>.<base_domain>`
- `canary-openshift-ingress-canary.apps.<cluster>.<base_domain>`
- `console-openshift-console.apps.<cluster>.<base_domain>`

#### Conditional sites checked

- GPU: NVIDIA and OpenShift cloud endpoints
- China: IBM China registry endpoints
- Metro DR: `gcr.io`
- Call Home: IBM support endpoints
- Remote Support: relay and backend support endpoints

### Connected Install Without Proxy

The script collects:

- IBM entitlement key
- Pull-secret JSON file path

Then it performs:

- Pull-secret file existence validation
- Pull-secret JSON syntax validation
- Auth file creation through [`create_auth_file()`](openshift-fusion-mgmt-software-prechecks.py:343)
- Registry reachability checks for common registries

It also prompts for optional ingress certificate and key file paths and validates them if provided.

## Files Created or Referenced

### Created during execution

- [`installer_validation.log`](installer_validation.log)
- [`authfile.json`](authfile.json) by default from [`create_auth_file()`](openshift-fusion-mgmt-software-prechecks.py:343)

### Referenced as input

- Pull secret JSON file
- Registry certificate files
- Ingress certificate and key files

## How to Run

From the project directory, run:

```bash
python3 openshift-fusion-mgmt-software-prechecks.py
```

## Example Usage

1. Start the script
2. Enter cluster name and base domain
3. Choose installation type
4. Answer prompts based on your environment
5. Review console output and log file for validation results

## Logging Behavior

All major actions are both printed to the terminal and written to [`installer_validation.log`](installer_validation.log) through [`log_and_print()`](openshift-fusion-mgmt-software-prechecks.py:37).

Sensitive fields such as passwords are masked in logs where applicable.

## Exit Behavior

Users can exit the script at any time by pressing **Ctrl+C**.

The script includes graceful interrupt handling that:
- Logs the exit event
- Displays a clean exit message
- Terminates the program safely

This standard exit mechanism (Ctrl+C) is more intuitive than the previous "I want to exit" text requirement.

## Error Handling

The script includes:

- Input validation loops for empty or invalid options
- Graceful `Ctrl+C` handling in the entry block
- Generic exception handling in the main entry point

If an unexpected error occurs, it is logged and displayed to the user.

## Notes and Limitations

- The script uses shell commands through Python subprocesses, so required binaries must be installed and available in `PATH`.
- Registry/image paths are currently hardcoded for certain validation checks.
- The script validates connectivity and file presence but does not persist a structured summary report other than the log file.
- Proxy support is implemented for website reachability checks, but not as a general session-wide network configuration.
- The generated auth file uses a placeholder email value for `cp.icr.io`.

## Main Functions Reference

### Logging and Display
- [`log_and_print()`](openshift-fusion-mgmt-software-prechecks.py) - Logs messages to file and prints to screen
- [`print_section_header()`](openshift-fusion-mgmt-software-prechecks.py) - Displays formatted section headers with step numbers
- [`print_prompt()`](openshift-fusion-mgmt-software-prechecks.py) - Displays formatted input prompts with context

### Input Functions
- [`get_user_input()`](openshift-fusion-mgmt-software-prechecks.py) - Collects user input with enhanced prompts
- [`get_password_input()`](openshift-fusion-mgmt-software-prechecks.py) - Securely captures passwords with context
- [`get_choice_input()`](openshift-fusion-mgmt-software-prechecks.py) - Restricts input to valid options with descriptions

### Validation Functions
- [`check_firewall_status()`](openshift-fusion-mgmt-software-prechecks.py) - Checks if firewall is active/running
- [`check_registry_reachability()`](openshift-fusion-mgmt-software-prechecks.py) - Tests registry connectivity
- [`podman_login_test()`](openshift-fusion-mgmt-software-prechecks.py) - Validates registry authentication
- [`podman_pull_test()`](openshift-fusion-mgmt-software-prechecks.py) - Tests image pull capability
- [`validate_file_path()`](openshift-fusion-mgmt-software-prechecks.py) - Checks file existence and readability
- [`validate_certificate()`](openshift-fusion-mgmt-software-prechecks.py) - Validates X.509 certificates
- [`check_site_reachability()`](openshift-fusion-mgmt-software-prechecks.py) - Tests website connectivity
- [`create_auth_file()`](openshift-fusion-mgmt-software-prechecks.py) - Creates authentication file
- [`validate_json_file()`](openshift-fusion-mgmt-software-prechecks.py) - Validates JSON file format

### Result Tracking and Reporting
- [`add_validation_result()`](openshift-fusion-mgmt-software-prechecks.py) - Tracks validation results
- [`print_validation_summary()`](openshift-fusion-mgmt-software-prechecks.py) - Generates comprehensive summary report

### Main Execution
- [`main()`](openshift-fusion-mgmt-software-prechecks.py) - Main program entry point

## Summary

[`openshift-fusion-mgmt-software-prechecks.py`](openshift-fusion-mgmt-software-prechecks.py) (Version 2.0) is an enhanced, user-friendly pre-installation validation tool for IBM Fusion HCI environments.

### Key Improvements in Version 2.0

**Enhanced User Experience:**
- Clear, contextual input prompts with examples and requirements
- Actionable error messages with troubleshooting steps
- Detailed success messages explaining validation results
- Progress indicators showing current step and completion status
- Comprehensive summary report with installation readiness determination

**Improved Communication:**
- Standard exit mechanism (Ctrl+C) instead of typing "I want to exit"
- Contextual help explaining technical terms and choices
- Structured error messages with possible causes and solutions
- Validation result tracking throughout execution

**Better Guidance:**
- Step-by-step progress through validation workflow
- Clear indication of critical vs. warning vs. informational results
- Specific troubleshooting commands for common issues
- Next steps based on validation outcomes

The tool helps verify that required registries, certificates, credentials, pull secrets, proxies, and external endpoints are accessible before proceeding with cluster installation, while providing clear guidance to resolve any issues discovered.

## Version History

- **Version 1.0**: Original implementation with basic prompts and error messages
- **Version 2.0**: Enhanced usability with improved prompts, actionable error messages, progress indicators, contextual help, and comprehensive summary reporting
