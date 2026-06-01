# installerNetworkValidation

## Overview

[`installerNetworkValidation.py`](installerNetworkValidation.py) is an interactive Python-based network validation utility for HCI cluster installation preparation. It guides the user through installation-specific questions and validates registry access, certificate files, pull secrets, proxy-based connectivity, and required external endpoints.

The script supports two major installation modes:

- Air-gapped installation
- Connected installation

It also creates a log file named [`installer_validation.log`](installer_validation.log) during execution to record all actions, outcomes, warnings, and errors.

## Key Features

- Interactive CLI prompts for installation setup
- Graceful exit support by typing `I want to exit`
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
  - Connected install with proxy
  - Connected install without proxy
  - GPU-enabled cluster requirements
  - China-specific endpoint requirements
  - Metro DR site requirements
  - Call Home and Remote Support requirements

## Prerequisites

Before running [`installerNetworkValidation.py`](installerNetworkValidation.py), ensure the following are available on the system:

- Python 3
- [`podman`](installerNetworkValidation.py:179)
- [`openssl`](installerNetworkValidation.py:273)
- [`curl`](installerNetworkValidation.py:324)

The script also expects valid access to:
- Container registries
- Certificate files
- Pull-secret JSON files
- External internet or proxy-restricted endpoints depending on installation mode

## Script Structure

The script is organized into the following major sections:

### Logging Setup

- [`LOG_FILE`](installerNetworkValidation.py:27) defines the output log file
- [`log_and_print()`](installerNetworkValidation.py:37) prints messages to the terminal and writes them to the log

### Input Helper Functions

- [`check_exit_command()`](installerNetworkValidation.py:54) exits the script when the user types the supported exit phrase
- [`get_user_input()`](installerNetworkValidation.py:64) collects non-empty user input
- [`get_password_input()`](installerNetworkValidation.py:87) securely captures passwords
- [`get_choice_input()`](installerNetworkValidation.py:109) restricts user input to allowed options

### Validation Functions

- [`check_registry_reachability()`](installerNetworkValidation.py:143) checks socket-level connectivity to a registry
- [`podman_login_test()`](installerNetworkValidation.py:179) validates registry login using Podman
- [`podman_pull_test()`](installerNetworkValidation.py:209) validates image pull capability from a registry
- [`validate_file_path()`](installerNetworkValidation.py:246) checks file existence and readability
- [`validate_certificate()`](installerNetworkValidation.py:260) validates X.509 certificate content using OpenSSL
- [`check_site_reachability()`](installerNetworkValidation.py:305) validates website access with optional proxy support
- [`create_auth_file()`](installerNetworkValidation.py:343) creates an auth JSON file by merging pull-secret content with IBM entitlement credentials
- [`validate_json_file()`](installerNetworkValidation.py:380) checks whether a file contains valid JSON

### Main Execution Flow

- [`main()`](installerNetworkValidation.py:403) orchestrates the full validation workflow
- The script entry point starts execution in [`if __name__ == "__main__":`](installerNetworkValidation.py:829)

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

When `connected_install` is selected, the script asks whether installation uses:

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
- Auth file creation through [`create_auth_file()`](installerNetworkValidation.py:343)
- Registry reachability checks for common registries

It also prompts for optional ingress certificate and key file paths and validates them if provided.

## Files Created or Referenced

### Created during execution

- [`installer_validation.log`](installer_validation.log)
- [`authfile.json`](authfile.json) by default from [`create_auth_file()`](installerNetworkValidation.py:343)

### Referenced as input

- Pull secret JSON file
- Registry certificate files
- Ingress certificate and key files

## How to Run

From the project directory, run:

```bash
python3 installerNetworkValidation.py
```

## Example Usage

1. Start the script
2. Enter cluster name and base domain
3. Choose installation type
4. Answer prompts based on your environment
5. Review console output and log file for validation results

## Logging Behavior

All major actions are both printed to the terminal and written to [`installer_validation.log`](installer_validation.log) through [`log_and_print()`](installerNetworkValidation.py:37).

Sensitive fields such as passwords are masked in logs where applicable.

## Exit Behavior

At any prompt, the user can type:

`I want to exit`

This is handled by [`check_exit_command()`](installerNetworkValidation.py:54), which logs the event and terminates the program cleanly.

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

- [`log_and_print()`](installerNetworkValidation.py:37)
- [`check_exit_command()`](installerNetworkValidation.py:54)
- [`get_user_input()`](installerNetworkValidation.py:64)
- [`get_password_input()`](installerNetworkValidation.py:87)
- [`get_choice_input()`](installerNetworkValidation.py:109)
- [`check_registry_reachability()`](installerNetworkValidation.py:143)
- [`podman_login_test()`](installerNetworkValidation.py:179)
- [`podman_pull_test()`](installerNetworkValidation.py:209)
- [`validate_file_path()`](installerNetworkValidation.py:246)
- [`validate_certificate()`](installerNetworkValidation.py:260)
- [`check_site_reachability()`](installerNetworkValidation.py:305)
- [`create_auth_file()`](installerNetworkValidation.py:343)
- [`validate_json_file()`](installerNetworkValidation.py:380)
- [`main()`](installerNetworkValidation.py:403)

## Summary

[`installerNetworkValidation.py`](installerNetworkValidation.py) is a guided pre-installation validation tool for HCI environments. It helps verify that the required registries, certificates, credentials, pull secrets, proxies, and external endpoints are accessible before proceeding with cluster installation.