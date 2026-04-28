# Running Disaggregated LLM Inference on IBM Fusion HCI
## Prefill–Decode Separation, KV Cache Affinity, and What the Metrics Show

Getting an LLM to respond is straightforward. Getting it to respond consistently at scale, with observable performance, that’s where most deployments run into trouble.

Traditional LLM deployments often struggle with scaling inefficiencies, high latency, and limited visibility into where time is spent during inference.

Red Hat OpenShift AI 3.0 introduces a new inference architecture built around llm-d (LLM Disaggregated Inference), which separates the Prefill and Decode phases of LLM inference into independently scalable pod pools. This approach addresses key challenges by isolating compute-heavy and memory-bound workloads, improving KV cache reuse across requests, and enabling fine-grained observability into each stage of inference.

Running this stack on IBM Fusion HCI further simplifies GPU, storage, and operator readiness for enterprise AI workloads.

This blog walks through the prerequisites, the `LLMInferenceService` CR configuration with full Prefill-Decode separation, the authentication setup via Red Hat Connectivity Link, and two rounds of load testing with real Prometheus metrics. The model used was `mistralai/Ministral-3-8B-Instruct-2512`, deployed in the `llm-model-serving` namespace on IBM Fusion HCI running OpenShift 4.19+.

---

## Executive Summary

This article presents a practical, metrics-driven walkthrough of running disaggregated
LLM inference using Red Hat OpenShift AI’s llm-d architecture on IBM Fusion HCI.

Using the `mistralai/Ministral-3-8B-Instruct-2512` model, we demonstrate:
- How prefill–decode separation changes GPU utilization and request behavior
- How KV cache–aware scheduling reduces redundant computation and improves latency
- How the Endpoint Picker Protocol (EPP) scheduler makes phase‑aware routing decisions
- Which Prometheus metrics validate correct disaggregated inference behavior

Rather than focusing on theoretical benefits, this post uses real load tests and
observable signals—prefill token spikes, sustained decode throughput, asymmetric cache
hits, and improved time‑to‑first‑token—to confirm that the architecture behaves as expected
under concurrent load.

The goal is to give AI platform and MLOps engineers a clear mental model of how
disaggregated inference works in practice, when it provides measurable benefits, and
how to reason about its performance using production‑grade telemetry.

---

## Disaggregated Inference Architecture

The end-to-end request flow from the user to the model is as follows:

```
User Request (HTTPS)
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│ Gateway API (openshift-ingress namespace)                   │
│ - openshift-ai-inference Gateway                            │
│ - Port 443, TLS termination                                 │
│ - OpenShift-managed certificate                             │
└─────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│ Kuadrant (Red Hat Connectivity Link)                        │
│ ├── Authorino → KubernetesTokenReview (JWT validation)      │
│ └── Limitador → Rate limiting                               │
└─────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│ EPP Scheduler (Endpoint Picker Protocol)                    │
│                                                             │
│ Scheduling Plugins:                                         │
│ ├── prefill-header-handler                                  │
│ ├── prefill-filter    → routes prefill to prefill pool      │
│ ├── decode-filter     → routes decode to decode pool        │
│ ├── queue-scorer      → weight 1.0 (queue depth)            │
│ ├── kv-cache-utilization-scorer → weight 2.0 (cache hits)   │
│ ├── max-score-picker  → selects highest-scoring pod         │
│ └── pd-profile-handler                                      │
└─────────────────────────────────────────────────────────────┘
        │
   ┌────┴────────┐
   ▼             ▼
┌─────────┐  ┌─────────┐
│ Prefill │  │ Decode  │
│  Pool   │  │  Pool   │
├─────────┤  ├─────────┤
│ Pod 1   │  │ Pod 1   │
│ (1 GPU) │  │ (1 GPU) │
├─────────┤  ├─────────┤
│ Pod 2   │  │ Pod 2   │
│ (1 GPU) │  │ (1 GPU) │
└─────────┘  └─────────┘
```
In simple terms, requests pass through authentication and scheduling layers before being intelligently routed to either prefill or decode pods.

**The key difference introduced by llm-d** is the EPP Scheduler layer. Traditional vLLM deployments rely on round-robin or simple load balancing. The EPP Scheduler in llm-d routes based on semantic awareness of the inference pipeline: it understands which phase a request is in (prefill vs decode), which pods have warm KV caches for similar prompts, and the current queue depth per pod. This results in better GPU utilization and lower time-to-first-token (TTFT), especially for workloads with repeated or overlapping prompts.

---

## Prerequisites

### Platform Requirements

- IBM Fusion HCI cluster installed and in a healthy state
- OpenShift 4.19.9+ running on IBM Fusion
- GPU-enabled worker nodes (NVIDIA GPUs)
- Cluster admin access

### OpenShift Cluster and Operator Requirements

According to the [official OpenShift AI 3.3 documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/deploying_models/deploying_models#deploying-models-using-distributed-inference_rhoai-user):

**Required Operators:**

Install these operators from OperatorHub in the OpenShift Web Console:

| Operator | Channel | Purpose |
|---|---|---|
| Node Feature Discovery | `stable` | Automatically detects and labels GPU nodes for workload scheduling |
| NVIDIA GPU Operator | `stable` | Manages GPU drivers, device plugins, and container runtime for GPU workloads |
| Red Hat OpenShift Serverless | `stable` | Provides Knative Serving for auto-scaling inference workloads |
| Red Hat OpenShift AI | `stable-3.x` | Provides KServe for model serving and inference management |
| LeaderWorkerSet Operator | `stable` | Manages coordinated prefill-decode pod groups for llm-d disaggregated inference |
| Red Hat Connectivity Link | `stable` | Provides Kuadrant for API gateway, authentication (Authorino), and rate limiting (Limitador) |

**Verify Operator Installation:**

```bash
# Check all operators are in Succeeded state
oc get csv -A | grep -E "rhods|gpu|rhcl|serverless|nfd|leaderworkerset"
```

**Cluster Requirements:**

- OpenShift Service Mesh v2 must **not** be installed (conflicts with Gateway API)
- Gateway API resources configured (see below)
- Access to the OpenShift CLI (`oc`)
- Cluster admin access

### Gateway API Configuration

The Gateway API is used to expose LLM inference endpoints via HTTPS. Two resources are required:

**1. GatewayClass**

The `GatewayClass` defines the controller that manages Gateway resources:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: openshift-ai-inference
spec:
  controllerName: openshift.io/gateway-controller/v1
```

**2. Gateway**

The `Gateway` resource in the `openshift-ingress` namespace exposes HTTP (port 80) and HTTPS (port 443) endpoints:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: openshift-ai-inference
  namespace: openshift-ingress
spec:
  gatewayClassName: openshift-ai-inference
  listeners:
    - name: http
      port: 80
      protocol: HTTP
      allowedRoutes:
        namespaces:
          from: All
    - name: https
      port: 443
      protocol: HTTPS
      allowedRoutes:
        namespaces:
          from: All
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: router-certs-default
```

**TLS Certificate Configuration:**

The Gateway uses the existing `router-certs-default` secret from the `openshift-ingress` namespace, which is managed by the OpenShift ingress controller. This provides automatic TLS termination with OpenShift-managed certificates. For production-grade deployments, you can provide a custom TLS certificate by creating your own secret and referencing it in the `certificateRefs` field.

**Verify Gateway API Resources:**

```bash
# Verify GatewayClass exists
oc get gatewayclass openshift-ai-inference

# Verify Gateway is configured
oc get gateway -n openshift-ingress openshift-ai-inference

# Check Gateway status
oc get gateway -n openshift-ingress openshift-ai-inference -o yaml
```

**Authentication Requirements:**
- Red Hat Connectivity Link must be installed and fully configured before deploying any LLMInferenceService, as it is required for authentication and AuthPolicy creation
- A ServiceAccount with permission to access the LLMInferenceService must be created
- A JWT token must be generated from this ServiceAccount and used for authenticating inference requests

---

## Step 1: Configure Authentication First

Authentication via Red Hat Connectivity Link must be configured before deploying the LLMInferenceService. In OpenShift AI 3.0 and later, authentication and authorization are automatically enabled for LLMInferenceService resources when Red Hat Connectivity Link is configured. 

### Create the Kuadrant CR

```bash
oc apply -f - <<EOF
apiVersion: kuadrant.io/v1beta1
kind: Kuadrant
metadata:
  name: kuadrant
  namespace: kuadrant-system
spec: {}
EOF
```

Wait for it to become ready:

```bash
oc wait Kuadrant -n kuadrant-system kuadrant --for=condition=Ready --timeout=10m
```

### Enable TLS for Authorino

This is required for token-based authentication. The annotation tells OpenShift's service-ca operator to generate a signed TLS certificate for the Authorino service:

```bash
oc annotate svc/authorino-authorino-authorization \
  service.beta.openshift.io/serving-cert-secret-name=authorino-server-cert \
  -n kuadrant-system
```

Then update the Authorino CR to use that certificate:

```bash
oc apply -f - <<EOF
apiVersion: operator.authorino.kuadrant.io/v1beta1
kind: Authorino
metadata:
  name: authorino
  namespace: kuadrant-system
spec:
  replicas: 1
  clusterWide: true
  listener:
    tls:
      enabled: true
      certSecretRef:
        name: authorino-server-cert
  oidcServer:
    tls:
      enabled: false
EOF
```

Wait for the pods:

```bash
oc wait --for=condition=ready pod -l authorino-resource=authorino \
  -n kuadrant-system --timeout 150s
```

### If OpenShift AI Was Installed Before Connectivity Link

If RHOAI was already running when you installed Connectivity Link, restart the controllers so they pick up the Kuadrant integration:

```bash
oc delete pod -n redhat-ods-applications -l app=odh-model-controller
oc delete pod -n redhat-ods-applications -l control-plane=kserve-controller-manager
```

### How AuthPolicies Are Created Automatically

Once Kuadrant is running, when you deploy an `LLMInferenceService`, the ODH Model Controller automatically creates two `AuthPolicy` objects, one at the Gateway level and one scoped to the HTTPRoute for your specific model. You verify them after deployment:

```bash
oc get authpolicy -A
# NAMESPACE          NAME                             TARGETREF
# openshift-ingress  openshift-ai-inference-authn     Gateway
# llm-model-serving  ministral-3-8b-pd-kserve-route-authn  HTTPRoute
```

For production, leave authentication enabled (the default). To explicitly re-enable if it was disabled:

```yaml
annotations:
  security.opendatahub.io/enable-auth: "true"
```

---

## Step 2: Deploy the LLMInferenceService with Prefill-Decode Separation

This is the core of what makes llm-d different from a standard KServe deployment. The `LLMInferenceService` CR defines separate Prefill and Decode replica pools, and configures the EPP Scheduler with plugin weights that determine how requests are routed between them.

Here is the full CR:

```yaml
apiVersion: serving.kserve.io/v1alpha1
kind: LLMInferenceService
metadata:
  name: ministral-3-8b-pd
  namespace: llm-model-serving
spec:
  model:
    name: mistralai/Ministral-3-8B-Instruct-2512
    uri: 'hf://mistralai/Ministral-3-8B-Instruct-2512'
  prefill:
    replicas: 2
    template:
      containers:
        - env:
            - name: HF_HOME
              value: /models/cache
          livenessProbe:
            failureThreshold: 10
            httpGet:
              path: /health
              port: 8000
              scheme: HTTPS
            initialDelaySeconds: 300
            periodSeconds: 30
            timeoutSeconds: 60
          name: main
          resources:
            limits:
              cpu: '4'
              memory: 48Gi
              nvidia.com/gpu: '1'
            requests:
              cpu: '4'
              memory: 48Gi
              nvidia.com/gpu: '1'
  replicas: 2
  router:
    gateway: {}
    route: {}
    scheduler:
      template:
        containers:
          - args:
              - '--pool-name'
              - '{{ ChildName .ObjectMeta.Name `-inference-pool` }}'
              - '--pool-namespace'
              - '{{ .ObjectMeta.Namespace }}'
              - '--zap-encoder'
              - json
              - '--grpc-port'
              - '9002'
              - '--grpc-health-port'
              - '9003'
              - '--secure-serving'
              - '--model-server-metrics-scheme'
              - https
              - '--enable-pprof'
              - '--zap-log-level'
              - debug
              - '--cert-path'
              - /var/run/kserve/tls
              - '--config-text'
              - |
                apiVersion: inference.networking.x-k8s.io/v1alpha1
                kind: EndpointPickerConfig
                plugins:
                  - type: prefill-header-handler
                  - type: prefill-filter
                  - type: decode-filter
                  - type: queue-scorer
                  - type: kv-cache-utilization-scorer
                  - type: max-score-picker
                  - type: pd-profile-handler
                    parameters:
                      threshold: 0
                      hashBlockSize: 16

                schedulingProfiles:
                  - name: prefill
                    plugins:
                      - pluginRef: prefill-filter
                      - pluginRef: queue-scorer
                        weight: 1.0
                      - pluginRef: max-score-picker

                  - name: decode
                    plugins:
                      - pluginRef: decode-filter
                      - pluginRef: queue-scorer
                        weight: 1.0
                      - pluginRef: kv-cache-utilization-scorer
                        weight: 2.0
                      - pluginRef: max-score-picker
            name: main
            resources: {}
  template:
    containers:
      - env:
          - name: HF_HOME
            value: /models/cache
        livenessProbe:
          failureThreshold: 10
          httpGet:
            path: /health
            port: 8000
            scheme: HTTPS
          initialDelaySeconds: 300
          periodSeconds: 30
          timeoutSeconds: 60
        name: main
        resources:
          limits:
            cpu: '4'
            memory: 48Gi
            nvidia.com/gpu: '1'
          requests:
            cpu: '4'
            memory: 48Gi
            nvidia.com/gpu: '1'

```

### Understanding the EPP Scheduler Plugins

The EPP (Endpoint Picker Protocol) Scheduler uses a plugin-based architecture to make intelligent routing decisions. Here's how each plugin contributes to the inference pipeline:

#### Core Scheduling Plugins

**`prefill-header-handler`** - Inspects incoming requests and tags them with metadata indicating whether they're in the prefill or decode phase. This enables phase-aware routing downstream.

**`prefill-filter`** - Routes prefill-phase requests exclusively to the prefill pod pool. Ensures compute-intensive prompt processing is isolated from token generation.

**`decode-filter`** - Routes decode-phase requests exclusively to the decode pod pool. Ensures memory-bandwidth-sensitive token generation happens on pods optimized for sequential output.

**`queue-scorer` (weight 1.0)** - Scores pods based on current queue depth. Lower queue = higher score. Prevents any single pod from becoming a bottleneck.

**`kv-cache-utilization-scorer` (weight 2.0)** - Scores pods based on KV cache prefix matches. If a pod already has the prompt context cached, it gets a higher score. **This is the key differentiator** - the 2.0 weight means cache affinity is prioritized over queue depth for decode requests.

**`max-score-picker`** - Selects the pod with the highest combined score from all scorers. The final routing decision balances queue depth and cache efficiency.

**`pd-profile-handler`** - Manages the scheduling profiles (prefill vs decode) and applies the appropriate plugin chain based on the request phase.

#### Key Configuration Parameters

**`hashBlockSize: 16`** - Controls KV cache prefix matching granularity. The scheduler tracks cached context in 16-token blocks. This allows partial prompt overlaps (shared system prompts, few-shot examples) to still get cache hits. Smaller blocks = finer matching but more overhead; larger blocks = coarser matching but fewer cache hits.

**Scheduling Profile Weights:**
- **Prefill profile:** `queue-scorer` only (weight 1.0), prefill is compute-bound with no cache reuse
- **Decode profile:** `queue-scorer` (weight 1.0) + `kv-cache-utilization-scorer` (weight 2.0), decode benefits from cache-aware routing

The 2:1 weight ratio means the scheduler will route to a slightly busier pod if that pod has the matching KV cache. For decode requests, avoiding a cache miss (recomputing full prompt context) outweighs a marginally longer queue.

**`threshold: 0`** - The scheduler considers all healthy pods for every request. In larger deployments, you might raise this to exclude heavily loaded pods.

**`initialDelaySeconds: 300`** - Model loading for an 8B parameter model takes several minutes. The pod needs time to download weights and load them into GPU memory before the health endpoint responds. On IBM Fusion HCI, where storage reads happen over the network fabric, 300 seconds provides a safe initialization buffer.

---

## Step 3: Verify the Deployment

```bash
# Check overall status
oc get llminferenceservice -n llm-model-serving

# Expect: 2 prefill pods + 2 decode pods + 1 scheduler pod
oc get pods -n llm-model-serving

# Verify AuthPolicies were auto-created
oc get authpolicy -A

# Get the inference endpoint
oc get llminferenceservice ministral-3-8b-pd -n llm-model-serving \
  -o jsonpath='{.status.url}'
```

---

## Step 4: Exposing the LLM Inference Service Externally

By default, the inference gateway service is exposed as a `ClusterIP`, which is only accessible within the cluster. To access the model externally, you must create an OpenShift Route.

### Expose the Gateway Service

```bash
oc expose service openshift-ai-inference-openshift-ai-inference -n openshift-ingress
```

**Note**: This approach works on IBM Fusion HCI but may differ in other OpenShift environments. Verify the service name with `oc get svc -n openshift-ingress` before running.

### Get the External Host

```bash
oc get route openshift-ai-inference -n openshift-ingress
```

Example output:
```
oc get route openshift-ai-inference -n openshift-ingress
NAME                     HOST/PORT                                                                   PATH   SERVICES                                        
openshift-ai-inference   openshift-ai-inference-openshift-ingress.apps.<cluster-domain>                     openshift-ai-inference-openshift-ai-inference 
NAME                                          HOST/PORT
openshift-ai-inference-openshift-ai-inference openshift-ai-inference-openshift-ai-inference.apps.<cluster-domain>
```

### Construct the Model Endpoint

The inference endpoint follows this pattern:
```
https://<route-host>/<namespace>/<llm-service-name>
```

Example for the `ministral-3-8b-pd` service in the `llm-model-serving` namespace:
```
https://openshift-ai-inference-openshift-ai-inference.apps.<cluster-domain>/llm-model-serving/ministral-3-8b-pd
```

### Verify External Access

Test the endpoint by listing available models:

```bash
curl -k https://<route-host>/llm-model-serving/<llm-service-name>/v1/models \
  -H "Authorization: Bearer $(oc whoami -t)"
```

Example response:
```json
{
  "object": "list",
  "data": [
    {
      "id": "mistralai/Ministral-3-8B-Instruct-2512",
      "object": "model",
      "created": 1234567890,
      "owned_by": "system"
    }
  ]
}
```

---

## Step 5: Load Testing and Observability

Two targeted test scenarios were executed to validate Prefill-Decode separation and KV cache efficiency. All metrics were collected via Prometheus using the OpenShift monitoring stack.

### TEST 1 - Validating Prefill-Decode Separation

This test issues 50 concurrent requests with a detailed prompt to validate that Prefill-Decode (PD) separation is functioning correctly. The objective is to confirm that both pod pools receive traffic and that token-level metrics are emitted as expected under concurrent load.

**Load Test Command:**

```bash
PROMPT="Explain Quantum Computing in detail with examples and code"

seq 1 50 | xargs -n1 -P15 -I{} curl -k \
  https://openshift-ai-inference-openshift-ingress.apps.f07d005.fusion.tadn.ibm.com/llm-model-serving/v1/chat/completions \
  -H "Authorization: Bearer $(oc whoami -t)" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"mistralai/Ministral-3-8B-Instruct-2512\",
    \"messages\": [{\"role\": \"user\", \"content\": \"$PROMPT\"}]
  }"
```

#### Running Requests

**Metric:** Number of in-flight requests

```promql
kserve_vllm:num_requests_running
```

<img width="3006" height="1586" alt="image" src="https://github.com/user-attachments/assets/d8d2e0db-4f71-42cf-91f1-c9e3b75e0ccf" />

**Analysis:** This graph shows the number of in-flight requests across the system. A sharp increase is visible as concurrent requests are initiated, followed by a gradual decline as requests complete. This pattern confirms that the system is handling parallel load and draining requests as expected.

#### Prefill Tokens per Pod

**Metric:** Prompt token processing in prefill phase

```promql
sum by(pod)(
  rate(kserve_vllm:prompt_tokens_total{llm_isvc_role="prefill"}[1m])
)
```

<img width="2934" height="1344" alt="image" src="https://github.com/user-attachments/assets/71081b6e-328d-430f-945e-0f9973aafcc4" />

**Analysis:** This graph shows prompt token processing across prefill pods. A noticeable spike occurs early in the timeline, indicating that multiple prompts are processed simultaneously. The activity then tapers off as requests transition into the decode phase, confirming that prefill handles the initial burst of computation.

#### Decode Tokens per Pod

**Metric:** Token generation in decode phase

```promql
sum by(pod)(
  rate(kserve_vllm:generation_tokens_total{llm_isvc_role="decode"}[1m])
)
```

<img width="2948" height="1336" alt="image" src="https://github.com/user-attachments/assets/ba784a2e-fbd3-4f2a-be6b-6468abe4eeba" />

**Analysis:** This graph shows token generation across decode pods. Unlike prefill, token generation increases more gradually and remains sustained over time as responses are streamed. This reflects the sequential nature of token generation and confirms that decode operates independently from prefill.

**Test Results:** The observed pattern, an initial prefill spike followed by sustained decode throughput, validates correct phase separation. Prefill absorbs bursty prompt processing, while decode maintains steady token generation, demonstrating effective workload isolation under concurrent load. This establishes a baseline for evaluating cache efficiency and latency improvements in the next test.

---

### TEST 2 - Evaluating KV Cache Efficiency and Latency

KV cache efficiency is the primary differentiator in disaggregated inference. The key indicator is the prefix cache hit rate per decode pod. High cache hit rates imply that semantically similar requests are routed to pods with existing KV cache state, avoiding redundant computation.

**Load Test Command:**

```bash
PROMPT="Explain in detail how event-driven architectures using Apache Kafka work in large-scale distributed systems, including producer-consumer models, partitioning strategies, offset management, message durability, fault tolerance, and exactly-once semantics"

seq 1 100 | xargs -n1 -P10 -I{} curl -k https://openshift-ai-inference-openshift-ingress.apps.f07d005.fusion.tadn.ibm.com/llm-model-serving/ministral-3-8b-pd/v1/chat/completions \
  -H "Authorization: Bearer $(oc whoami -t)" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"mistralai/Ministral-3-8B-Instruct-2512\",
    \"messages\": [{\"role\": \"user\", \"content\": \"$PROMPT\"}],
    \"max_tokens\": 200
  }"

```

### Cache Effectiveness
#### KV Cache Hits per Decode Pod

**Metric:** Cache reuse efficiency

```promql
sum by(pod)(
  rate(kserve_vllm:prefix_cache_hits_total{llm_isvc_role="decode"}[1m])
)
```

<img width="2940" height="1332" alt="image" src="https://github.com/user-attachments/assets/00b7f7ac-d3dc-40ac-b741-457d0b65b5d6" />

**Analysis:** This graph shows prefix cache hit rates broken down per decode pod. The lines are not uniform; one or more pods show consistently higher cache hit rates compared to others. This uneven distribution indicates that requests with similar prompt structures are repeatedly routed to the same pod, confirming effective cache-aware scheduling. This is the most critical metric in disaggregated inference. Without sustained cache hit rates, Prefill-Decode separation does not provide meaningful performance improvements.

### Workload Distribution
#### Prompt Tokens (Baseline Workload)

**Metric:** Incoming prompt workload

```promql
increase(kserve_vllm:prompt_tokens_total[1m])
```

<img width="3026" height="1476" alt="image" src="https://github.com/user-attachments/assets/247e19e8-9ed2-4a5b-81d8-d56e02e34bec" />

**Analysis:** This graph shows the total number of prompt tokens processed over time. Distinct spikes are visible, corresponding to bursts of incoming requests or new prompt variations. These spikes represent fresh computation entering the system and serve as a baseline for evaluating cache effectiveness.

#### Prefill Tokens per Pod

**Metric:** Prefill workload distribution

```promql
sum by(pod)(
  increase(kserve_vllm:prompt_tokens_total{llm_isvc_role="prefill"}[1m])
)
```

<img width="3014" height="1138" alt="image" src="https://github.com/user-attachments/assets/e342fe72-06a4-41cf-be0b-63e2235b1dc1" />

**Analysis:** This graph shows how prompt tokens are distributed across prefill pods. Spikes are visible across prefill pods during periods of increased prompt activity, while decode pods remain unaffected. This confirms that prompt processing load is isolated to the prefill layer, preventing interference with token generation.

### Latency and Performance
#### Time to First Token (TTFT)

**Metric:** Initial response latency

```promql
rate(kserve_vllm:time_to_first_token_seconds_sum[1m])
```

<img width="3018" height="1460" alt="image" src="https://github.com/user-attachments/assets/fe7231c3-3302-48af-bd78-4e70818fdb10" />

**Analysis:** This graph shows the rate of time-to-first-token across requests. Noticeable fluctuations correspond to differences in request processing time, with lower values occurring during periods of higher cache reuse. This indicates that requests benefiting from KV cache hits bypass redundant prefill computation, resulting in faster initial response times.

#### Decode Latency

**Metric:** Token generation latency

```promql
rate(kserve_vllm:request_decode_time_seconds_sum[1m])
```

<img width="3008" height="1422" alt="image" src="https://github.com/user-attachments/assets/9b53e851-c9af-4d34-a1cb-01fe2aeef54b" />

**Analysis:** This graph shows the time spent in the decode phase across requests. The curve remains relatively stable without sharp spikes, indicating consistent token generation performance. This stability suggests that cache-aware routing reduces variability by directing requests to pods with warm KV cache state.

#### Decode Tokens per Pod

**Metric:** Decode workload distribution
```promql
sum by(pod)(
  increase(kserve_vllm:generation_tokens_total{llm_isvc_role="decode"}[1m])
)
```

<img width="3022" height="1022" alt="image" src="https://github.com/user-attachments/assets/8c3eb1d5-5cf1-46ac-8c9f-5c4886bcfdc7" />

**Analysis:** This graph shows token generation distributed across decode pods. Token generation increases steadily across pods, with slight variations reflecting load balancing and cache locality. This confirms that the decode workload is distributed while still benefiting from routing decisions that preserve cache efficiency.

**Test Results:** The observed patterns, asymmetric cache hits, bursty prefill spikes, stable decode latency, and steady token generation collectively confirm that Prefill-Decode separation and cache-aware scheduling are functioning as intended. Cache reuse reduces redundant computation, improves latency, and maintains efficient GPU utilization under load.

---

## Observability and Metrics

Traditional LLM inference typically exposes end-to-end latency, which limits visibility into where time is spent within the inference pipeline.

With llm-d, metrics are available at each stage of the request lifecycle, enabling more granular analysis:

- **Prefill phase** → `prompt_tokens_total`, `time_to_first_token_seconds`
- **Decode phase** → `generation_tokens_total`, `request_decode_time_seconds`
- **Cache layer** → `prefix_cache_hits_total`
- **Scheduler routing** → `num_requests_running` segmented by `llm_svc_role`

These metrics represent a subset of the available signals and provide useful insights into key performance characteristics of the system.

They enable more targeted analysis, for example:
- Increased latency may indicate higher prefill load or reduced cache effectiveness
- Elevated decode time may suggest token generation bottlenecks
- Low cache hit rates may indicate limited prompt reuse or suboptimal routing

On IBM Fusion HCI, these metrics are available through the OpenShift monitoring stack when user workload monitoring is enabled.

This visibility allows inference behaviour to be analyzed at a component level rather than relying solely on aggregate latency.

---

## Key Takeaways

**KV cache efficiency drives performance** in disaggregated inference. Higher cache reuse directly reduces latency and redundant computation.

**Prefill-Decode separation** improves scalability by isolating bursty prompt processing from steady token generation, enabling independent scaling of each phase.

**Scheduler tuning is workload-dependent** prioritize cache scoring for repeated prompts, and queue depth for highly varied workloads.

**IBM Fusion HCI simplifies operations** with reliable GPU infrastructure and seamless OpenShift integration, reducing deployment and troubleshooting overhead.

---

## Final Thoughts

Disaggregated LLM inference shifts inference from a black box to an observable,
schedulable pipeline.

For AI platform and MLOps teams, this enables disciplined scaling:
aligning GPU resources to inference phases, preserving cache locality,
and validating performance with telemetry rather than intuition.

As LLM workloads mature into sustained production systems, architectures that
expose—and optimize for—these internal behaviors will become increasingly important.

---

## References
- TechXchange blog post: https://community.ibm.com/community/user/blogs/harichandana-kotha/2026/03/30/disaggregated-llm-inference-on-ibm-fusion-hci
- Red Hat OpenShift AI: [**Red Hat OpenShift AI**](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed)
- Deploying models by using Distributed Inference with llm-d: [**Deploying models by using Distributed Inference with llm-d**](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.0/html/deploying_models/deploying_models#deploying-models-using-distributed-inference_rhoai-user)

