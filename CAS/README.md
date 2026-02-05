# IBM Content Aware Storage (CAS)

## Automation, Configuration, and Management Repository

This repository provides a **curated set of automation scripts, tools, and configuration assets** for deploying, configuring, operating, securing, and decommissioning **IBM Fusion Content‑aware Storage (CAS)** on **Red Hat OpenShift Container Platform**.

The contents are intended to support **enterprise-grade CAS deployments**, following controlled, repeatable, and operationally safe practices aligned with IBM product usage guidelines.

---

## Repository Structure

```
.
├── CAS-cleanup/
├── CAS-resource-configuration/
├── CAS-cli-chatbot/
├── File-security/
├── local-data-caching/
```

Each directory addresses a specific phase or capability within the CAS lifecycle.

---

## CAS-cleanup

### IBM CAS Cleanup (Customer‑Safe)

This directory contains a **customer‑safe cleanup utility** for uninstalling **IBM Cloud Application Services (CAS)** from an OpenShift cluster.

**Overview**
The `customer_cas_cleanup.sh` script provides a **controlled and interactive mechanism** for CAS removal. It is designed to minimize operational risk and prevent unintended data loss during decommissioning activities.

**Key Characteristics**

* Interactive execution with explicit user confirmations
* Non‑destructive by default
* Suitable for customer and production environments
* Focused on safe and predictable cleanup behavior

**Typical Use Cases**

* CAS decommissioning
* Environment reinitialization prior to redeployment
* Controlled cleanup during customer off‑boarding

---

## CAS-resource-configuration

### CAS Resource Configuration Automation

This directory provides automation for **configuring core CAS resources** on OpenShift in a consistent and repeatable manner.

**Capabilities**

* Authenticates to the OpenShift cluster
* Creates CAS **DataSources**, including:

  * IBM Storage Scale
  * AWS S3
* Creates **Domains** and associates DataSources
* Creates **DocumentProcessors**, including:

  * NVIDIA multimodal processors
  * Docling multimodal processors
* Performs validation of resource creation

**Intended Usage**

* Initial CAS environment setup
* Standardized provisioning across environments
* Automation-driven and CI/CD-based deployments

---

## CAS-cli-chatbot

### CAS Chatbot – Enterprise Edition v2.0.0

This directory contains an **enterprise-grade CLI application** for administering and interacting with CAS environments.

**Key Features**

* Command-line management of CAS resources and domains
* Multi-provider Large Language Model (LLM) integration
* User and access administration
* Support for both interactive and scripted workflows

**Intended Usage**

* Operational administration of CAS
* Advanced automation and assisted workflows
* Enterprise-scale CAS management

---

## File-security

### File Level Security for IBM Fusion CAS

This directory contains scripts and Kubernetes manifests used to **enable or disable File Level Security (FLS)** for CAS deployments on OpenShift.

**Overview**

* Implements granular file-level access controls
* Supports security and compliance requirements
* Intended for controlled execution by administrators

**Target Audience**

* OpenShift cluster administrators
* Platform and security operators
* Teams responsible for governance and compliance

---

## local-data-caching

### Local Data Caching for Content‑aware Storage (CAS)

This directory provides tooling to enable **local caching of remote S3 data** for ingestion by CAS.

**Architecture Summary**

* Deploys IBM Fusion services to support local caching
* Utilizes **IBM Storage Scale Container Native** on OpenShift
* Uses **Data Foundation (DF) RBD volumes** as backing storage
* Improves ingestion performance and reduces network latency

**Compatibility**

* IBM Fusion SDS 2.12
* IBM Fusion HCI 2.12

**Intended Usage**

* Hybrid and remote data ingestion scenarios
* Performance-sensitive CAS workloads
* Reduced dependency on remote object storage latency

---

## Intended Audience

This repository is intended for:

* Platform and DevOps Engineers
* Red Hat OpenShift Cluster Administrators
* IBM Fusion and CAS Operators
* Enterprise Architecture and Security Teams

---

## Operational Guidance

* Review all scripts prior to execution in production environments
* Ensure appropriate cluster privileges are available
* Validate CAS and Fusion version compatibility
* Follow organizational change management and backup procedures

---

## Disclaimer

These artifacts are provided as **operational automation utilities** for IBM Content Aware Storage.
Users are responsible for validating behavior within their own clusters and environments prior to production use.
