# HCI Installer Network Validation Tool - Flow Document

## Overview
**Script Name:** `installerNetworkValidation_new.py`  
**Purpose:** Interactive validation tool for HCI (Hybrid Cloud Infrastructure) installer network configuration  
**Version:** 1.0  
**Log File:** `installer_validation.log`

---

## Table of Contents
1. [Script Architecture](#script-architecture)
2. [Main Flow Diagram](#main-flow-diagram)
3. [Detailed Flow Paths](#detailed-flow-paths)
4. [Function Reference](#function-reference)
5. [Validation Checklist](#validation-checklist)
6. [Exit Points](#exit-points)

---

## Script Architecture

### Core Components

```
installerNetworkValidation_new.py
│
├── Logging Setup (Lines 23-48)
│   └── Logs to: installer_validation.log
│
├── Helper Functions (Lines 50-137)
│   ├── check_exit_command()
│   ├── get_user_input()
│   ├── get_password_input()
│   └── get_choice_input()
│
├── Validation Functions (Lines 139-397)
│   ├── check_registry_reachability()
│   ├── podman_login_test()
│   ├── podman_pull_test()
│   ├── validate_file_path()
│   ├── validate_certificate()
│   ├── check_site_reachability()
│   ├── create_auth_file()
│   └── validate_json_file()
│
└── Main Program (Lines 399-839)
    └── main() - Entry point
```

---

## Main Flow Diagram


```
START
  │
  ├─► Welcome Message & Instructions
  │
  ├─► Step 1: Get Cluster Name
  │
  ├─► Step 2: Get Base Domain
  │
  ├─► Step 3: Choose Installation Type
  │         │
  │         ├─────────────────┬─────────────────┐
  │         │                 │                 │
  │    [1] Airgap        [2] Connected         │
  │         │                 │                 │
  │         ▼                 ▼                 │
  │   ┌─────────┐      ┌──────────┐           │
  │   │ Airgap  │      │Connected │           │
  │   │  Flow   │      │   Flow   │           │
  │   └─────────┘      └──────────┘           │
  │         │                 │                 │
  │         └─────────┬───────┘                │
  │                   ▼                         │
  │            Validation Complete             │
  │                   │                         │
  └───────────────────┴─────────────────────► END
```

---

## Detailed Flow Paths

### 1. Initial Setup (Common for All Paths)

```
┌─────────────────────────────────────────┐
│ 1. Display Welcome Message              │
│    - Script purpose                     │
│    - Instructions                       │
│    - Exit command info                  │
│    - Log file location                  │
└─────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│ 2. Get Cluster Name                     │
│    Input: Cluster name                  │
│    Validation: Non-empty                │
└─────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│ 3. Get Base Domain                      │
│    Input: Base domain                   │
│    Validation: Non-empty                │
└─────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│ 4. Choose Installation Type             │
│    Options:                             │
│    [1] Airgap Install (Offline)         │
│    [2] Connected Install (Online)       │
└─────────────────────────────────────────┘
                  │
        ┌─────────┴─────────┐
        │                   │
    [1] Airgap        [2] Connected
        │                   │
        ▼                   ▼
```

---

### 2. Airgap Installation Flow

```
┌──────────────────────────────────────────────────────────┐
│                    AIRGAP INSTALL PATH                   │
└──────────────────────────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────┐
│ Choose Registry Configuration                            │
│ [1] Single Registry (One for all)                        │
│ [2] Multiple Registries (Separate for OS & Fusion)       │
└──────────────────────────────────────────────────────────┘
                          │
            ┌─────────────┴─────────────┐
            │                           │
    [1] Single Registry        [2] Multiple Registries
            │                           │
            ▼                           ▼
```

#### 2.1 Single Registry Path

```
┌─────────────────────────────────────────┐
│ Single Registry Configuration           │
├─────────────────────────────────────────┤
│ 1. Get Registry URL                     │
│    Input: Registry URL                  │
│    Example: registry.example.com:5000   │
├─────────────────────────────────────────┤
│ 2. Get Registry Username                │
│    Input: Username                      │
├─────────────────────────────────────────┤
│ 3. Get Registry Password                │
│    Input: Password (hidden)             │
│    Logged as: XXXXXXXXX                 │
└─────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│ Validation Steps                        │
├─────────────────────────────────────────┤
│ ✓ Check Registry Reachability           │
│   - Socket connection test              │
│   - Port: 443 (default) or specified    │
├─────────────────────────────────────────┤
│ ✓ Test Podman Login                     │
│   - Command: podman login               │
│   - Auto logout after test              │
├─────────────────────────────────────────┤
│ ✓ Test Image Pull                       │
│   - Image: openshift/release:latest     │
│   - Auto cleanup after test             │
└─────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│ Certificate Configuration               │
│ [1] Yes - Certificate will be used      │
│ [2] No - No certificate                 │
└─────────────────────────────────────────┘
                  │
            [1] Yes │
                  ▼
┌─────────────────────────────────────────┐
│ Certificate Validation                  │
├─────────────────────────────────────────┤
│ 1. Get Certificate File Path            │
│    Input: /path/to/cert.pem             │
├─────────────────────────────────────────┤
│ 2. Validate File Exists                 │
│    Check: File readable                 │
├─────────────────────────────────────────┤
│ 3. Validate Certificate                 │
│    - Check validity (openssl)           │
│    - Check expiration date              │
│    - Check if self-signed               │
└─────────────────────────────────────────┘
                  │
                  ▼
            [COMPLETE]
```

#### 2.2 Multiple Registries Path

```
┌─────────────────────────────────────────┐
│ Multiple Registries Configuration       │
└─────────────────────────────────────────┘
                  │
        ┌─────────┴─────────┐
        │                   │
        ▼                   ▼
┌──────────────┐    ┌──────────────┐
│  OpenShift   │    │   Fusion     │
│  Registry    │    │   Registry   │
└──────────────┘    └──────────────┘

For EACH Registry:
┌─────────────────────────────────────────┐
│ 1. Get Registry URL                     │
│ 2. Get Username                         │
│ 3. Get Password (hidden)                │
├─────────────────────────────────────────┤
│ Validations:                            │
│ ✓ Check Reachability                    │
│ ✓ Test Podman Login                     │
│ ✓ Test Image Pull                       │
│   - OpenShift: openshift/release:latest │
│   - Fusion: fusion/catalog:latest       │
├─────────────────────────────────────────┤
│ Certificate (Optional):                 │
│ [1] Yes - Provide cert path & validate  │
│ [2] No - Skip certificate               │
└─────────────────────────────────────────┘
                  │
                  ▼
            [COMPLETE]
```

---

### 3. Connected Installation Flow

```
┌──────────────────────────────────────────────────────────┐
│                  CONNECTED INSTALL PATH                  │
└──────────────────────────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────┐
│ Proxy Configuration                                      │
│ [1] With Proxy                                           │
│ [2] Without Proxy                                        │
└──────────────────────────────────────────────────────────┘
                          │
            ┌─────────────┴─────────────┐
            │                           │
    [1] With Proxy            [2] Without Proxy
            │                           │
            ▼                           ▼
```

#### 3.1 Connected WITH Proxy Path

```
┌─────────────────────────────────────────┐
│ Proxy Type Selection                    │
│ [1] Authenticated Proxy                 │
│ [2] Unauthenticated Proxy               │
└─────────────────────────────────────────┘
                  │
        ┌─────────┴─────────┐
        │                   │
   [1] Auth          [2] Unauth
        │                   │
        ▼                   ▼
┌──────────────┐    ┌──────────────┐
│ Get Proxy    │    │ Get Proxy    │
│ Server       │    │ Server       │
│ Username     │    │ (No Auth)    │
│ Password     │    │              │
└──────────────┘    └──────────────┘
        │                   │
        └─────────┬─────────┘
                  ▼
┌─────────────────────────────────────────┐
│ Deployment Characteristics              │
├─────────────────────────────────────────┤
│ 1. GPU Nodes?                           │
│    [1] Yes  [2] No                      │
├─────────────────────────────────────────┤
│ 2. China Region?                        │
│    [1] Yes  [2] No                      │
├─────────────────────────────────────────┤
│ 3. Metro DR?                            │
│    [1] Yes  [2] No                      │
├─────────────────────────────────────────┤
│ 4. Call Home?                           │
│    [1] Yes  [2] No                      │
├─────────────────────────────────────────┤
│ 5. Remote Support?                      │
│    [1] Yes  [2] No                      │
└─────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│ Site Reachability Validation            │
│ (All via Proxy)                         │
├─────────────────────────────────────────┤
│ BASE SITES (Always Checked):            │
│ ✓ icr.io, cp.icr.io, dd0.icr.io        │
│ ✓ registry.redhat.io, redhat.com       │
│ ✓ quay.io, cdn.quay.io, cdn0*.quay.io  │
│ ✓ docker.com, docker.io, ghcr.io       │
│ ✓ console.redhat.com, cloud.redhat.com │
│ ✓ api.openshift.com, mirror.openshift  │
│ ✓ storage.googleapis.com                │
│ ✓ Cluster-specific URLs:                │
│   - oauth-openshift.apps.<cluster>     │
│   - console-openshift-console.apps     │
│   - canary-openshift-ingress-canary    │
└─────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│ CONDITIONAL SITES:                      │
├─────────────────────────────────────────┤
│ IF GPU = Yes:                           │
│ ✓ cloud.openshift.com                   │
│ ✓ nvcr.io, containers.nvcr.io          │
│ ✓ api.ngc.nvidia.com                    │
│ ✓ catalog.ngc.nvidia.com                │
├─────────────────────────────────────────┤
│ IF China = Yes:                         │
│ ✓ dd1-icr.ibm-zh.com                    │
│ ✓ dd3-icr.ibm-zh.com                    │
├─────────────────────────────────────────┤
│ IF Metro DR = Yes:                      │
│ ✓ gcr.io                                │
├─────────────────────────────────────────┤
│ IF Call Home = Yes:                     │
│ ✓ www.ecurep.ibm.com                    │
│ ✓ esupport.ibm.com                      │
├─────────────────────────────────────────┤
│ IF Remote Support = Yes:                │
│ ✓ aosrelay1.us.ihost.com                │
│ ✓ aosback.us.ihost.com                  │
│ ✓ aoshats.us.ihost.com                  │
└─────────────────────────────────────────┘
                  │
                  ▼
            [COMPLETE]
```

#### 3.2 Connected WITHOUT Proxy Path

```
┌─────────────────────────────────────────┐
│ IBM Entitlement & Pull Secret           │
├─────────────────────────────────────────┤
│ 1. Get IBM Entitlement Key              │
│    Input: Key (hidden)                  │
│    Logged as: XXXXXXXXX                 │
├─────────────────────────────────────────┤
│ 2. Get Pull Secret Path                 │
│    Input: /path/to/pull-secret.json     │
├─────────────────────────────────────────┤
│ 3. Validate Pull Secret File            │
│    ✓ File exists                        │
│    ✓ Valid JSON format                  │
└─────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│ Create Authentication File              │
├─────────────────────────────────────────┤
│ Process:                                │
│ 1. Read pull-secret.json                │
│ 2. Add cp.icr.io authentication         │
│    - Encode: cp:<entitlement_key>       │
│    - Base64 encoding                    │
│ 3. Write to: authfile.json              │
└─────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│ Registry Validation                     │
├─────────────────────────────────────────┤
│ Check Reachability for:                 │
│ ✓ cp.icr.io                             │
│ ✓ registry.redhat.io                    │
│ ✓ gcr.io                                │
│ ✓ quay.io                               │
│ ✓ registry.access.redhat.com            │
└─────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│ Test Image Pull                         │
├─────────────────────────────────────────┤
│ Image: cp.icr.io/cp/isf/                │
│        isf-validate-entitlement@sha256  │
│ Purpose: Validate entitlement key       │
└─────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│ Ingress Certificate (Optional)          │
│ [1] Yes - Certificate will be used      │
│ [2] No - No certificate                 │
└─────────────────────────────────────────┘
                  │
            [1] Yes │
                  ▼
┌─────────────────────────────────────────┐
│ Ingress Certificate Validation          │
├─────────────────────────────────────────┤
│ 1. Get Certificate File Path            │
│    Input: /path/to/ingress-cert.pem     │
├─────────────────────────────────────────┤
│ 2. Get Certificate Key Path             │
│    Input: /path/to/ingress-key.pem      │
├─────────────────────────────────────────┤
│ 3. Validate Certificate File            │
│    ✓ File exists                        │
│    ✓ Valid certificate                  │
│    ✓ Check expiration                   │
│    ✓ Check if self-signed               │
├─────────────────────────────────────────┤
│ 4. Validate Key File                    │
│    ✓ File exists                        │
│    ✓ File readable                      │
└─────────────────────────────────────────┘
                  │
                  ▼
            [COMPLETE]
```

---

## Function Reference

### Helper Functions

#### 1. `check_exit_command(user_input)`
**Purpose:** Check if user wants to exit  
**Input:** User's input string  
**Action:** If input is "I want to exit", program exits gracefully  
**Location:** Lines 54-62

#### 2. `get_user_input(prompt_message, allow_empty=False)`
**Purpose:** Get validated input from user  
**Input:** 
- `prompt_message`: Message to display
- `allow_empty`: Whether empty input is allowed (default: False)

**Returns:** User's input as string  
**Validation:** 
- Non-empty (unless allow_empty=True)
- Checks for exit command
- Loops until valid input received

**Location:** Lines 64-85

#### 3. `get_password_input(prompt_message)`
**Purpose:** Get password with hidden input  
**Input:** Prompt message  
**Returns:** Password as string  
**Features:**
- Password hidden on screen (using getpass)
- Logged as "XXXXXXXXX"
- Checks for exit command
- Validates non-empty

**Location:** Lines 87-107

#### 4. `get_choice_input(prompt_message, valid_choices)`
**Purpose:** Get user choice from valid options  
**Input:**
- `prompt_message`: Message to display
- `valid_choices`: List of valid options (e.g., ['1', '2'])

**Returns:** User's choice as string  
**Validation:**
- Non-empty
- Must be in valid_choices list
- Checks for exit command

**Location:** Lines 109-137

---

### Validation Functions

#### 5. `check_registry_reachability(registry_url)`
**Purpose:** Test if registry is reachable  
**Method:** Socket connection test  
**Input:** Registry URL (e.g., "registry.example.com:5000")  
**Returns:** True if reachable, False otherwise  
**Process:**
1. Parse URL (remove protocol, extract host/port)
2. Create socket connection
3. Test connection with 5-second timeout
4. Log result

**Location:** Lines 143-177

#### 6. `podman_login_test(registry_url, username, password)`
**Purpose:** Test podman login to registry  
**Method:** Execute podman login command  
**Input:**
- `registry_url`: Registry URL
- `username`: Registry username
- `password`: Registry password (logged as XXXXXXXXX)

**Returns:** True if login successful, False otherwise  
**Process:**
1. Execute: `echo 'password' | podman login -u 'username' --password-stdin registry`
2. Check return code
3. Auto logout after test
4. Log result

**Location:** Lines 179-207

#### 7. `podman_pull_test(registry_url, username, password, image_name)`
**Purpose:** Test pulling image from registry  
**Method:** Execute podman pull command  
**Input:**
- `registry_url`: Registry URL
- `username`: Registry username
- `password`: Registry password
- `image_name`: Image to pull (e.g., "openshift/release:latest")

**Returns:** True if pull successful, False otherwise  
**Process:**
1. Login to registry
2. Pull image: `podman pull registry/image_name`
3. Logout from registry
4. Remove pulled image (cleanup)
5. Log result

**Location:** Lines 209-244

#### 8. `validate_file_path(file_path)`
**Purpose:** Check if file exists and is readable  
**Input:** File path  
**Returns:** True if file exists and readable, False otherwise  
**Location:** Lines 246-258

#### 9. `validate_certificate(cert_path)`
**Purpose:** Validate SSL/TLS certificate  
**Method:** Use openssl commands  
**Input:** Certificate file path  
**Returns:** True if valid, False otherwise  
**Checks:**
1. File exists and readable
2. Certificate validity: `openssl x509 -in cert -noout -text`
3. Expiration date: `openssl x509 -in cert -noout -enddate`
4. Self-signed check: Compare issuer and subject

**Location:** Lines 260-303

#### 10. `check_site_reachability(site_url, proxy_server, proxy_username, proxy_password)`
**Purpose:** Check if website/URL is reachable  
**Method:** Use curl command  
**Input:**
- `site_url`: URL to check
- `proxy_server`: Proxy server (optional)
- `proxy_username`: Proxy username (optional)
- `proxy_password`: Proxy password (optional, logged as XXXXXXXXX)

**Returns:** True if reachable, False otherwise  
**Process:**
1. Build curl command with/without proxy
2. Execute: `curl -I --max-time 10 https://site_url`
3. Check for HTTP response codes (200, 301, 302, 401, 403)
4. Log result

**Location:** Lines 305-341

#### 11. `create_auth_file(pull_secret_path, ibm_entitlement_key, output_path)`
**Purpose:** Create authentication file for registries  
**Method:** Combine pull-secret with IBM entitlement  
**Input:**
- `pull_secret_path`: Path to pull-secret.json
- `ibm_entitlement_key`: IBM entitlement key (logged as XXXXXXXXX)
- `output_path`: Output file path (default: "authfile.json")

**Returns:** True if successful, False otherwise  
**Process:**
1. Read pull-secret.json
2. Encode credentials: `base64(cp:entitlement_key)`
3. Add cp.icr.io authentication to auths
4. Write to authfile.json

**Location:** Lines 343-378

#### 12. `validate_json_file(file_path)`
**Purpose:** Validate JSON file format  
**Input:** File path  
**Returns:** True if valid JSON, False otherwise  
**Location:** Lines 380-397

---

## Validation Checklist

### Airgap Installation - Single Registry
- [ ] Registry URL provided
- [ ] Registry username provided
- [ ] Registry password provided
- [ ] Registry reachability confirmed
- [ ] Podman login successful
- [ ] Image pull test successful
- [ ] Certificate validated (if used)

### Airgap Installation - Multiple Registries
**OpenShift Registry:**
- [ ] Registry URL provided
- [ ] Username provided
- [ ] Password provided
- [ ] Reachability confirmed
- [ ] Podman login successful
- [ ] Image pull test successful
- [ ] Certificate validated (if used)

**Fusion Registry:**
- [ ] Registry URL provided
- [ ] Username provided
- [ ] Password provided
- [ ] Reachability confirmed
- [ ] Podman login successful
- [ ] Image pull test successful
- [ ] Certificate validated (if used)

### Connected Installation - With Proxy
- [ ] Proxy server configured
- [ ] Proxy authentication (if required)
- [ ] Base sites reachability (30+ sites)
- [ ] GPU sites (if GPU nodes)
- [ ] China sites (if China region)
- [ ] Metro DR sites (if Metro DR)
- [ ] Call Home sites (if configured)
- [ ] Remote Support sites (if configured)

### Connected Installation - Without Proxy
- [ ] IBM entitlement key provided
- [ ] Pull-secret.json validated
- [ ] Auth file created
- [ ] Registry reachability (5 registries)
- [ ] Image pull test successful
- [ ] Ingress certificate validated (if used)

---

## Exit Points

### User-Initiated Exit
**Command:** Type "I want to exit" at any prompt  
**Action:** Graceful exit with goodbye message  
**Logged:** "User requested to exit by saying: I want to exit"

### Keyboard Interrupt (Ctrl+C)
**Action:** Catch KeyboardInterrupt exception  
**Message:** "Program interrupted by user (Ctrl+C)"  
**Logged:** Warning level

### Unexpected Error
**Action:** Catch all exceptions  
**Message:** Display error details  
**Logged:** Error level with full traceback  
**Exit Code:** 1

### Normal Completion
**Action:** Display completion message  
**Message:** "Validation Complete!"  
**Logged:** "HCI Installer Network Validation Script Completed Successfully"  
**Exit Code:** 0

---

## Logging Details

### Log File
**Name:** `installer_validation.log`  
**Format:** `timestamp - level - message`  
**Levels:** INFO, WARNING, ERROR

### What Gets Logged
✓ All user inputs (except passwords)  
✓ All validation results (success/failure)  
✓ All function calls with parameters  
✓ All error messages with details  
✓ Program start and completion  
✗ Passwords (logged as "XXXXXXXXX")

### Log Examples
```
2026-03-08 16:45:23 - INFO - HCI Installer Network Validation Script Started
2026-03-08 16:45:30 - INFO - Cluster Name: prod-cluster
2026-03-08 16:45:35 - INFO - Base Domain: example.com
2026-03-08 16:45:40 - INFO - Installation Type: Airgap Install (Offline)
2026-03-08 16:45:50 - INFO - Registry Username: admin
2026-03-08 16:45:52 - INFO - Password entered: XXXXXXXXX
2026-03-08 16:45:55 - INFO - ✓ SUCCESS: Registry registry.example.com:5000 is reachable
2026-03-08 16:46:00 - INFO - ✓ SUCCESS: Podman login to registry.example.com:5000 successful
2026-03-08 16:46:10 - ERROR - ✗ FAILURE: Image pull from registry.example.com:5000 failed
```

---

## Best Practices for Users

### Before Running
1. Ensure `podman` is installed and configured
2. Ensure `openssl` is available for certificate validation
3. Ensure `curl` is available for site reachability checks
4. Have all required information ready:
   - Registry URLs and credentials
   - Certificate file paths
   - IBM entitlement key
   - Pull-secret.json file

### During Execution
1. Answer each question carefully
2. Use "I want to exit" to exit gracefully at any time
3. Check log file for detailed results
4. Don't interrupt with Ctrl+C unless necessary

### After Completion
1. Review `installer_validation.log` for all results
2. Address any failed validations before installation
3. Keep log file for troubleshooting reference

---

## Troubleshooting

### Common Issues

**Issue:** Registry not reachable  
**Solution:** Check network connectivity, firewall rules, and registry URL

**Issue:** Podman login fails  
**Solution:** Verify username/password, check registry authentication settings

**Issue:** Image pull fails  
**Solution:** Verify image name exists in registry, check credentials

**Issue:** Certificate validation fails  
**Solution:** Check certificate file format, expiration date, and path

**Issue:** Site not reachable via proxy  
**Solution:** Verify proxy settings, authentication, and site URL

---

## Version History

**Version 1.0** (Current)
- Initial release
- Support for Airgap and Connected installations
- Single and multiple registry configurations
- Proxy support (authenticated and unauthenticated)
- Comprehensive site reachability checks
- Certificate validation
- IBM entitlement key validation
- Detailed logging

---

## Contact & Support

For issues or questions about this script:
1. Check the log file: `installer_validation.log`
2. Review this flow document
3. Contact your HCI administrator

---

**Document Version:** 1.0  
**Last Updated:** 2026-03-08  
**Script Version:** 1.0