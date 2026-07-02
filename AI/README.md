# Fusion Agentic Assistance Platform - Complete Deployment Guide

Enterprise RAG (Retrieval-Augmented Generation) platform with real-time progress tracking, source attribution, and intelligent document search powered by OpenShift AI and CAS.

## 🎯 **What This Platform Provides**

### **Technology Stack:**
- **OpenShift AI** - LLM serving infrastructure (KServe)
- **CAS (Content-Aware Storage)** - Enterprise vector store
- **ArgoCD** - GitOps continuous deployment
- **Streamlit** - Interactive chat UI
- **vLLM** - High-performance LLM inference
- **IBM Granite 3.1** - 2B parameter language model
## 🍴 **Fork and Use This Repository**

Since this is a shared/template repository, you should fork it to your own GitHub organization or account before deploying.

### **Quick Fork Guide:**

#### **Option 1: Fork via GitHub UI (Recommended)**

1. **Navigate to the repository:**
   ```
   https://github.ibm.com/ProjectAbell/Fusion-AI
   ```

2. **Click the "Fork" button** (top-right corner)

3. **Choose your destination:**
   - Select your personal account or organization
   - Optionally rename the repository
   - Click "Create fork"

4. **Clone your fork:**
   ```bash
   git clone https://github.ibm.com/YOUR_USERNAME/Fusion-AI.git
   cd Fusion-AI
   ```

#### **Option 2: Manual Fork via CLI**

```bash
# Clone the original repository
git clone https://github.ibm.com/ProjectAbell/Fusion-AI.git
cd Fusion-AI

# Remove original remote
git remote remove origin

# Create new repository in your GitHub account/org
# Then add your new repository as remote
git remote add origin https://github.ibm.com/YOUR_USERNAME/YOUR_REPO_NAME.git

# Push to your repository
git push -u origin main
```

### **Configure Repository in ArgoCD**

After forking, you'll configure your repository URL in ArgoCD (not in YAML files). This is done during deployment:

**Via ArgoCD UI:**
1. Login to ArgoCD: `https://<argocd-url>`
2. Go to **Settings** → **Repositories**
3. Click **Connect Repo**
4. Enter your forked repository URL: `https://github.com/YOUR_ORG/YOUR_REPO.git`
5. Add credentials (username/token)
6. Click **Connect**

**Via ArgoCD CLI:**
```bash
argocd repo add https://github.com/YOUR_ORG/YOUR_REPO.git \
  --username YOUR_GITHUB_USERNAME \
  --password YOUR_GITHUB_TOKEN
```

**Note:** The YAML files have `repoURL: ""` as a placeholder. ArgoCD will use the repository you configure in Settings.

### **Customize for Your Environment**

After forking, you should customize these files for your environment:

1. **`fusion-gitops-sample-app/config/config.yaml`**
   - Update CAS endpoint URL
   - Update model endpoint URL
   - Configure your specific settings

2. **`fusion-gitops-sample-app/gitops/applications/secrets.yaml`**
   - Add your CAS API key (base64 encoded)
   - Add any other required credentials

3. **`fusion-model-serving/gitops/models/kserve-model-serving.yaml`**
   - Adjust model resources (CPU, memory, GPU)
   - Configure storage settings
   - Update model path if using different model

4. **Container Image** (if building custom image)
   - Update image registry in `fusion-gitops-sample-app/gitops/applications/chat-app-deployment.yaml`
   - Build and push your custom image:
     ```bash
     cd fusion-gitops-sample-app
     docker build -t YOUR_REGISTRY/fusion-chat-app:latest -f Dockerfile.chat-app .
     docker push YOUR_REGISTRY/fusion-chat-app:latest
     ```

### **Why Fork?**

✅ **Customization** - Modify code and configs for your needs  
✅ **Version Control** - Track your changes separately  
✅ **GitOps** - ArgoCD monitors your repository for changes  
✅ **Collaboration** - Share with your team  
✅ **Updates** - Pull upstream changes when needed  

### **Keeping Your Fork Updated**

To sync with upstream changes:

```bash
# Add upstream remote (one time)
git remote add upstream https://github.ibm.com/ProjectAbell/Fusion-AI.git

# Fetch upstream changes
git fetch upstream

# Merge upstream changes
git checkout main
git merge upstream/main

# Push to your fork
git push origin main
```


## 📁 **Repository Structure**

```
|   bootstrap.yaml                          # 🚀 START HERE - Main bootstrap
│
├── fusion-gitops-argocd/                   # ArgoCD installation
│   └── argocd-install.yaml                 # OpenShift GitOps operator
│
├── fusion-gitops-sample-app/      # Main chat application
│   ├── chat_app.py                         # Enhanced Streamlit UI
│   ├── src/
│   │   ├── rag_flow.py                     # RAG orchestrator
│   │   ├── cas_client.py                   # CAS integration
│   │   └── monitoring.py                   # Monitoring service
│   ├── test_enhanced_features.py           # Test suite
│   ├── Dockerfile.chat-app                 # Container image
│   └── gitops/                             # GitOps manifests
│       ├── bootstrap.yaml                  # App bootstrap
│       ├── llmops-application.yaml         # ArgoCD apps
│       └── applications/                   # K8s resources
│
├── fusion-model-serving/                   # LLM model deployment
│   └── gitops/
│       └── models/
│           └── kserve-model-serving.yaml   # Granite LLM
│
├── fusion-openshift-ai/                    # OpenShift AI docs
│   └── docs/                               # (Documentation only)
│
└── FusionAIDataService/                    # CAS deployment guides
    └── docs/
```

## 🚀 **Complete End-to-End Deployment**

### **Prerequisites**

Before starting, ensure you have:

1. **OpenShift Cluster**
   - Version 4.12 or higher
   - Cluster admin access
   - GPU nodes (optional but recommended for LLM)

2. **Tools Installed**
   - `oc` CLI (OpenShift command-line)
   - `kubectl` (Kubernetes CLI)
   - `git` (for repository access)

3. **Access Requirements**
   - GitHub repository access (or your Git provider)
   - Container registry access (for chat app image)
   - CAS endpoint and API key

---

## 📋 **Step-by-Step Deployment**

### **STEP 1: Install OpenShift AI (Manual - One Time)**

OpenShift AI provides the infrastructure for model serving.

#### **Via OpenShift Console:**
```
1. Login to OpenShift Console
2. Navigate to: Operators → OperatorHub
3. Search for: "Red Hat OpenShift AI"
4. Click "Install"
5. Accept defaults and click "Install"
6. Wait for installation to complete (~5 minutes)
```

#### **Via CLI:**
```bash
# Create operator subscription
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rhods-operator
  namespace: redhat-ods-operator
spec:
  channel: stable
  name: rhods-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

# Wait for operator to be ready
oc get pods -n redhat-ods-operator -w
```

#### **Verify Installation:**
```bash
# Check operator is running
oc get csv -n redhat-ods-operator | grep rhods

# Check DataScienceCluster
oc get datasciencecluster

# Expected output: default-dsc should exist
```

---

### **STEP 2: Install ArgoCD (Manual - One Time)**

ArgoCD enables GitOps-based continuous deployment.

```bash
# Install OpenShift GitOps Operator
oc apply -f fusion-gitops-argocd/argocd-install.yaml

# Wait for ArgoCD to be ready (takes ~3-5 minutes)
oc get pods -n openshift-gitops -w

# Press Ctrl+C when all pods are Running
```

#### **Access ArgoCD UI:**
```bash
# Get ArgoCD URL
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'

# Get admin password
oc get secret openshift-gitops-cluster -n openshift-gitops \
  -o jsonpath='{.data.admin\.password}' | base64 -d && echo

# Login to ArgoCD UI with:
# Username: admin
# Password: (from above command)
```

---

### **STEP 3: Configure Git Repository (One Time)**

Update the bootstrap to point to your Git repository.

#### **Edit bootstrap.yaml:**
```bash
# Edit the bootstrap file
vi bootstrap.yaml

# Update line 14 with your repository URL:
# OLD: repoURL: https://github.ibm.com/ProjectAbell/Fusion-AI.git
# NEW: repoURL: https://github.com/YOUR-ORG/YOUR-REPO.git
```

#### **Configure Git Credentials (if private repo):**

**Via ArgoCD UI:**
```
1. Login to ArgoCD UI
2. Settings → Repositories
3. Click "Connect Repo"
4. Enter:
   - Repository URL: https://github.com/YOUR-ORG/YOUR-REPO.git
   - Username: your-username
   - Password: your-personal-access-token
5. Click "Connect"
```

**Via CLI:**
```bash
# Get ArgoCD admin password
ARGOCD_PASSWORD=$(oc get secret openshift-gitops-cluster -n openshift-gitops \
  -o jsonpath='{.data.admin\.password}' | base64 -d)

# Get ArgoCD URL
ARGOCD_URL=$(oc get route openshift-gitops-server -n openshift-gitops \
  -o jsonpath='{.spec.host}')

# Login to ArgoCD
argocd login $ARGOCD_URL --username admin --password $ARGOCD_PASSWORD --insecure

# Add repository
argocd repo add https://github.com/YOUR-ORG/YOUR-REPO.git \
  --username YOUR_USERNAME \
  --password YOUR_TOKEN
```

---

### **STEP 4: Build and Push Chat Application Image (One Time)**

The chat application needs to be containerized and pushed to a registry.

```bash
# Navigate to the app directory
cd fusion-gitops-sample-app

# Build the image (replace with your registry)
podman build --no-cache --platform linux/amd64 \
  -f Dockerfile.chat-app \
  -t YOUR-REGISTRY/YOUR-ORG/chat-app:latest .

# Push to registry
podman push YOUR-REGISTRY/YOUR-ORG/chat-app:latest

# Update the image reference in deployment
vi gitops/applications/chat-app-deployment.yaml
# Line 22: Update image to your registry URL
```

---

### **STEP 5: Configure Application Settings (One Time)**

Update configuration for your environment.

#### **Configure CAS Endpoint:**
```bash
# Edit ConfigMap
vi fusion-gitops-sample-app/gitops/applications/configmap.yaml

# Update:
# - cas-endpoint: "https://your-cas-endpoint.com"
# - cas-vector-store-id: "your-vector-store-id"
# - llm-endpoint: "http://granite-llm-predictor.default-dsc.svc.cluster.local:8080"
```

#### **Configure CAS API Key:**
```bash
# Edit Secrets
vi fusion-gitops-sample-app/gitops/applications/secrets.yaml

# Update:
# stringData:
#   cas-api-key: "your-actual-cas-api-key"
```

---

### **STEP 6: Deploy Everything via GitOps (Automated!)**

This is where the magic happens - one command deploys everything!

```bash
# Apply the bootstrap (from repository root)
oc apply -f bootstrap.yaml

# This triggers ArgoCD to deploy:
# 1. Model Serving (Granite LLM)
# 2. Chat Application
# 3. All configurations
```

#### **Monitor Deployment:**
```bash
# Watch ArgoCD applications
oc get applications -n openshift-gitops -w

# Expected applications:
# - fusion-agentic-assistance-bootstrap
# - fusion-agentic-assistance-platform
# - fusion-agentic-assistance-models

# Press Ctrl+C when all show "Synced" and "Healthy"
```

---

### **STEP 7: Verify Deployments**

Check that all components are running.

#### **Check Model Serving:**
```bash
# Check InferenceService
oc get inferenceservice granite-llm -n default-dsc

# Check model pods
oc get pods -n default-dsc | grep granite-llm

# Check model logs
oc logs -f $(oc get pods -n default-dsc -l serving.kserve.io/inferenceservice=granite-llm -o name | head -1) -n default-dsc
```

#### **Check Chat Application:**
```bash
# Check deployment
oc get deployment llmops-chat-app -n llmops-platform

# Check pods
oc get pods -n llmops-platform

# Check logs
oc logs -f deployment/llmops-chat-app -n llmops-platform
```

---

### **STEP 8: Access the Application**

Get the URL and start using the platform!

```bash
# Get the chat application URL
oc get route llmops-chat-app -n llmops-platform

# Example output:
# NAME              HOST/PORT
# llmops-chat-app   llmops-chat-app-llmops-platform.apps.cluster.example.com

# Open in browser:
# https://llmops-chat-app-llmops-platform.apps.cluster.example.com
```

#### **First Time Setup in UI:**
```
1. Click "⚙️ Configuration" button
2. Enter:
   - CAS Endpoint: https://your-cas-endpoint.com
   - CAS API Key: your-api-key
   - LLM Endpoint: (pre-configured)
3. Click "🔌 Initialize Components"
4. Click "🔄 Load Vector Stores"
5. Select your vector store
6. Start chatting!
```

---

## 🎨 **Using the Application**

### **Chat Interface:**

The application has a **three-panel layout**:

#### **Left Panel - Configuration:**
- Agent status
- Vector store selection
- System status

#### **Center Panel - Chat:**
- Processing metrics (time, sources, searches)
- Chat messages
- Input field

#### **Right Panel - Real-time Tracking:**
- **Progress Tracker** - Live updates:
  ```
  ✅ Initialized (14:23:41)
  ✅ Searching CAS (14:23:42)
  ✅ Context Building (14:23:43)
  ✅ LLM Inference (14:23:44)
  ✅ Completed (14:23:45) - 2.34s
  ```

- **Source Attribution** - Detailed sources:
  ```
  📄 Source 1: patent_guide.pdf (Relevance: 0.9234)
    📍 Line Numbers: 45 - 67
    🎯 Relevance Score: 0.9234
    Document ID: doc_abc123
    Content: "The patent filing process..."
  ```

### **Example Queries:**
```
"What is the patent filing process?"
"Summarize the technical specifications"
"Find information about data security"
"What are the system requirements?"
```

---

## 🔄 **GitOps Continuous Deployment**

After initial setup, all updates are automatic!

### **How It Works:**
```
1. You push changes to Git repository
   ↓
2. ArgoCD detects changes (every 3 minutes)
   ↓
3. ArgoCD automatically syncs
   ↓
4. Applications updated in cluster
   ↓
5. Self-healing if drift detected
```

### **Making Updates:**
```bash
# Update chat application
vi fusion-gitops-sample-app/chat_app.py
git add .
git commit -m "Update chat UI"
git push

# ArgoCD will automatically:
# - Detect the change
# - Rebuild if needed
# - Deploy new version
# - Verify health
```

---

## 📊 **Architecture Overview**

```
┌─────────────────────────────────────────────────────┐
│  User Browser                                       │
│  https://llmops-chat-app-...                        │
└─────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────┐
│  Chat Application (Streamlit)                       │
│  • 3-panel UI                                       │
│  • Real-time progress tracking                      │
│  • Source attribution                               │
└─────────────────────────────────────────────────────┘
        │                                    │
        ▼                                    ▼
┌──────────────────┐            ┌──────────────────────┐
│   CAS Client     │            │  LLM Endpoint        │
│  • Vector search │            │  • Granite 3.1 2B    │
│  • Line numbers  │            │  • vLLM serving      │
│  • Metadata      │            │  • OpenAI API        │
└──────────────────┘            └──────────────────────┘
        │                                    │
        ▼                                    ▼
┌──────────────────┐            ┌──────────────────────┐
│  CAS Vector      │            │  OpenShift AI        │
│  Store           │            │  (KServe)            │
│  • Documents     │            │  • GPU acceleration  │
│  • Embeddings    │            │  • Auto-scaling      │
└──────────────────┘            └──────────────────────┘
```

---

## 🐛 **Troubleshooting**

### **Issue: ArgoCD applications not syncing**

**Solution:**
```bash
# Check ArgoCD application status
oc get application -n openshift-gitops

# Describe application for details
oc describe application fusion-agentic-assistance-platform -n openshift-gitops

# Force sync
oc patch application fusion-agentic-assistance-platform -n openshift-gitops \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'
```

### **Issue: Model not loading**

**Solution:**
```bash
# Check InferenceService
oc get inferenceservice granite-llm -n default-dsc -o yaml

# Check events
oc get events -n default-dsc --sort-by='.lastTimestamp'

# Check GPU availability
oc describe node | grep nvidia.com/gpu

# Check model logs
oc logs -f $(oc get pods -n default-dsc -l serving.kserve.io/inferenceservice=granite-llm -o name) -n default-dsc
```

### **Issue: Chat app cannot connect to LLM**

**Solution:**
```bash
# Verify LLM endpoint
oc get svc granite-llm-predictor -n default-dsc

# Test endpoint from chat app pod
oc exec -it deployment/llmops-chat-app -n llmops-platform -- \
  curl -X POST "http://granite-llm-predictor.default-dsc.svc.cluster.local:8080/v1/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer EMPTY" \
  -d '{"prompt": "Hello", "max_tokens": 10}'

# Check ConfigMap
oc get configmap llmops-config -n llmops-platform -o yaml
```

### **Issue: No sources found in CAS**

**Solution:**
```bash
# Verify CAS endpoint in ConfigMap
oc get configmap llmops-config -n llmops-platform -o yaml | grep cas-endpoint

# Check CAS API key
oc get secret llmops-secrets -n llmops-platform -o jsonpath='{.data.cas-api-key}' | base64 -d

# Test CAS connection from chat app
oc exec -it deployment/llmops-chat-app -n llmops-platform -- \
  python3 -c "from src.cas_client import CASClient; client = CASClient(); print(client.health_check())"
```

---

## 📈 **Monitoring & Observability**

### **ArgoCD Dashboard:**
```bash
# Get ArgoCD URL
echo "https://$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}')"

# View:
# - Application sync status
# - Resource health
# - Deployment history
# - Git commits
```

### **Application Logs:**
```bash
# Chat application logs
oc logs -f deployment/llmops-chat-app -n llmops-platform

# Model serving logs
oc logs -f $(oc get pods -n default-dsc -l serving.kserve.io/inferenceservice=granite-llm -o name) -n default-dsc

# ArgoCD logs
oc logs -f deployment/openshift-gitops-application-controller -n openshift-gitops
```

### **Metrics:**
The application tracks:
- Query processing time
- CAS search duration
- LLM inference time
- Sources retrieved
- Relevance scores

---

## 🔒 **Security Best Practices**

1. **API Keys:**
   - Store in Kubernetes Secrets
   - Never commit to Git
   - Rotate regularly

2. **TLS/SSL:**
   - Routes use TLS termination
   - Internal traffic can use mTLS

3. **RBAC:**
   - Service accounts with minimal permissions
   - Namespace isolation

4. **Network Policies:**
   - Restrict pod-to-pod communication
   - Allow only necessary traffic

---

## 📚 **Additional Resources**

- **OpenShift AI Documentation:** https://access.redhat.com/documentation/en-us/red_hat_openshift_ai
- **ArgoCD Documentation:** https://argo-cd.readthedocs.io/
- **KServe Documentation:** https://kserve.github.io/website/
- **Streamlit Documentation:** https://docs.streamlit.io/

---

## 🤝 **Contributing**

Contributions are welcome! Please:
1. Follow SOLID design principles
2. Add unit tests
3. Update documentation
4. Test end-to-end

---

## 📄 **License**

[Your License Here]

---

## ✅ **Quick Reference**

### **One-Command Deployment:**
```bash
# After prerequisites (OpenShift AI + ArgoCD installed):
oc apply -f bootstrap.yaml
```

### **Check Status:**
```bash
oc get applications -n openshift-gitops
oc get pods -n default-dsc
oc get pods -n llmops-platform
```

### **Access Application:**
```bash
oc get route llmops-chat-app -n llmops-platform
```

### **View Logs:**
```bash
oc logs -f deployment/llmops-chat-app -n llmops-platform
```

---

**🎉 You're all set! Enjoy your Fusion Agentic Assistance platform!**
