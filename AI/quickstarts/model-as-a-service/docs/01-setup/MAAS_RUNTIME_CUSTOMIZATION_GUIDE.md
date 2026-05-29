# Configuring OpenShift AI Runtime: Gateway, Model registry, and Storage Integration

**Building Production-Ready Model Serving Infrastructure**

---

## Overview

With OpenShift AI platform components configured, the next critical step is establishing the runtime infrastructure that enables actual model serving operations. The runtime layer provides the essential services that connect your AI platform to production workloads: API gateways for model access, centralized model registries for version control, and storage integration for data science workflows.

This guide addresses the configuration of the `maas-runtime` Helm chart, which deploys and configures the operational infrastructure required for production model serving on Red Hat OpenShift AI.

## The Runtime Configuration Challenge

Organizations that successfully deploy OpenShift AI platform components often encounter significant challenges when configuring the runtime layer. The runtime infrastructure must address multiple critical requirements simultaneously:

**Gateway and routing complexity**:
- Secure ingress configuration for model endpoints
- TLS certificate management and renewal
- Traffic routing and load balancing
- Rate limiting and quota enforcement

**Model registry requirements**:
- Centralized model versioning and metadata management
- Integration with object storage backends (IBM Fusion, S3-compatible)
- Database configuration for registry persistence
- Service exposure and ingress configuration

**Storage integration challenges**:
- Workbench storage for data science teams
- Data connection management for model training
- Resource allocation and quota management
- Network policy configuration for security

**Access control and security**:
- Tier-based access control with rate limiting
- RBAC configuration for model deployments
- Authentication and authorization integration
- Network policies for workload isolation

## Runtime Components

The `maas-runtime` chart configures six primary infrastructure components:

**Gateway API**: Provides ingress gateway for model endpoint access with TLS termination, traffic routing, and rate limiting capabilities.

**Model Registry**: Establishes centralized repository for model metadata and artifacts with IBM Fusion Object Storage integration, version control, and catalog management.

**Workbench Storage**: Configures IBM Fusion Object Storage integration for data science workbenches, enabling persistent storage for notebooks and datasets.

**Tier-Based Access Control**: Implements user group management with configurable rate limiting tiers for different user classes (free, premium, enterprise).

**RBAC Configuration**: Establishes role-based access control for model deployment operations, ensuring proper authorization for model lifecycle management.

**Monitoring Integration**: Configures optional Grafana dashboards and Prometheus metrics for runtime observability.

## Guide Objectives

This guide provides:

- **Configuration patterns**: Detailed examples for gateway, registry, and storage configuration
- **Integration guidance**: IBM Fusion Object Storage and S3-compatible backend integration
- **Security configuration**: RBAC, network policies, and access control implementation
- **Deployment procedures**: Step-by-step installation and validation processes
- **Troubleshooting guidance**: Common issues and resolution strategies

## Target Audience

This guide serves:

- **Platform Engineers**: Configuring runtime infrastructure for model serving operations
- **Storage Administrators**: Integrating IBM Fusion or S3-compatible storage backends
- **Security Engineers**: Implementing access control and network policies
- **DevOps Teams**: Managing runtime deployment and operational procedures
- **ML Engineers**: Understanding runtime capabilities and constraints

## Prerequisites

### Required: Platform Components Configured

This guide assumes the OpenShift AI platform components are configured. If not completed:

**Option 1**: Follow the [Platform Customization Guide](MAAS_PLATFORM_CUSTOMIZATION_GUIDE.md) (30 minutes)

**Option 2**: Quick platform deployment if already familiar:
```bash
# Deploy platform components
helm install maas-platform \
  quickstarts/model-as-a-service/deploy/maas-platform/ \
  --set global.wildcardDomain=$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}') \
  --wait \
  --timeout 15m

# Verify platform deployment
oc get datasciencecluster -n redhat-ods-operator
```

### What You Need

- ✅ OpenShift 4.20+ cluster with cluster-admin access
- ✅ OpenShift AI operators installed
- ✅ Platform components configured (DataScienceCluster ready)
- ✅ IBM Fusion Object Storage or S3-compatible storage (for registry and workbench)
- ✅ Helm 3.x installed
- ✅ Understanding of Kubernetes networking and storage concepts

**Platform not configured?** Complete the [Platform Customization Guide](MAAS_PLATFORM_CUSTOMIZATION_GUIDE.md) first, then return here.

---

## Table of Contents

1. [Understanding Runtime Architecture](#understanding-runtime-architecture)
2. [Global Configuration](#global-configuration)
3. [Gateway API Configuration](#gateway-api-configuration)
4. [Model Registry Configuration](#model-registry-configuration)
5. [Workbench Storage Configuration](#workbench-configuration)
6. [Access Control and Security](#tier-based-access-control)
7. [Deployment and Validation](#installation)
8. [Troubleshooting](#troubleshooting)
9. [Next Steps](#next-steps)

---

## Understanding Runtime Architecture

### Component Relationships

```
┌─────────────────────────────────────────────────────────────┐
│                   Model Serving Requests                    │
│                    (External Traffic)                       │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                      Gateway API                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │
│  │ TLS Ingress  │  │ Rate Limiting│  │   Routing    │    │
│  └──────────────┘  └──────────────┘  └──────────────┘    │
└─────────────────────────────────────────────────────────────┘
                              ↓
        ┌─────────────────────┼─────────────────────┐
        ↓                     ↓                     ↓
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│    Model     │    │   Model      │    │  Workbench   │
│   Registry   │    │  Inference   │    │   Storage    │
│              │    │   Services   │    │              │
└──────────────┘    └──────────────┘    └──────────────┘
        ↓                                       ↓
┌──────────────┐                      ┌──────────────┐
│ IBM Fusion   │                      │ IBM Fusion   │
│   Storage    │                      │   Storage    │
│ (Registry)   │                      │ (Workbench)  │
└──────────────┘                      └──────────────┘
```

### Deployment Dependencies

```text
maas-operators (installed) ✅
    ↓
maas-platform (configured) ✅
    ↓
maas-runtime (configuring) ← You are here
    ↓
maas-model-service (deploy models)
```

### Key Integration Points

**Storage Integration**: IBM Fusion Object Storage provides S3-compatible backend for both model registry artifacts and workbench persistent storage.

**Gateway Integration**: Kuadrant Gateway API provides ingress routing, TLS termination, and rate limiting for model endpoints.

**Registry Integration**: Model Registry integrates with OpenShift AI dashboard for model lifecycle management and version control.

**RBAC Integration**: Role-based access control ensures proper authorization for model deployment and management operations.

---

## Helm Chart Details

**Chart Location:** `quickstarts/model-as-a-service/deploy/maas-runtime/`

**Configuration:** Defined in [deploy/maas-runtime/values.yaml](../deploy/maas-runtime/values.yaml)

**Purpose:**
- Deploys Gateway API for model endpoint routing
- Configures Model Registry with IBM Fusion Object Storage
- Sets up workbench storage for data scientists
- Implements tier-based access control and rate limiting
- Configures RBAC for model deployments
- Integrates monitoring and observability

---

## Global Configuration

### Basic Settings

```yaml
global:
  # OpenShift cluster wildcard domain (e.g., apps.cluster.example.com)
  wildcardDomain: apps.cluster.example.com
  
  # Name of the certificate secret for ingress (leave empty for self-signed)
  wildcardCertName: ""
  
  # Default namespace for model deployments
  modelsNamespace: maas-models
  
  # Tools image for jobs (should contain oc, kubectl, bash)
  toolsImage: image-registry.openshift-image-registry.svc:5000/openshift/tools:latest
```

**Customization:**

- **wildcardDomain**: Set to your OpenShift cluster's wildcard domain. Find it with:
  ```bash
  oc get ingresses.config/cluster -o jsonpath='{.spec.domain}'
  ```

- **wildcardCertName**: If you have a custom TLS certificate secret, specify its name. Leave empty to use OpenShift's default certificates.

- **modelsNamespace**: Change if you want to deploy models to a different namespace. This namespace will be created automatically.

- **toolsImage**: Use a custom image if you need specific tools. The default uses OpenShift's built-in tools image.

## Gateway API Configuration

The Gateway API provides ingress access to deployed models.

### Configuration

```yaml
gateway:
  # Enable GatewayClass and Gateway creation
  enabled: true

  # Create the cluster GatewayClass resource
  createGatewayClass: true

  # Gateway name
  name: openshift-ai-inference
  
  # Gateway namespace
  namespace: openshift-ingress
  
  # GatewayClass name
  gatewayClassName: openshift-ai-inference
  
  # Controller name for GatewayClass
  controllerName: openshift.io/gateway-controller/v1
  
  # Istio revision label (optional)
  istioRevision: openshift-gateway
  
  # Listeners configuration
  listeners:
    - allowedRoutes:
        namespaces:
          from: All
      name: http
      port: 80
      protocol: HTTP
    - allowedRoutes:
        namespaces:
          from: All
      name: https
      port: 443
      protocol: HTTPS
      tls:
        certificateRefs:
          - group: ''
            kind: Secret
            name: router-certs-default
        mode: Terminate
```

**Customization:**

- **enabled**: Set to `false` to skip Gateway creation if you have an existing gateway.

- **createGatewayClass**: Set to `false` if the GatewayClass already exists in your cluster.

- **name**: Change the gateway name if needed for your organization's naming conventions.

- **namespace**: The gateway is typically deployed in `openshift-ingress`. Change only if you have a custom ingress setup.

- **listeners**: Modify to add custom ports or protocols. The default configuration supports both HTTP (port 80) and HTTPS (port 443).

- **tls.certificateRefs**: Update the secret name if using a custom TLS certificate.

## Tier-Based Access Control

Configure user access tiers with different rate limits.

### Configuration

```yaml
tiers:
  # Free tier - basic access
  free:
    requestRates:
      - limit: 5
        window: 2m
    tokenRates:
      - limit: 100
        window: 1m
  
  # Premium tier - enhanced access
  premium:
    requestRates:
      - limit: 20
        window: 2m
    tokenRates:
      - limit: 10000
        window: 1m
  
  # Enterprise tier - full access
  enterprise:
    requestRates:
      - limit: 50
        window: 2m
    tokenRates:
      - limit: 20000
        window: 1m

# User to tier mapping
userMapping:
  free:
    - user1
    - user2
  premium:
    - user3
    - user4
  enterprise:
    - admin
    - poweruser
```

**Customization:**

- **requestRates**: Define the maximum number of API requests per time window.
  - `limit`: Number of requests allowed
  - `window`: Time window (e.g., `1m`, `2m`, `1h`)

- **tokenRates**: Define the maximum number of tokens (for LLM models) per time window.
  - `limit`: Number of tokens allowed
  - `window`: Time window

- **userMapping**: Map OpenShift users to tiers. Get user list with:
  ```bash
  oc get users
  ```

**Example Custom Tier:**

```yaml
tiers:
  developer:
    requestRates:
      - limit: 10
        window: 1m
    tokenRates:
      - limit: 5000
        window: 1m

userMapping:
  developer:
    - dev-user1
    - dev-user2
```

## Monitoring and Observability

Configure monitoring and Grafana dashboards.

### Configuration

```yaml
monitoring:
  # Enable monitoring stack
  enabled: true
  
  # Cluster monitoring configuration
  clusterMonitoring:
    enabled: true
    userWorkloadMonitoring: true
  
  # Grafana configuration
  grafana:
    enabled: true
    namespace: grafana
    
    # Grafana instance selectors (labels to match Grafana CR)
    selectors:
      app: grafana
    
    # Create console link for Grafana
    consoleLink:
      enabled: true
      displayName: "MaaS Metrics Dashboard"
      section: "Observability"
    
    # Default dashboards to deploy
    dashboards:
      maasOverview:
        enabled: true
      modelMetrics:
        enabled: true
      gpuUtilization:
        enabled: true
```

**Customization:**

- **enabled**: Set to `false` to disable monitoring completely.

- **clusterMonitoring.userWorkloadMonitoring**: Enable to collect metrics from user workloads.

- **grafana.enabled**: Set to `false` if you don't want Grafana dashboards.

- **grafana.namespace**: Change if Grafana is deployed in a different namespace.

- **grafana.selectors**: Update to match your Grafana instance labels.

- **dashboards**: Enable/disable specific dashboards as needed.

## Authentication and Authorization

Configure Keycloak for authentication (optional).

### Configuration

```yaml
authentication:
  # Keycloak configuration (optional)
  keycloak:
    enabled: false
    namespace: keycloak
    
    # Realm configuration
    realm:
      name: maas
      displayName: "MaaS Platform"
      
      # Admin user
      admin:
        username: admin
        password: ""  # Set via --set or secure method
      
      # Default user configuration
      user:
        password: ""  # Set via --set or secure method
        count: 5  # Creates user1-user5
    
    # Remove kubeadmin user after Keycloak setup
    removeKubeAdmin: false
    
    # OAuth integration
    oauth:
      enabled: true
```

**Customization:**

- **enabled**: Set to `true` to enable Keycloak authentication.

- **namespace**: Change if deploying Keycloak to a different namespace.

- **realm.name**: Customize the Keycloak realm name.

- **admin.username**: Change the admin username.

- **admin.password**: Set via command line for security:
  ```bash
  helm install maas-runtime ... --set authentication.keycloak.realm.admin.password=<password>
  ```

- **user.count**: Number of default users to create (user1, user2, etc.).

- **removeKubeAdmin**: Set to `true` to remove the default kubeadmin user after Keycloak is configured (use with caution).

## RBAC Configuration

Configure role-based access control for model deployments.

### Configuration

```yaml
rbac:
  # Create default roles and bindings
  enabled: true
  
  # Service account for model deployments
  modelServiceAccount:
    name: maas-model-sa
    namespace: maas-models
```

**Customization:**

- **enabled**: Set to `false` to skip RBAC resource creation (not recommended).

- **modelServiceAccount.name**: Change the service account name if needed.

- **modelServiceAccount.namespace**: Should match `global.modelsNamespace`.

## Model Registry Configuration

Configure the Model Registry for storing model metadata and artifacts.

### Basic Configuration

```yaml
modelRegistry:
  # Enable Model Registry
  enabled: true

  # Namespace for Model Registry
  namespace: rhoai-model-registries
  createNamespace: false
  
  # Model Registry instance name
  name: model-registry
```

### IBM Fusion Object Storage Configuration

```yaml
  objectStorage:
    # Enable IBM Fusion Object Storage (required)
    enabled: true
    
    # Automatic bucket creation using OpenShift Data Foundation (ODF)
    autoCreateBucket: true
    
    # OpenShift Data Foundation StorageClass
    odfStorageClass: openshift-storage.noobaa.io
    
    # BucketClass to use
    bucketClass: noobaa-default-bucket-class
    
    # Bucket retention policy settings (optional)
    bucketRetentionPolicy: false
    
    # Maximum number of objects in bucket (optional)
    maxObjects: ""
    
    # Maximum bucket size (optional, e.g., "100Gi", "1Ti")
    maxSize: ""
    
    # Fusion endpoint URL (only required if autoCreateBucket: false)
    endpoint: ""
    
    # Fusion bucket name for model artifacts
    bucket: model-registry-artifacts
    
    # Fusion region
    region: us-south
    
    # Fusion credentials (only required if autoCreateBucket: false)
    accessKeyId: ""
    secretAccessKey: ""
    
    # SSL verification (recommended: true)
    verifySSL: true
    
    # Storage class for objects
    storageClass: STANDARD
```

**Customization:**

- **enabled**: Set to `false` to disable Model Registry.

- **namespace**: Change if Model Registry should be in a different namespace. Note: This namespace is typically created by the DataScienceCluster.

- **createNamespace**: Set to `true` only if the namespace doesn't exist and won't be created by DataScienceCluster.

- **objectStorage.autoCreateBucket**: 
  - `true` (recommended): Automatically creates a bucket using OpenShift Data Foundation
  - `false`: Requires manual bucket creation and credentials

- **objectStorage.odfStorageClass**: Change if using a different ODF StorageClass. List available classes:
  ```bash
  oc get storageclass | grep noobaa
  ```

- **objectStorage.bucketClass**: Change to use a different bucket class with specific data placement policies.

- **objectStorage.maxObjects** and **maxSize**: Set quotas for the bucket.

- **objectStorage.endpoint**, **accessKeyId**, **secretAccessKey**: Only needed when `autoCreateBucket: false`. For manual configuration:
  ```bash
  helm install maas-runtime ... \
    --set modelRegistry.objectStorage.autoCreateBucket=false \
    --set modelRegistry.objectStorage.endpoint=https://s3.example.com \
    --set modelRegistry.objectStorage.accessKeyId=<key> \
    --set modelRegistry.objectStorage.secretAccessKey=<secret>
  ```

### Database Configuration

```yaml
  database:
    # Database type: postgres (default) or mysql
    type: postgres
    
    # Use external database or deploy one
    external: false
    
    # External database configuration
    externalDatabase:
      host: ""
      port: 5432
      database: modelregistry
      username: modelregistry
      password: ""
      sslMode: require
    
    # Internal database configuration (if external: false)
    internalDatabase:
      storageSize: 10Gi
      storageClassName: ""  # Use default
      resources:
        limits:
          cpu: "1"
          memory: 2Gi
        requests:
          cpu: 500m
          memory: 1Gi
```

**Customization:**

- **external**: 
  - `false` (default): Deploys a PostgreSQL database in the cluster
  - `true`: Use an external database

- **externalDatabase**: Configure when `external: true`:
  ```bash
  helm install maas-runtime ... \
    --set modelRegistry.database.external=true \
    --set modelRegistry.database.externalDatabase.host=postgres.example.com \
    --set modelRegistry.database.externalDatabase.password=<password>
  ```

- **internalDatabase.storageSize**: Adjust based on expected model metadata volume.

- **internalDatabase.storageClassName**: Specify a StorageClass or leave empty for default.

- **internalDatabase.resources**: Adjust CPU and memory based on workload.

### Service and Ingress Configuration

```yaml
  service:
    type: ClusterIP
    restPort: 8080
    grpcPort: 9090
  
  ingress:
    enabled: true
    hostname: ""
    tls:
      enabled: true
      secretName: ""
```

**Customization:**

- **service.type**: Usually `ClusterIP`. Change to `LoadBalancer` or `NodePort` if needed.

- **ingress.enabled**: Set to `false` to disable external access.

- **ingress.hostname**: Leave empty for auto-generation based on `global.wildcardDomain`.

### Versioning and Metadata Configuration

```yaml
  versioning:
    enabled: true
    format: semantic  # semantic (1.0.0) or timestamp (20240101-120000)
    autoIncrement: true
  
  metadata:
    requiredFields:
      - name
      - description
      - framework
      - version
    customFields: []
```

**Customization:**

- **versioning.format**: Choose between `semantic` (1.0.0) or `timestamp` (20240101-120000).

- **metadata.requiredFields**: Add or remove required fields for model registration.

- **metadata.customFields**: Add custom metadata fields:
  ```yaml
  customFields:
    - field: use-case
      type: string
      required: false
    - field: accuracy
      type: float
      required: false
  ```

### Catalog Integration

```yaml
  catalogIntegration:
    enabled: true
    autoRegister: true
    syncSchedule: "0 3 * * *"  # Daily at 3 AM
```

**Customization:**

- **enabled**: Set to `false` to disable catalog integration.

- **autoRegister**: Automatically register models from the catalog.

- **syncSchedule**: Cron expression for sync schedule. Examples:
  - `"0 3 * * *"`: Daily at 3 AM
  - `"0 */6 * * *"`: Every 6 hours
  - `"0 0 * * 0"`: Weekly on Sunday

## Workbench Configuration

Configure IBM Fusion Object Storage integration for data science workbenches.

### Basic Configuration

```yaml
workbench:
  # Enable Workbench IBM Fusion object storage integration
  enabled: true

  # Namespace for workbenches
  namespace: rhods-notebooks
  createNamespace: false
```

### IBM Fusion Object Storage Configuration

```yaml
  objectStorage:
    # Enable IBM Fusion Object Storage (required)
    enabled: true
    
    # Use OpenShift Data Foundation (ODF) for automatic bucket creation
    useODF: true
    
    # OpenShift Data Foundation StorageClass
    odfStorageClass: openshift-storage.noobaa.io
    
    # BucketClass to use
    bucketClass: noobaa-default-bucket-class
    
    # Bucket retention policy settings (optional)
    bucketRetentionPolicy: false
    
    # Maximum number of objects in bucket (optional)
    maxObjects: ""
    
    # Maximum bucket size (optional)
    maxSize: ""
    
    # Fusion endpoint URL (only required if useODF: false)
    endpoint: ""
    
    # Default bucket name for workbenches
    defaultBucket: workbench-data
    
    # Fusion region
    region: us-south
    
    # Fusion credentials (only required if useODF: false)
    accessKeyId: ""
    secretAccessKey: ""
    
    # SSL verification
    verifySSL: true
    
    # Storage class for objects
    storageClass: STANDARD
    
    # Auto-create per-user buckets
    autoCreateBuckets: true
    
    # Bucket name prefix for per-user buckets
    bucketPrefix: workbench-
```

**Customization:**

- **useODF**: 
  - `true` (recommended): Automatically creates buckets using ODF
  - `false`: Requires manual bucket creation

- **autoCreateBuckets**: When `true`, creates separate buckets for each user with the specified prefix.

- **bucketPrefix**: Prefix for per-user buckets (e.g., `workbench-user1`, `workbench-user2`).

### Data Connections Configuration

```yaml
  dataConnections:
    enabled: true
    createDefault: true
    defaultConnectionName: fusion-storage
```

**Customization:**

- **enabled**: Set to `false` to disable data connections.

- **createDefault**: Creates a default IBM Fusion storage connection.

- **defaultConnectionName**: Name of the default connection visible in OpenShift AI dashboard.

### Storage Configuration

```yaml
  storage:
    defaultPVCSize: 20Gi
    
    sharedStorage:
      enabled: false
      size: 100Gi
      storageClassName: ""
```

**Customization:**

- **defaultPVCSize**: Default size for workbench persistent volumes.

- **sharedStorage.enabled**: Set to `true` to create shared storage for team collaboration.

- **sharedStorage.size**: Size of the shared storage PVC.

### Resource Configuration

```yaml
  resources:
    defaultRequests:
      cpu: "1"
      memory: 8Gi
    
    defaultLimits:
      cpu: "2"
      memory: 16Gi
    
    gpu:
      enabled: true
      defaultLimit: "0"  # 0 = no GPU by default
```

**Customization:**

- **defaultRequests** and **defaultLimits**: Adjust based on your workload requirements.

- **gpu.enabled**: Set to `false` if GPUs are not available.

- **gpu.defaultLimit**: Set to `"1"` or higher to allocate GPUs by default.

### Idle Culling Configuration

```yaml
  culling:
    enabled: true
    idleTimeout: 60  # minutes
    checkInterval: 5  # minutes
```

**Customization:**

- **enabled**: Set to `false` to disable automatic culling of idle workbenches.

- **idleTimeout**: Minutes of inactivity before a workbench is stopped.

- **checkInterval**: How often to check for idle workbenches.

### Network Policies

```yaml
  networkPolicies:
    enabled: false
    allowIngress: []
    allowEgress:
      - 0.0.0.0/0
```

**Customization:**

- **enabled**: Set to `true` to enable network policies for workbenches.

- **allowIngress**: Define allowed ingress sources:
  ```yaml
  allowIngress:
    - namespaceSelector:
        matchLabels:
          name: openshift-ingress
  ```

- **allowEgress**: Define allowed egress destinations (CIDR blocks).

## Network Policies

Global network policies for the models namespace.

### Configuration

```yaml
networkPolicies:
  enabled: false
  
  # Allow ingress from specific namespaces
  allowFrom:
    - openshift-ingress
    - openshift-monitoring
```

**Customization:**

- **enabled**: Set to `true` to enable network policies.

- **allowFrom**: List of namespaces allowed to access model services.

## Common Labels and Annotations

Apply labels and annotations to all resources.

### Configuration

```yaml
# Additional labels to apply to all resources
commonLabels: {}
  # environment: production
  # team: ai-platform

# Additional annotations to apply to all resources
commonAnnotations: {}
  # managed-by: helm
```

**Customization:**

Add custom labels and annotations for your organization:

```yaml
commonLabels:
  environment: production
  team: ai-platform
  cost-center: "12345"

commonAnnotations:
  managed-by: helm
  contact: ai-team@example.com
```

## Installation

### Prerequisites

1. OpenShift cluster with cluster-admin access
2. Helm 3.x installed
3. OpenShift CLI (oc) installed
4. Logged into the cluster:
   ```bash
   oc login <cluster-url>
   ```

### Installation Steps

1. **Create a custom values file** (recommended):
   ```bash
   cp quickstarts/model-as-a-service/deploy/maas-runtime/values.yaml my-values.yaml
   ```

2. **Edit the values file** with your customizations:
   ```bash
   vim my-values.yaml
   ```

3. **Install using the installation script**:
   ```bash
   cd quickstarts/model-as-a-service
   ./scripts/install-runtime.sh my-values.yaml
   ```

   Or install directly with Helm:
   ```bash
   helm install maas-runtime \
     quickstarts/model-as-a-service/deploy/maas-runtime \
     -f my-values.yaml \
     --timeout 20m
   ```

4. **Verify the installation**:
   ```bash
   # Check Model Registry
   oc get modelregistry -n rhoai-model-registries
   
   # Check Gateway
   oc get gateway -n openshift-ingress
   
   # Check workbench storage
   oc get secret workbench-fusion-storage -n rhods-notebooks
   ```

### Setting Sensitive Values

For sensitive values like passwords and API keys, use `--set` flags instead of storing them in files:

```bash
helm install maas-runtime \
  quickstarts/model-as-a-service/deploy/maas-runtime \
  -f my-values.yaml \
  --set authentication.keycloak.realm.admin.password=<admin-password> \
  --set authentication.keycloak.realm.user.password=<user-password> \
  --set modelRegistry.objectStorage.accessKeyId=<access-key> \
  --set modelRegistry.objectStorage.secretAccessKey=<secret-key>
```

### Upgrading

To upgrade an existing installation with new values:

```bash
helm upgrade maas-runtime \
  quickstarts/model-as-a-service/deploy/maas-runtime \
  -f my-values.yaml \
  --timeout 20m
```

### Uninstalling

To remove the MaaS Runtime:

```bash
helm uninstall maas-runtime
```

**Note**: This will not delete PVCs or namespaces. To clean up completely:

```bash
# Delete PVCs
oc delete pvc -n rhoai-model-registries --all
oc delete pvc -n rhods-notebooks --all

# Delete namespaces (if created by the chart)
oc delete namespace maas-models
```

## Troubleshooting

### Common Issues

1. **ObjectBucketClaim not binding**:
   ```bash
   # Check OBC status
   oc get obc -n rhoai-model-registries
   
   # Check ODF operator
   oc get csv -n openshift-storage | grep odf
   ```

2. **Model Registry not ready**:
   ```bash
   # Check ModelRegistry status
   oc get modelregistry -n rhoai-model-registries -o yaml
   
   # Check database pod
   oc get pods -n rhoai-model-registries
   oc logs -n rhoai-model-registries model-registry-db-<pod-id>
   ```

3. **Gateway not working**:
   ```bash
   # Check Gateway status
   oc get gateway -n openshift-ingress
   
   # Check GatewayClass
   oc get gatewayclass
   ```

4. **Workbench storage not configured**:
   ```bash
   # Check setup job
   oc get job -n rhods-notebooks
   oc logs -n rhods-notebooks job/workbench-fusion-setup
   ```

### Getting Help

- Check the logs of setup jobs:
  ```bash
  oc logs -n rhoai-model-registries job/model-registry-fusion-setup
  oc logs -n rhods-notebooks job/workbench-fusion-setup
  ```

- Review Helm release status:
  ```bash
  helm status maas-runtime
  helm get values maas-runtime
  ```

- Check resource events:
  ```bash
  oc get events -n rhoai-model-registries --sort-by='.lastTimestamp'
  ```

## Next Steps

After installing the MaaS Runtime:

1. **Deploy models**: See [DEPLOYING_MODEL_SERVICES.md](../03-model-deployment/DEPLOYING_MODEL_SERVICES.md)
2. **Configure Model Registry**: See [ADDING_MODELS_TO_REGISTRY.md](../02-model-catalog-and-registry/ADDING_MODELS_TO_REGISTRY.md)
3. **Set up workbenches**: See [WORKBENCH_STORAGE_GUIDE.md](../04-workbench-configuration/WORKBENCH_STORAGE_GUIDE.md)
4. **Add models to registry**: See [ADDING_MODELS_TO_REGISTRY.md](../02-model-catalog-and-registry/ADDING_MODELS_TO_REGISTRY.md)

## References

- [MaaS Platform Documentation](../../README.md)
- [Getting Started Guide](../GETTING_STARTED.md)
- [Operators Guide](MAAS_OPERATORS_GUIDE.md)
- [Platform Customization Guide](MAAS_PLATFORM_CUSTOMIZATION_GUIDE.md)
- [Red Hat OpenShift AI Documentation](https://access.redhat.com/documentation/en-us/red_hat_openshift_ai)
- [Gateway API Documentation](https://gateway-api.sigs.k8s.io/)
- [OpenShift Data Foundation Documentation](https://access.redhat.com/documentation/en-us/red_hat_openshift_data_foundation)

---
