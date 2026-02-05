# Configuring File Level Security for IBM Fusion Content-aware Storage (CAS)

This repository contains scripts and configuration manifests used to **enable or disable File Level Security (FLS)** for **IBM Fusion Content-aware Storage (CAS)** deployments running on **Red Hat OpenShift Container Platform**.

The artifacts provided here are intended for **cluster administrators and platform operators** responsible for managing CAS security and access controls.

---

## Overview

File Level Security in CAS enables enforcement of access control lists (ACLs) at the file level. Enabling this capability requires:

- Additional Linux capabilities (`SETUID`, `SETGID`) for specific CAS components
- Updates to CAS configuration
- Restart of dependent CAS services

This repository provides:
- A shell script to manage File Level Security configuration
- An OpenShift YAML manifest to configure required security permissions and role bindings

---

## Repository Contents

### `configure-file-security.sh`

A shell script that enables or disables File Level Security for CAS by:
- Updating the `cas-config` ConfigMap
- Restarting dependent CAS deployments
- Verifying whether ACL support is active in Document Processor pods

---

### `acl-checker-security.yaml`

An OpenShift manifest that defines:
- A custom **SecurityContextConstraints (SCC)** allowing `SETUID` and `SETGID` capabilities
- An RBAC **Role** granting permission to use the SCC
- A **RoleBinding** associating the role with the CAS operator service account

> **Important:** Applying this manifest requires **cluster-admin privileges**.

---

## Supported Environment

- IBM Fusion Content-aware Storage (CAS)
- Red Hat OpenShift Container Platform
- OpenShift CLI (`oc`) installed and configured

---

## Prerequisites

Before proceeding, ensure the following conditions are met:

- CAS is installed and operational
- You are logged in to the OpenShift cluster:
  ```bash
  oc login
