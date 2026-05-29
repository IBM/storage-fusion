# Adding Fusion Services to Developer Hub Catalog

This guide explains how to add IBM Fusion AI services, APIs, and components to your Developer Hub catalog for easy discovery and consumption by development teams.

## Overview

Developer Hub uses a **Software Catalog** to organize and discover:
- **Components**: Applications, services, libraries
- **APIs**: REST APIs, GraphQL endpoints, gRPC services
- **Resources**: Databases, message queues, AI models, storage
- **Systems**: Collections of related components
- **Domains**: Business areas or product lines

## Table of Contents

1. [Understanding Catalog Entities](#understanding-catalog-entities)
2. [Adding Fusion AI Services](#adding-fusion-ai-services)
3. [Documenting APIs](#documenting-apis)
4. [Adding AI Models as Resources](#adding-ai-models-as-resources)
5. [Creating Service Documentation](#creating-service-documentation)
6. [Organizing with Systems and Domains](#organizing-with-systems-and-domains)
7. [Automated Discovery](#automated-discovery)

---

## Understanding Catalog Entities

### Entity Types

```yaml
# Component - A piece of software (service, library, app)
kind: Component
spec:
  type: service  # or: library, website, etc.
  lifecycle: production  # or: experimental, deprecated
  owner: team-ai

# API - An interface for a component
kind: API
spec:
  type: openapi  # or: graphql, grpc, asyncapi
  lifecycle: production
  owner: team-ai

# Resource - Infrastructure or external dependency
kind: Resource
spec:
  type: ai-model  # or: database, queue, storage
  owner: team-ai

# System - Collection of related entities
kind: System
spec:
  owner: team-ai

# Domain - Business area
kind: Domain
spec:
  owner: team-ai
```

---

## Adding Fusion AI Services

### Step 1: Create catalog-info.yaml

Create a `catalog-info.yaml` file in your service repository:

```yaml
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: watsonx-code-assistant
  title: watsonx Code Assistant
  description: AI-powered code generation and completion service using IBM Granite models
  annotations:
    # Link to source code
    github.com/project-slug: ibm/watsonx-code-assistant
    
    # Link to documentation
    backstage.io/techdocs-ref: dir:.
    
    # Grafana dashboard
    grafana/dashboard-selector: watsonx-code-assistant
    
    # Prometheus metrics
    prometheus.io/rule: watsonx-code-assistant
    
    # Kubernetes deployment
    backstage.io/kubernetes-id: watsonx-code-assistant
    
    # Fusion AI specific
    fusion.ibm.com/ai-model: granite-code-20b
    fusion.ibm.com/model-version: v2.0
    fusion.ibm.com/capability: code-generation
  
  tags:
    - ai
    - code-generation
    - watsonx
    - granite
    - fusion
  
  links:
    - url: https://watsonx-code.example.com
      title: Service Dashboard
      icon: dashboard
    
    - url: https://watsonx-code.example.com/api/docs
      title: API Documentation
      icon: docs
    
    - url: https://grafana.example.com/d/watsonx-code
      title: Metrics Dashboard
      icon: grafana
    
    - url: https://wiki.example.com/watsonx-code
      title: User Guide
      icon: help

spec:
  type: service
  lifecycle: production
  owner: team-ai-platform
  
  # System this component belongs to
  system: fusion-ai-platform
  
  # APIs this component provides
  providesApis:
    - watsonx-code-api
  
  # APIs this component consumes
  consumesApis:
    - watsonx-foundation-api
  
  # Resources this component depends on
  dependsOn:
    - resource:granite-code-model
    - resource:watsonx-postgres-db
```

### Step 2: Add API Definition

Create an API entity for the service:

```yaml
apiVersion: backstage.io/v1alpha1
kind: API
metadata:
  name: watsonx-code-api
  title: watsonx Code Assistant API
  description: REST API for AI-powered code generation and completion
  annotations:
    github.com/project-slug: ibm/watsonx-code-assistant
  
  tags:
    - ai
    - rest-api
    - code-generation
    - fusion

spec:
  type: openapi
  lifecycle: production
  owner: team-ai-platform
  system: fusion-ai-platform
  
  # OpenAPI specification
  definition: |
    openapi: 3.0.0
    info:
      title: watsonx Code Assistant API
      version: 2.0.0
      description: AI-powered code generation and completion
    
    servers:
      - url: https://watsonx-code.example.com/api/v2
        description: Production
    
    paths:
      /generate:
        post:
          summary: Generate code from prompt
          requestBody:
            required: true
            content:
              application/json:
                schema:
                  type: object
                  properties:
                    prompt:
                      type: string
                      description: Code generation prompt
                    language:
                      type: string
                      enum: [python, java, javascript, go]
                    max_tokens:
                      type: integer
                      default: 500
          responses:
            '200':
              description: Generated code
              content:
                application/json:
                  schema:
                    type: object
                    properties:
                      code:
                        type: string
                      confidence:
                        type: number
                      model:
                        type: string
      
      /complete:
        post:
          summary: Complete code snippet
          requestBody:
            required: true
            content:
              application/json:
                schema:
                  type: object
                  properties:
                    code:
                      type: string
                    cursor_position:
                      type: integer
          responses:
            '200':
              description: Code completions
              content:
                application/json:
                  schema:
                    type: object
                    properties:
                      completions:
                        type: array
                        items:
                          type: object
```

### Step 3: Add AI Model as Resource

```yaml
apiVersion: backstage.io/v1alpha1
kind: Resource
metadata:
  name: granite-code-model
  title: IBM Granite Code 20B Model
  description: Large language model optimized for code generation and understanding
  annotations:
    fusion.ibm.com/model-id: granite-code-20b-instruct-v2
    fusion.ibm.com/model-size: 20B
    fusion.ibm.com/training-date: 2024-03-15
    fusion.ibm.com/license: IBM Research License
  
  tags:
    - ai-model
    - llm
    - code-generation
    - granite
    - fusion

spec:
  type: ai-model
  owner: team-ai-research
  system: fusion-ai-platform
  
  # Model specifications
  dependsOn:
    - resource:watsonx-inference-engine
```

### Step 4: Register in Developer Hub

Add to your Helm values:

```yaml
developerHub:
  catalog:
    enabled: true
    locations:
      # Direct file reference
      - type: url
        target: https://github.com/your-org/watsonx-code-assistant/blob/main/catalog-info.yaml
      
      # Discover all catalog files in a repository
      - type: url
        target: https://github.com/your-org/fusion-services/blob/main/catalog-info.yaml
        rules:
          - allow: [Component, API, Resource, System, Domain]
```

---

## Complete Fusion AI Service Example

Here's a complete example for a Fusion AI modernization service:

```yaml
---
# Domain: Application Modernization
apiVersion: backstage.io/v1alpha1
kind: Domain
metadata:
  name: app-modernization
  title: Application Modernization
  description: Tools and services for modernizing legacy applications
  tags:
    - modernization
    - transformation
    - fusion
spec:
  owner: team-modernization

---
# System: Transformation Advisor
apiVersion: backstage.io/v1alpha1
kind: System
metadata:
  name: transformation-advisor
  title: IBM Transformation Advisor
  description: Automated application analysis and modernization recommendations
  annotations:
    fusion.ibm.com/capability: application-analysis
  tags:
    - modernization
    - analysis
    - fusion
spec:
  owner: team-modernization
  domain: app-modernization

---
# Component: Transformation Advisor Service
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: transformation-advisor-service
  title: Transformation Advisor Service
  description: Analyzes applications and provides modernization recommendations
  annotations:
    github.com/project-slug: ibm/transformation-advisor
    backstage.io/techdocs-ref: dir:.
    backstage.io/kubernetes-id: transformation-advisor
    fusion.ibm.com/capability: application-analysis
    fusion.ibm.com/ai-powered: "true"
  
  tags:
    - modernization
    - analysis
    - ai
    - fusion
  
  links:
    - url: https://transformation-advisor.example.com
      title: Web Console
      icon: dashboard
    - url: https://transformation-advisor.example.com/api/docs
      title: API Docs
      icon: docs

spec:
  type: service
  lifecycle: production
  owner: team-modernization
  system: transformation-advisor
  
  providesApis:
    - transformation-advisor-api
  
  consumesApis:
    - watsonx-analysis-api
  
  dependsOn:
    - resource:transformation-advisor-db
    - resource:granite-analysis-model

---
# API: Transformation Advisor API
apiVersion: backstage.io/v1alpha1
kind: API
metadata:
  name: transformation-advisor-api
  title: Transformation Advisor API
  description: REST API for application analysis and modernization
  tags:
    - modernization
    - rest-api
    - fusion

spec:
  type: openapi
  lifecycle: production
  owner: team-modernization
  system: transformation-advisor
  
  definition: |
    openapi: 3.0.0
    info:
      title: Transformation Advisor API
      version: 1.0.0
    
    paths:
      /analyze:
        post:
          summary: Analyze application for modernization
          requestBody:
            content:
              multipart/form-data:
                schema:
                  type: object
                  properties:
                    application:
                      type: string
                      format: binary
          responses:
            '200':
              description: Analysis results
      
      /recommendations:
        get:
          summary: Get modernization recommendations
          parameters:
            - name: analysisId
              in: query
              required: true
              schema:
                type: string
          responses:
            '200':
              description: Recommendations

---
# Resource: Analysis AI Model
apiVersion: backstage.io/v1alpha1
kind: Resource
metadata:
  name: granite-analysis-model
  title: Granite Application Analysis Model
  description: AI model for analyzing application architecture and dependencies
  annotations:
    fusion.ibm.com/model-id: granite-analysis-v1
    fusion.ibm.com/model-type: analysis
  tags:
    - ai-model
    - analysis
    - fusion

spec:
  type: ai-model
  owner: team-ai-research
  system: transformation-advisor
```

---

## Adding Multiple Fusion Services

### Create a Fusion Services Repository

1. **Create repository structure:**

```
fusion-services/
├── catalog-info.yaml          # Main catalog file
├── services/
│   ├── watsonx-code/
│   │   ├── catalog-info.yaml
│   │   ├── api-spec.yaml
│   │   └── docs/
│   ├── transformation-advisor/
│   │   ├── catalog-info.yaml
│   │   └── docs/
│   ├── mono2micro/
│   │   ├── catalog-info.yaml
│   │   └── docs/
│   └── app-navigator/
│       ├── catalog-info.yaml
│       └── docs/
├── models/
│   ├── granite-code.yaml
│   ├── granite-chat.yaml
│   └── granite-analysis.yaml
└── systems/
    ├── ai-platform.yaml
    └── modernization-platform.yaml
```

2. **Main catalog-info.yaml:**

```yaml
apiVersion: backstage.io/v1alpha1
kind: Location
metadata:
  name: fusion-services-catalog
  description: IBM Fusion AI Services Catalog
  annotations:
    fusion.ibm.com/catalog-version: v1.0.0
spec:
  type: url
  targets:
    # AI Services
    - ./services/watsonx-code/catalog-info.yaml
    - ./services/watsonx-chat/catalog-info.yaml
    
    # Modernization Services
    - ./services/transformation-advisor/catalog-info.yaml
    - ./services/mono2micro/catalog-info.yaml
    - ./services/app-navigator/catalog-info.yaml
    
    # AI Models
    - ./models/granite-code.yaml
    - ./models/granite-chat.yaml
    - ./models/granite-analysis.yaml
    
    # Systems and Domains
    - ./systems/ai-platform.yaml
    - ./systems/modernization-platform.yaml
```

3. **Register in Developer Hub:**

```yaml
developerHub:
  catalog:
    enabled: true
    locations:
      # Main Fusion services catalog
      - type: url
        target: https://github.com/your-org/fusion-services/blob/main/catalog-info.yaml
      
      # Individual service catalogs (optional, if not using Location)
      - type: url
        target: https://github.com/your-org/fusion-services/blob/main/services/*/catalog-info.yaml
```

---

## Creating Service Documentation

### TechDocs Integration

1. **Add mkdocs.yml to your service repository:**

```yaml
site_name: watsonx Code Assistant
site_description: AI-powered code generation service

nav:
  - Home: index.md
  - Getting Started:
    - Quick Start: getting-started/quickstart.md
    - Authentication: getting-started/auth.md
  - User Guide:
    - Code Generation: guide/generation.md
    - Code Completion: guide/completion.md
    - Best Practices: guide/best-practices.md
  - API Reference:
    - REST API: api/rest.md
    - Python SDK: api/python.md
    - JavaScript SDK: api/javascript.md
  - Examples:
    - Python: examples/python.md
    - Java: examples/java.md
    - JavaScript: examples/javascript.md

theme:
  name: material
  palette:
    primary: indigo

plugins:
  - techdocs-core
```

2. **Create documentation:**

```markdown
# docs/index.md

# watsonx Code Assistant

AI-powered code generation and completion using IBM Granite models.

## Features

- **Code Generation**: Generate complete functions from natural language
- **Code Completion**: Intelligent code completion as you type
- **Multi-Language**: Supports Python, Java, JavaScript, Go, and more
- **Context-Aware**: Understands your codebase context

## Quick Start

```python
from watsonx_code import CodeAssistant

# Initialize
assistant = CodeAssistant(api_key="your-key")

# Generate code
code = assistant.generate(
    prompt="Create a function to sort a list of dictionaries by a key",
    language="python"
)

print(code)
```

## Use Cases

- Accelerate development with AI-generated boilerplate
- Learn new languages and frameworks
- Refactor legacy code
- Generate unit tests automatically
```

3. **Link in catalog-info.yaml:**

```yaml
metadata:
  annotations:
    backstage.io/techdocs-ref: dir:.
```

---

## Automated Discovery

### GitHub/GitLab Discovery

Configure automatic discovery of catalog files:

```yaml
developerHub:
  catalog:
    enabled: true
    
    providers:
      github:
        - organization: your-org
          catalogPath: '/catalog-info.yaml'
          filters:
            branch: main
            repository: 'fusion-.*'  # Only repos starting with fusion-
          schedule:
            frequency: { hours: 1 }
            timeout: { minutes: 3 }
      
      gitlab:
        - host: gitlab.com
          group: fusion-services
          catalogPath: '/catalog-info.yaml'
```

### Fusion AI Provider

Configure Fusion-specific discovery:

```yaml
developerHub:
  catalog:
    providers:
      fusion:
        default:
          baseUrl: https://fusion-api.example.com
          schedule:
            frequency: { minutes: 30 }
            timeout: { minutes: 3 }
```

---

## Best Practices

### 1. Consistent Naming

```yaml
# Use consistent naming patterns
metadata:
  name: watsonx-code-assistant  # kebab-case
  title: watsonx Code Assistant  # Title Case
```

### 2. Rich Metadata

```yaml
metadata:
  description: >
    Detailed description explaining what the service does,
    who should use it, and key capabilities.
  
  tags:
    - ai              # Technology
    - code-generation # Capability
    - fusion          # Platform
    - production      # Lifecycle
```

### 3. Comprehensive Links

```yaml
links:
  - url: https://service.example.com
    title: Service Dashboard
    icon: dashboard
  
  - url: https://service.example.com/api/docs
    title: API Documentation
    icon: docs
  
  - url: https://grafana.example.com/d/service
    title: Metrics
    icon: grafana
  
  - url: https://wiki.example.com/service
    title: User Guide
    icon: help
  
  - url: https://slack.com/channels/service-support
    title: Support Channel
    icon: chat
```

### 4. Clear Ownership

```yaml
spec:
  owner: team-ai-platform  # Must match a Group in catalog
  system: fusion-ai-platform
  domain: artificial-intelligence
```

### 5. Lifecycle Management

```yaml
spec:
  lifecycle: production  # or: experimental, deprecated
```

---

## Validation

### Validate Catalog Files

```bash
# Install Backstage CLI
npm install -g @backstage/cli

# Validate catalog file
backstage-cli catalog:validate catalog-info.yaml

# Validate OpenAPI spec
backstage-cli api:validate api-spec.yaml
```

### Test in Developer Hub

```bash
# Check catalog processing
kubectl logs -n fusion-hub deployment/developerhub -c backstage | grep catalog

# View catalog entities
curl https://developerhub.example.com/api/catalog/entities
```

---

## Next Steps

1. **Create Templates**: See [Adding Self-Service Templates](./adding-self-service-templates.md)
2. **Customize Homepage**: See [Homepage Customization](./homepage-customization.md)
3. **Monitor Catalog**: Set up alerts for catalog processing errors

## Related Documentation

- [Backstage Catalog](https://backstage.io/docs/features/software-catalog/)
- [TechDocs](https://backstage.io/docs/features/techdocs/)
- [API Documentation](https://backstage.io/docs/features/software-catalog/descriptor-format#kind-api)