# LLMOps Platform Demo Guide

Complete demo guide with architecture explanation, flow, and talking points.

## Demo Flow Overview

**Duration**: 15-20 minutes

**Flow:**
1. **Architecture Overview** (3-4 min)
2. **GitOps Applications** (2-3 min)
3. **OpenShift AI with Model** (2-3 min)
4. **CAS MCP** (2 min)
5. **Chat Application Demo** (5-7 min)
6. **Q&A** (2-3 min)

---

## 1. Architecture Overview (3-4 minutes)

### What to Show

**Open ARCHITECTURE.md or draw on whiteboard**

### Monologue Script

> "Good morning/afternoon everyone. Today I'm going to demonstrate an LLMOps platform that we've built on IBM Fusion HCI with OpenShift AI.
>
> **Let me start by explaining the architecture:**
>
> We have three main components:
>
> **First, OpenShift AI** - This is running on our Fusion HCI infrastructure and provides GPU-accelerated LLM serving. We're using KServe with vLLM to serve our Granite model. The model is deployed in the `default-dsc` namespace, which is OpenShift AI's Data Science Cluster.
>
> **Second, CAS** - Content-Aware Storage, which provides enterprise document retrieval. CAS has a vector store with all our enterprise documents, and it exposes an MCP - Model Context Protocol - endpoint that we use for semantic search.
>
> **Third, our Chat Application** - A simple Streamlit-based chat interface that brings everything together. This is deployed in the `llmops-platform` namespace.
>
> **The flow is simple:**
> 1. User asks a question in the chat app
> 2. Chat app queries CAS MCP to find relevant documents
> 3. CAS returns the most relevant documents with their content
> 4. Chat app sends the query plus document context to OpenShift AI LLM
> 5. LLM generates an answer based on the retrieved context
> 6. Chat app displays the answer along with source citations
>
> **The key here is that we're using GitOps for everything.** All our infrastructure is defined as code in Git, and ArgoCD automatically deploys and keeps everything in sync.
>
> Let me show you how this is deployed."

### Key Points to Emphasize

- ✅ OpenShift AI on Fusion HCI (GPU acceleration)
- ✅ CAS MCP for document retrieval
- ✅ Simple chat interface for end users
- ✅ GitOps for automation
- ✅ RAG pipeline (Retrieval-Augmented Generation)

---

## 2. GitOps Applications (2-3 minutes)

### What to Show

**Open ArgoCD UI or run:**
```bash
oc get applications -n openshift-gitops
```

### Monologue Script

> "Now let me show you how we've deployed this using GitOps.
>
> **We have exactly 2 ArgoCD applications:**
>
> **Application 1: llmops-platform**
> - This deploys our chat application
> - It includes the Streamlit UI, ConfigMaps, Secrets, and RBAC
> - Everything needed for the chat app to run
> - Deployed in the `llmops-platform` namespace
>
> **Application 2: llmops-models**
> - This deploys the LLM model serving
> - Uses KServe InferenceService
> - Deployed in the `default-dsc` namespace where OpenShift AI runs
>
> **Notice we don't have a separate monitoring application.** That's because OpenShift AI comes with built-in monitoring - Prometheus and Grafana are already there. We don't need to deploy our own.
>
> **The beauty of GitOps:**
> - All configuration is in Git
> - ArgoCD watches the repository
> - Any changes are automatically deployed
> - We can see the sync status, history, and health in ArgoCD UI
> - Everything is version controlled and auditable
>
> Let me show you the actual applications in ArgoCD..."

### Actions to Take

1. **Show ArgoCD UI:**
   - Navigate to Applications
   - Show `llmops-platform` and `llmops-models`
   - Show sync status (should be Synced/Healthy)

2. **Show Application Details:**
   - Click on `llmops-platform`
   - Show resource tree
   - Show sync history

3. **Explain GitOps Benefits:**
   - Infrastructure as Code
   - Automated deployments
   - Rollback capability
   - Audit trail

### Key Points to Emphasize

- ✅ Only 2 applications (simplified)
- ✅ OpenShift AI provides monitoring
- ✅ GitOps automation
- ✅ Everything in Git

---

## 3. OpenShift AI with Model (2-3 minutes)

### What to Show

**Open OpenShift Console or run:**
```bash
oc get inferenceservice -n default-dsc
oc get pods -n default-dsc
```

### Monologue Script

> "Now let's look at OpenShift AI and our LLM model.
>
> **OpenShift AI is running on Fusion HCI**, which gives us:
> - GPU acceleration (NVIDIA L40S GPUs)
> - High-performance storage
> - Simplified management
>
> **Our model is deployed as a KServe InferenceService:**
> - Model: Granite (IBM's open-source LLM)
> - Serving engine: vLLM (high-throughput)
> - Format: OpenAI-compatible API
> - Namespace: `default-dsc` (Data Science Cluster)
>
> **The model is ready and serving requests.** You can see it's running in a pod, and it's exposed as a Kubernetes service. The service name follows the pattern: `<model-name>-predictor.<namespace>.svc.cluster.local`
>
> **Why OpenShift AI?**
> - Built-in GPU management
> - Model versioning
> - Auto-scaling
> - Monitoring included
> - Enterprise-grade security
>
> The model is already deployed and ready. If it wasn't, our GitOps application would deploy it automatically.
>
> Let me show you the model status..."

### Actions to Take

1. **Show InferenceService:**
   ```bash
   oc get inferenceservice -n default-dsc
   oc describe inferenceservice granite-llm -n default-dsc
   ```

2. **Show Model Pod:**
   ```bash
   oc get pods -n default-dsc -l serving.kserve.io/inferenceservice=granite-llm
   oc logs -n default-dsc <pod-name> --tail=20
   ```

3. **Show Service:**
   ```bash
   oc get svc -n default-dsc | grep granite
   ```

4. **Optional: Test LLM Endpoint:**
   ```bash
   # Port-forward if needed
   oc port-forward -n default-dsc svc/granite-llm-predictor 8080:80
   
   # Test in another terminal
   curl -X POST http://localhost:8080/v1/completions \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer EMPTY" \
     -d '{"prompt": "Hello", "max_tokens": 10}'
   ```

### Key Points to Emphasize

- ✅ OpenShift AI on Fusion HCI
- ✅ GPU acceleration
- ✅ Model ready and serving
- ✅ OpenAI-compatible API
- ✅ Enterprise features

---

## 4. CAS MCP (2 minutes)

### What to Show

**Show CAS endpoint or run validation:**
```bash
python3 scripts/validate_cas_mcp.py
```

### Monologue Script

> "Now let's talk about CAS - Content-Aware Storage.
>
> **CAS provides enterprise document retrieval.** It has:
> - A vector store with all our enterprise documents
> - Semantic search capabilities
> - MCP - Model Context Protocol - endpoint
>
> **MCP is a standard protocol** that allows LLM applications to interact with external data sources. In our case, CAS exposes an MCP endpoint that we use to search documents.
>
> **The key feature is auto-discovery:**
> - We don't need to hardcode vector store IDs
> - The system automatically discovers available vector stores
> - Users can select which vector store to search in
>
> **CAS handles:**
> - Document indexing
> - Vector embeddings
> - Semantic and hybrid search
> - Relevance scoring
>
> The CAS endpoint is external to our cluster - it's a separate service. We just need to configure the endpoint and API key, and we're good to go.
>
> Let me validate that CAS is accessible..."

### Actions to Take

1. **Show CAS Validation:**
   ```bash
   export CAS_ENDPOINT=https://your-cas-endpoint
   export CAS_API_KEY=your-api-key
   python3 scripts/validate_cas_mcp.py
   ```

2. **Show Vector Stores:**
   - Explain that CAS can have multiple vector stores
   - Show how the chat app will list them

3. **Explain MCP:**
   - Standard protocol
   - JSON-RPC 2.0 format
   - Tool-based interface

### Key Points to Emphasize

- ✅ Enterprise document retrieval
- ✅ MCP protocol (standard)
- ✅ Auto-discovery of vector stores
- ✅ Semantic search

---

## 5. Chat Application Demo (5-7 minutes)

### What to Show

**Open Chat Application in browser**

### Monologue Script

> "Now for the main event - the chat application. This is where everything comes together.
>
> **Let me open the chat application...**
>
> [Open browser to chat app URL]
>
> **The UI is simple and clean:**
> - Chat interface on the right
> - Configuration sidebar on the left
>
> **First, let's configure it:**
> 1. CAS Endpoint - already configured via ConfigMap
> 2. CAS API Key - stored securely in a Secret
> 3. Vector Store - let's load the available stores
>
> [Click "Load Vector Stores"]
>
> **See how it automatically discovered the vector stores?** The system called CAS MCP's `list_vector_stores` tool and got all available stores. Now I can select which one to use.
>
> [Select a vector store from dropdown]
>
> **Now let's initialize the components:**
> [Click "Initialize Components"]
>
> **Great! Everything is ready. Now let's ask a question:**
>
> [Type a question, e.g., "What is OpenShift AI?"]
>
> **Watch what happens:**
> 1. The query goes to CAS MCP
> 2. CAS searches the vector store
> 3. Returns relevant documents
> 4. The documents are sent to OpenShift AI LLM with the query
> 5. LLM generates an answer
> 6. We see the answer plus the source documents
>
> [Wait for response, then show results]
>
> **Look at this:**
> - The answer is generated based on the retrieved documents
> - We can see which documents were used
> - Each document shows the source path and relevance score
> - This is true RAG - Retrieval-Augmented Generation
>
> **Let's ask another question to show it's working:**
> [Ask another question]
>
> **Notice:**
> - Different documents retrieved
> - Answer is context-aware
> - Sources are always cited
> - This is production-ready RAG
>
> **The beauty of this solution:**
> - Simple for end users
> - Powerful RAG pipeline
> - All components integrated
> - Deployed via GitOps"

### Actions to Take

1. **Open Chat Application:**
   ```bash
   # Get route
   oc get route llmops-chat-app -n llmops-platform
   # Open in browser
   ```

2. **Show Configuration:**
   - CAS endpoint (pre-filled)
   - Load vector stores button
   - Vector store dropdown
   - Initialize button

3. **Demonstrate Queries:**
   - Ask 2-3 questions
   - Show retrieved documents
   - Show answers with sources
   - Explain the flow

4. **Show Document Listing:**
   - Expand document sections
   - Show metadata
   - Show scores
   - Explain content API coming soon

### Key Points to Emphasize

- ✅ Simple UI for end users
- ✅ Vector store selection
- ✅ Real-time RAG queries
- ✅ Document transparency
- ✅ Source citations

---

## 6. Q&A and Summary (2-3 minutes)

### Monologue Script

> "Let me summarize what we've built:
>
> **We have a complete LLMOps platform:**
> 1. OpenShift AI serving LLMs on Fusion HCI
> 2. CAS MCP for enterprise document retrieval
> 3. Chat application with RAG pipeline
> 4. Everything deployed via GitOps
>
> **Key benefits:**
> - **GitOps**: Infrastructure as Code, automated deployments
> - **OpenShift AI**: Enterprise-grade LLM serving with GPU acceleration
> - **CAS MCP**: Standard protocol for document retrieval
> - **Simple UI**: End users can ask questions without technical knowledge
> - **Transparency**: Always see which documents were used
>
> **This is production-ready:**
> - Scalable (OpenShift handles scaling)
> - Secure (Secrets management, RBAC)
> - Observable (OpenShift AI monitoring)
> - Maintainable (GitOps)
>
> **Questions?"**

### Common Questions and Answers

**Q: Why only 2 applications?**
> A: OpenShift AI provides built-in monitoring, so we don't need a separate monitoring application. This simplifies the deployment and reduces complexity.

**Q: How does vector store auto-discovery work?**
> A: The system calls CAS MCP's `list_vector_stores` tool when needed. If no vector store is specified, it automatically discovers and uses the first available one.

**Q: What if I want to deploy a different model?**
> A: Just update the `gitops/models/kserve-model-serving.yaml` file with your model configuration, commit, and ArgoCD will deploy it automatically.

**Q: Can I use this with other document stores?**
> A: Yes, as long as they support MCP protocol. CAS is just one implementation. The architecture is flexible.

**Q: How do I scale this?**
> A: OpenShift handles horizontal scaling automatically. You can adjust replica counts in the deployment manifests, and OpenShift will scale based on load.

**Q: What about security?**
> A: We use Kubernetes Secrets for sensitive data (API keys), RBAC for access control, and OpenShift's built-in security features. CAS authentication is handled via API keys.

**Q: How do I update the chat app?**
> A: Update the code, build/push new image, update the deployment in Git, and ArgoCD syncs automatically. No manual kubectl commands needed.

---

## Demo Checklist

### Before Demo

- [ ] Review architecture diagram
- [ ] Test chat application
- [ ] Prepare 2-3 example questions
- [ ] Verify all components are running
- [ ] Have ArgoCD UI ready
- [ ] Have OpenShift Console ready
- [ ] Test CAS connection
- [ ] Test LLM endpoint

### During Demo

- [ ] Explain architecture (3-4 min)
- [ ] Show GitOps applications (2-3 min)
- [ ] Show OpenShift AI model (2-3 min)
- [ ] Show CAS MCP (2 min)
- [ ] Demo chat application (5-7 min)
- [ ] Q&A (2-3 min)

### After Demo

- [ ] Answer questions
- [ ] Share repository link
- [ ] Offer to help with setup
- [ ] Collect feedback

---

## Troubleshooting During Demo

### If Chat App Doesn't Load

**Say:**
> "Let me check the deployment status..."

**Do:**
```bash
oc get pods -n llmops-platform
oc get route -n llmops-platform
oc logs -n llmops-platform deployment/llmops-chat-app --tail=20
```

### If LLM Doesn't Respond

**Say:**
> "Let me verify the LLM is ready..."

**Do:**
```bash
oc get inferenceservice -n default-dsc
oc get pods -n default-dsc
# Test endpoint if needed
```

### If CAS Connection Fails

**Say:**
> "Let me check the CAS configuration..."

**Do:**
```bash
oc get configmap llmops-config -n llmops-platform
oc get secret llmops-secrets -n llmops-platform
python3 scripts/validate_cas_mcp.py
```

---

## Demo Tips

1. **Start Strong**: Begin with architecture to set context
2. **Show Automation**: Emphasize GitOps benefits early
3. **Be Interactive**: Ask the audience questions
4. **Show Real Results**: Use actual questions that return good results
5. **Explain Why**: Don't just show what, explain why each design decision
6. **Handle Questions**: Be prepared for technical questions
7. **End with Value**: Summarize benefits and use cases

---

## Key Messages to Convey

1. **Simplicity**: Simple chat UI, complex RAG pipeline underneath
2. **Automation**: GitOps makes deployment and updates easy
3. **Integration**: Seamless integration of OpenShift AI + CAS
4. **Enterprise-Ready**: Production-grade solution
5. **Open Source**: Built on open-source technologies
6. **Fusion HCI**: Leverages IBM Fusion HCI capabilities

---

## Closing Statement

> "Thank you for your attention. This LLMOps platform demonstrates how we can bring together OpenShift AI, CAS, and GitOps to create a production-ready RAG solution on IBM Fusion HCI.
>
> The code is available in our repository, and we have comprehensive documentation for setup and deployment.
>
> If you have any questions or would like to see a deeper dive into any component, I'm happy to discuss.
>
> Thank you!"

