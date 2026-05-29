# Deploying Red Hat OpenShift AI: A Complete Operator Installation Guide

**Transform Your Kubernetes Cluster into an Enterprise AI Platform in Minutes**

---

## Why This Matters: The AI Infrastructure Challenge

Imagine you're a platform engineer tasked with deploying AI/ML capabilities for your organization. Your data scientists need to serve large language models, your DevOps team needs reliable infrastructure, and your security team demands enterprise-grade controls. Manually installing and configuring each component could take weeks—and that's before you even deploy your first model.

**The reality**: Modern AI platforms require a complex orchestration of services:
- Model serving infrastructure with GPU support
- API gateways for rate limiting and traffic management  
- Certificate management for secure communications
- Distributed workload orchestration for training jobs
- Monitoring and observability tools

**The solution**: Automated operator deployment that transforms your OpenShift cluster into a production-ready AI platform in under 15 minutes.

### Who Should Read This

- **Platform Engineers** building AI/ML infrastructure
- **DevOps Teams** automating AI platform deployments
- **ML Engineers** needing self-service model deployment
- **Technical Leaders** evaluating OpenShift AI capabilities

### What You'll Learn

By the end of this guide, you'll be able to:
✅ Deploy OpenShift AI and all dependencies with a single Helm command  
✅ Understand the architecture and operator relationships  
✅ Validate your installation is production-ready  
✅ Troubleshoot common deployment issues  

**Time to complete**: 15-20 minutes  
**Prerequisites**: OpenShift 4.20+ cluster with cluster-admin access

---

## Table of Contents

1. [Understanding the Architecture](#understanding-the-architecture)
2. [What Gets Installed](#what-gets-installed)
3. [Quick Start Deployment](#quick-start-deployment)
4. [Validation and Verification](#validation-and-verification)
5. [Next Steps](#next-steps)
6. [Advanced Topics](#advanced-topics)
7. [Troubleshooting](#troubleshooting)

---

## Understanding the Architecture

### The Big Picture: How Operators Work Together

Think of operators as specialized automation agents that manage different aspects of your AI platform. Here's how they collaborate:

```
┌─────────────────────────────────────────────────────────────┐
│                    Your AI/ML Workloads                     │
│         (Model Serving, Training, Notebooks)                │
└─────────────────────────────────────────────────────────────┘
                              ↑
┌─────────────────────────────────────────────────────────────┐
│              Red Hat OpenShift AI Operator                  │
│         (Orchestrates AI/ML platform components)            │
└─────────────────────────────────────────────────────────────┘
                              ↑
        ┌─────────────────────┼─────────────────────┐
        ↓                     ↓                     ↓
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│  Kuadrant    │    │ Cert-Manager │    │ Leader-Worker│
│  (Gateway &  │    │   (TLS/SSL   │    │     Set      │
│ Rate Limit)  │    │ Certificates)│    │ (Distributed │
│              │    │              │    │  Workloads)  │
└──────────────┘    └──────────────┘    └──────────────┘
```

### The Deployment Flow (Simplified)

```
Step 1: Create Namespaces
   ↓
Step 2: Configure Operator Groups (defines scope)
   ↓
Step 3: Create Subscriptions (triggers installation)
   ↓
Step 4: OLM Installs Operators Automatically
   ↓
Step 5: Operators Deploy Their Components
   ↓
✅ Ready for AI/ML Workloads
```

**Key Insight**: The Operator Lifecycle Manager (OLM) handles all the complexity—dependency resolution, version management, and health monitoring. You just declare what you want, and OLM makes it happen.

---

## What Gets Installed

### The Complete Operator Stack

The `maas-operators` Helm chart installs **5 critical operators** that form your AI platform foundation:

| Operator | Purpose | Why You Need It |
|----------|---------|-----------------|
| **Red Hat OpenShift AI** | Core AI/ML platform | Model serving, notebooks, pipelines |
| **Kuadrant** | API Gateway & Rate Limiting | Protect model endpoints, manage traffic |
| **Cert-Manager** | Certificate Management | Secure HTTPS connections |
| **Leader Worker Set** | Distributed Workloads | Multi-GPU training, fault tolerance |
| **Grafana** (Optional) | Monitoring Dashboards | Observability and metrics |

### Resource Requirements

**Minimum cluster requirements**:
- OpenShift 4.20 or higher
- 3 worker nodes
- GPU nodes (optional, for model serving)

---

## Quick Start Deployment

### Prerequisites Check

Before you begin, verify your environment:

```bash
# 1. Verify cluster access
oc whoami
# Expected: Your username

# 2. Confirm cluster-admin permissions
oc auth can-i '*' '*' --all-namespaces
# Expected: yes

# 3. Check OpenShift version (4.20+ required)
oc version
# Expected: Server Version: 4.20.x or higher

# 4. Verify Helm is installed
helm version
# Expected: version.BuildInfo{Version:"v3.x.x"...}
```

### Deploy in 3 Simple Steps

#### Step 1: Review the Configuration (Optional)

```bash
# View what will be installed
cat quickstarts/model-as-a-service/deploy/maas-operators/values.yaml

# Preview the deployment (dry-run)
helm template maas-operators \
  quickstarts/model-as-a-service/deploy/maas-operators \
  --debug
```

#### Step 2: Deploy the Operators

```bash
# Deploy with default configuration
helm install maas-operators \
  quickstarts/model-as-a-service/deploy/maas-operators \
  --create-namespace \
  --wait \
  --timeout 15m
```

**What's happening behind the scenes**:
1. Helm creates 5 namespaces
2. Operator subscriptions are created
3. OLM downloads and installs operators
4. Operators deploy their components
5. Health checks verify everything is running

**Expected output**:
```
NAME: maas-operators
LAST DEPLOYED: [timestamp]
NAMESPACE: default
STATUS: deployed
REVISION: 1
```

#### Step 3: Monitor the Installation

Watch the operators come online:

```bash
# Watch operator installation progress
watch oc get csv -A

# Expected output (after 10-15 minutes):
# NAMESPACE                  NAME                          PHASE
# redhat-ods-operator        rhods-operator.3.3.1         Succeeded
# kuadrant-system            kuadrant-operator.v0.x.x     Succeeded
# cert-manager-operator      cert-manager-operator.v1.x   Succeeded
# openshift-lws-operator     leader-worker-set.v1.0.x     Succeeded
```

**Pro tip**: Press `Ctrl+C` to exit the watch command once all operators show "Succeeded".

---

## Validation and Verification

### Quick Health Check (2 Minutes)

Run these commands to verify your installation:

```bash
# 1. Check Helm release
helm list -A | grep maas-operators
# Expected: maas-operators    default    1    deployed

# 2. Verify all namespaces exist
oc get namespace | grep -E "redhat-ods-operator|kuadrant-system|cert-manager-operator|openshift-lws-operator"
# Expected: 4 namespaces in Active state

# 3. Confirm all operators are running
oc get csv -A | grep -E "rhods-operator|kuadrant|cert-manager|leader-worker"
# Expected: All in "Succeeded" phase

# 4. Check operator pods
oc get pods -n redhat-ods-operator
oc get pods -n kuadrant-system
oc get pods -n cert-manager-operator
oc get pods -n openshift-lws-operator
# Expected: All pods in Running state with READY 1/1 or 2/2
```

### Comprehensive Validation

For production deployments, run this complete validation:

```bash
# Create validation script
cat > validate-operators.sh << 'EOF'
#!/bin/bash
echo "=== Operator Installation Validation ==="

# Check namespaces
echo -e "\n1. Checking namespaces..."
for ns in redhat-ods-operator kuadrant-system cert-manager-operator openshift-lws-operator; do
  if oc get namespace $ns &>/dev/null; then
    echo "✅ Namespace $ns exists"
  else
    echo "❌ Namespace $ns missing"
  fi
done

# Check CSVs
echo -e "\n2. Checking ClusterServiceVersions..."
csv_count=$(oc get csv -A --no-headers 2>/dev/null | grep -E "rhods-operator|kuadrant|cert-manager|leader-worker" | grep Succeeded | wc -l)
if [ "$csv_count" -ge 4 ]; then
  echo "✅ All operators installed successfully ($csv_count/4)"
else
  echo "❌ Some operators failed to install ($csv_count/4)"
fi

# Check pods
echo -e "\n3. Checking operator pods..."
for ns in redhat-ods-operator kuadrant-system cert-manager-operator openshift-lws-operator; do
  pod_count=$(oc get pods -n $ns --no-headers 2>/dev/null | grep Running | wc -l)
  if [ "$pod_count" -gt 0 ]; then
    echo "✅ $ns: $pod_count pods running"
  else
    echo "❌ $ns: No pods running"
  fi
done

echo -e "\n=== Validation Complete ==="
EOF

chmod +x validate-operators.sh
./validate-operators.sh
```

### Success Criteria

Your installation is successful when:
- ✅ All 4 namespaces are Active
- ✅ All CSVs show "Succeeded" phase
- ✅ All operator pods are Running
- ✅ No CrashLoopBackOff or Error states

**If you see any issues**, jump to the [Troubleshooting](#troubleshooting) section below.

---

## Next Steps

### 🎉 Congratulations! Your AI Platform Foundation is Ready

You've successfully deployed the operator foundation. Here's what to do next:

### Immediate Next Steps (Choose Your Path)

**Path 1: Deploy Your First AI Model** (Recommended for beginners)
```bash
# Install the platform components
helm install maas-platform \
  quickstarts/model-as-a-service/deploy/maas-platform

# Deploy a sample model
helm install granite-model \
  quickstarts/model-as-a-service/deploy/maas-model-service \
  -f quickstarts/model-as-a-service/examples/model-registry-deployment/granite-3.1-8b-instruct-values.yaml
```

**Path 2: Configure the Platform** (For production deployments)
- Set up model registry for versioning
- Configure monitoring and alerting
- Implement rate limiting policies
- Set up workbench storage for data scientists

**Path 3: Explore Advanced Features**
- Multi-tenancy configuration
- Custom operator channels
- GitOps integration with ArgoCD
- GPU resource management

### Learning Resources

📚 **Continue the Series**:
- **Part 2**: [Customizing Your OpenShift AI Deployment](MAAS_PLATFORM_CUSTOMIZATION_GUIDE.md)
- **Part 3**: [Deploying and Managing AI Models](../03-model-deployment/DEPLOYING_MODEL_SERVICES.md)
- **Part 4**: Production Best Practices and Troubleshooting

🔗 **Related Guides**:
- [Getting Started Guide](../GETTING_STARTED.md) - Complete platform overview
- [Model Registry Guide](../02-model-catalog-and-registry/ADDING_MODELS_TO_REGISTRY.md) - Version control for models
- [Deployment Order](DEPLOYMENT_ORDER.md) - Understanding the full stack

### Join the Community

- **Questions?** Open an issue in the repository
- **Success story?** Share your deployment experience
- **Improvements?** Contribute back to the project

---

## Advanced Topics

### Helm Chart Details

**Chart Location:** `quickstarts/model-as-a-service/deploy/maas-operators/`

**Configuration:** Defined in [deploy/maas-operators/values.yaml](../deploy/maas-operators/values.yaml)

**Purpose:**
- Installs Red Hat OpenShift AI operator and its dependencies
- Creates required namespaces and operator groups
- Manages operator subscriptions and update channels
- Provides foundation for the MaaS platform

**Dependencies:**
This chart must be installed **first** before deploying other MaaS components:
```text
maas-operators (install first)
    ↓
maas-platform (requires operators)
    ↓
maas-runtime (requires platform)
    ↓
maas-model-service (requires runtime)
```

### Detailed Architecture

#### Operator Deployment Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ Step 1: Namespace Creation                                      │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ • redhat-ods-operator                                       │ │
│ │ • cert-manager-operator                                     │ │
│ │ • kuadrant-system                                           │ │
│ │ • openshift-lws-operator                                    │ │
│ └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Step 2: OperatorGroup Creation                                  │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ • Defines operator scope (namespace/cluster-wide)           │ │
│ │ • Configures target namespaces                              │ │
│ │ • Sets up RBAC for operators                                │ │
│ └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Step 3: Subscription Creation                                   │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ • Subscribes to operator catalogs                           │ │
│ │ • Specifies update channels                                 │ │
│ │ • Configures install plan approval                          │ │
│ │ • Triggers operator installation                            │ │
│ └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ Step 4: Operator Installation (Automatic)                       │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ • OLM resolves dependencies                                 │ │
│ │ • Creates ClusterServiceVersion (CSV)                       │ │
│ │ • Deploys operator pods                                     │ │
│ │ • Installs CRDs                                             │ │
│ └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

#### Component Relationships

```
maas-operators Chart
├── Namespaces (templates/namespaces.yaml)
│   ├── redhat-ods-operator
│   ├── cert-manager-operator
│   ├── kuadrant-system
│   └── openshift-lws-operator
│
├── OperatorGroups (templates/operatorgroups.yaml)
│   ├── rhoai3-operatorgroup (cluster-scoped)
│   ├── cert-manager-operator-og (namespace-scoped)
│   ├── kuadrant-operator-group (cluster-scoped)
│   └── leader-worker-set (namespace-scoped)
│
└── Subscriptions (templates/subscriptions.yaml)
    ├── rhods-operator (OpenShift AI)
    ├── openshift-cert-manager-operator
    ├── rhcl-operator (Connectivity Link/Kuadrant)
    └── leader-worker-set
```

### Customization Guide

#### Common Customization Scenarios

##### 1. Change Operator Versions

**Use Case**: Pin to specific operator version for stability

```yaml
operators:
  openshiftAI:
    enabled: true
    channel: fast-3.x
    startingCSV: rhods-operator.3.3.0  # Pin to 3.3.0
    installPlanApproval: Manual        # Require manual approval for updates
```

**Verification**:
```bash
oc get csv -n redhat-ods-operator
```

##### 2. Disable Specific Operators

**Use Case**: Already have operators installed or don't need certain features

```yaml
operators:
  openshiftAI:
    enabled: true
  connectivityLink:
    enabled: false  # Disable Kuadrant
  certManager:
    enabled: false  # Already installed
  leaderWorkerSet:
    enabled: true
```

**Deployment**:
```bash
helm upgrade --install maas-operators \
  quickstarts/model-as-a-service/deploy/maas-operators \
  --set operators.connectivityLink.enabled=false \
  --set operators.certManager.enabled=false
```

##### 3. Change Update Channels

**Use Case**: Use stable vs. fast channels

```yaml
operators:
  openshiftAI:
    channel: stable-3.x  # Use stable channel instead of fast
```

**Available Channels**:
- OpenShift AI: `stable-3.x`, `fast-3.x`
- Cert-manager: `stable-v1`, `tech-preview`
- Kuadrant: `stable`, `preview`
- LWS: `stable-v1.0`

##### 4. Manual Update Approval

**Use Case**: Control when operators update

```yaml
operators:
  openshiftAI:
    installPlanApproval: Manual  # Require manual approval
```

**Approve Updates**:
```bash
# List pending install plans
oc get installplan -n redhat-ods-operator

# Approve install plan
oc patch installplan <install-plan-name> \
  -n redhat-ods-operator \
  --type merge \
  --patch '{"spec":{"approved":true}}'
```

---

## Troubleshooting

### Common Issues and Solutions

#### Issue 1: Subscription Stuck in "Installing" State

**Symptoms**:
```bash
oc get subscription -A
# NAMESPACE              NAME             PACKAGE          SOURCE             CHANNEL
# redhat-ods-operator    rhods-operator   rhods-operator   redhat-operators   fast-3.x   Installing
```

**Diagnosis**:
```bash
# Check subscription status
oc describe subscription rhods-operator -n redhat-ods-operator

# Check install plan
oc get installplan -n redhat-ods-operator

# Check catalog source
oc get catalogsource -n openshift-marketplace
```

**Solutions**:

1. **Wait for catalog sync**:
```bash
# Catalog sources may need time to sync
oc get catalogsource redhat-operators -n openshift-marketplace -o yaml | grep lastObservedTime
```

2. **Restart catalog pod**:
```bash
oc delete pod -n openshift-marketplace -l olm.catalogSource=redhat-operators
```

3. **Check install plan approval**:
```bash
# If manual approval required
oc get installplan -n redhat-ods-operator
oc patch installplan <install-plan-name> -n redhat-ods-operator \
  --type merge --patch '{"spec":{"approved":true}}'
```

#### Issue 2: CSV in "Failed" Phase

**Symptoms**:
```bash
oc get csv -n redhat-ods-operator
# NAME                    DISPLAY                  VERSION   REPLACES   PHASE
# rhods-operator.3.3.1    Red Hat OpenShift AI     3.3.1                Failed
```

**Diagnosis**:
```bash
# Check CSV status
oc describe csv rhods-operator.3.3.1 -n redhat-ods-operator

# Check operator pod logs
oc logs -n redhat-ods-operator -l name=rhods-operator
```

**Solutions**:

1. **Delete and recreate subscription**:
```bash
oc delete subscription rhods-operator -n redhat-ods-operator
oc delete csv rhods-operator.3.3.1 -n redhat-ods-operator
helm upgrade --install maas-operators quickstarts/model-as-a-service/deploy/maas-operators
```

2. **Check resource constraints**:
```bash
oc describe nodes | grep -A 5 "Allocated resources"
```

#### Issue 3: Operator Pod CrashLoopBackOff

**Symptoms**:
```bash
oc get pods -n redhat-ods-operator
# NAME                              READY   STATUS             RESTARTS   AGE
# rhods-operator-7d8f9c8b5d-xyz     0/1     CrashLoopBackOff   5          5m
```

**Diagnosis**:
```bash
# Check pod logs
oc logs -n redhat-ods-operator rhods-operator-7d8f9c8b5d-xyz

# Check pod events
oc describe pod -n redhat-ods-operator rhods-operator-7d8f9c8b5d-xyz

# Check resource limits
oc get pod -n redhat-ods-operator rhods-operator-7d8f9c8b5d-xyz -o yaml | grep -A 10 resources
```

**Solutions**:

1. **Check image pull**:
```bash
oc get events -n redhat-ods-operator | grep -i "pull"
```

2. **Verify RBAC**:
```bash
oc get clusterrolebinding | grep rhods
```

3. **Check webhook configuration**:
```bash
oc get validatingwebhookconfigurations
oc get mutatingwebhookconfigurations
```

### Debug Commands Reference

```bash
# Comprehensive debug information collection
mkdir -p debug-operators

# Helm release info
helm get all maas-operators > debug-operators/helm-release.yaml

# Namespaces
oc get namespace -o yaml > debug-operators/namespaces.yaml

# Subscriptions
oc get subscription -A -o yaml > debug-operators/subscriptions.yaml

# CSVs
oc get csv -A -o yaml > debug-operators/csvs.yaml

# Install plans
oc get installplan -A -o yaml > debug-operators/installplans.yaml

# Operator groups
oc get operatorgroup -A -o yaml > debug-operators/operatorgroups.yaml

# Pods
oc get pods -A -o yaml > debug-operators/pods.yaml

# Events
oc get events -A --sort-by='.lastTimestamp' > debug-operators/events.txt

# Logs
for ns in redhat-ods-operator kuadrant-system cert-manager-operator openshift-lws-operator; do
    oc logs -n $ns --all-containers=true --tail=1000 > debug-operators/logs-$ns.txt
done

# Create tarball
tar -czf debug-operators.tar.gz debug-operators/
```

---

## Summary

The `maas-operators` chart provides:

✅ **Automated operator installation** via OLM  
✅ **5 critical operators** for AI/ML platform  
✅ **Flexible configuration** via Helm values  
✅ **Comprehensive validation** tools  
✅ **Production-ready** deployment patterns  

### What We Covered

In this guide, you learned:
- Why operator-based deployment matters for AI platforms
- How OpenShift AI operators work together
- How to deploy the complete operator stack in minutes
- How to validate your installation
- Common troubleshooting techniques

### Your AI Journey Continues

This is just the beginning. With your operator foundation in place, you're ready to:
- Deploy production AI models
- Build data science workbenches
- Implement MLOps pipelines
- Scale to enterprise workloads

**Ready for the next step?** Check out [Part 2: Customizing Your OpenShift AI Deployment](MAAS_PLATFORM_CUSTOMIZATION_GUIDE.md) to configure your platform for production use.

