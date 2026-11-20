# MaaS Runtime (Deploy Once)

The `runtime` repository provides the foundational operators, platform infrastructure, networking, and registry services required to serve LLMs on OpenShift and IBM Storage Fusion.

---

## Architecture & Responsibilities

The runtime consists of four decoupled Helm charts deployed in strict wave ordering:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│  Phase 1: maas-operators                                                               │
│  RHOAI Operator, Kuadrant Operator, Authorino, Limitador, LeaderWorkerSet             │
├────────────────────────────────────────────────────────────────────────────────────────┤
│  Phase 2: maas-platform                                                                │
│  PostgreSQL Database (Model Registry backend), DataScienceCluster (default-dsc)        │
├────────────────────────────────────────────────────────────────────────────────────────┤
│  Phase 3: maas-runtime                                                                 │
│  Envoy Gateway (maas-default-gateway), Re-encrypt OpenShift Route, Authorino TLS Setup │
├────────────────────────────────────────────────────────────────────────────────────────┤
│  Phase 4: maas-model-registry                                                          │
│  Model Registry REST API Service & DB Schema Initialization                            │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Directory Structure

```
runtime/
├── README.md                          # Runtime operations guide
├── charts/                            # Reusable Helm charts (code/templates)
│   ├── maas-operators/                # Phase 1: Operator Subscriptions
│   ├── maas-platform/                 # Phase 2: DSC + PostgreSQL
│   ├── maas-runtime/                  # Phase 3: Gateway, TLS, OpenShift Route
│   └── maas-model-registry/           # Phase 4: Model Registry Service
├── config/                            # Environment-specific configuration
│   ├── helm/                          # Flattened per-environment values files
│   │   ├── dev/
│   │   ├── staging/
│   │   └── prod/
│   └── gitops/                        # ArgoCD AppProject and Application manifests
│       ├── dev/
│       ├── staging/
│       └── prod/
└── scripts/
    ├── install-runtime.sh             # Interactive / automated platform installer
    ├── cleanup-runtime.sh             # Platform teardown and resource wiper
    └── uninstall_rhoai.sh             # RHOAI-specific uninstaller
```

---

## Installation

### Option A: Using the Installer Script (Imperative / Helm)

```bash
cd runtime

# Deploy for production
./scripts/install-runtime.sh -e prod

# Deploy for development
./scripts/install-runtime.sh -e dev
```

### Option B: Using GitOps (ArgoCD)

Apply the AppProject and App-of-Apps for your environment:

```bash
oc apply -f config/gitops/prod/appproject.yaml
oc apply -f config/gitops/prod/app-of-apps.yaml
```

---

## Verification

```bash
# 1. Verify DataScienceCluster
oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}{"\n"}'
# Expected: Ready

# 2. Verify Kuadrant Gateway
oc get gateway maas-default-gateway -n openshift-ingress \
  -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}{"\n"}'
# Expected: True

# 3. Verify Authorino Auth Controller
oc get authorino authorino -n openshift-operators -o jsonpath='{.status.ready}{"\n"}'
# Expected: true
```
