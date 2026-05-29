# Developer Hub Homepage Customization

This guide explains how to customize the IBM Fusion Developer Hub homepage with your company branding, welcome messages, and featured content.

## Overview

The Developer Hub homepage can be customized to:
- Display your company logo and branding
- Show custom welcome messages highlighting Fusion AI capabilities
- Feature quick access links to common tasks
- Highlight AI-powered development and modernization tools
- Display multiple timezone clocks for distributed teams

## Configuration

All homepage customization is done through the `developerHub.config.homepage` section in your values file.

### Basic Example

```yaml
developerHub:
  config:
    title: "Acme Corp Developer Hub"
    organizationName: "Acme Corporation"
    
    homepage:
      # Company branding
      companyLogo: "https://cdn.acme.com/logo.png"
      companyLogoIcon: "https://cdn.acme.com/icon.png"
      
      # Welcome message
      welcomeTitle: "Welcome to Acme Developer Hub"
      welcomeMessage: |
        Build and modernize applications faster with AI-powered tools.
      
      # Quick access links
      quickLinks:
        - title: "Create Application"
          description: "Start with AI templates"
          url: "/create"
          icon: "add"
        - title: "Browse Catalog"
          description: "Discover components"
          url: "/catalog"
          icon: "catalog"
```

## Logo Configuration

### Company Logo

The main logo appears in the top-left corner of the Developer Hub interface.

**Recommended specifications:**
- Format: PNG, SVG, or WebP
- Size: 200x50px (or similar 4:1 aspect ratio)
- Background: Transparent
- File size: < 50KB for best performance

**Options:**

1. **External URL:**
```yaml
homepage:
  companyLogo: "https://your-cdn.com/logo.png"
```

2. **Base64 encoded (for small logos):**
```yaml
homepage:
  companyLogo: "data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjAwIi..."
```

3. **IBM Fusion AI Logo (default):**
```yaml
homepage:
  companyLogo: ""  # Uses default Fusion branding
```

### Company Logo Icon

A smaller icon used in mobile views and compact layouts.

**Recommended specifications:**
- Format: PNG or SVG
- Size: 32x32px (square)
- Background: Transparent

```yaml
homepage:
  companyLogoIcon: "https://your-cdn.com/icon-32x32.png"
```

## Welcome Message

Customize the homepage welcome section to highlight your organization's use of Fusion AI.

```yaml
homepage:
  welcomeTitle: "Welcome to [Your Company] Developer Hub"
  welcomeMessage: |
    Accelerate your development with:
    • AI-powered code generation using IBM watsonx
    • Automated application modernization
    • Intelligent API discovery and integration
    • Real-time collaboration tools
```

**Tips:**
- Keep the title concise (< 60 characters)
- Use bullet points in the message for readability
- Highlight key Fusion AI capabilities relevant to your teams
- Update seasonally or for major initiatives

## Quick Links

Quick links provide one-click access to common tasks and features.

```yaml
homepage:
  quickLinks:
    - title: "Create New App"
      description: "Start with AI-powered templates"
      url: "/create"
      icon: "add"
    
    - title: "AI Assistant"
      description: "Get intelligent coding help"
      url: "/ai-assistant"
      icon: "smart_toy"
    
    - title: "Modernize Legacy App"
      description: "Analyze and transform applications"
      url: "/transformation-advisor"
      icon: "autorenew"
    
    - title: "API Catalog"
      description: "Discover and integrate APIs"
      url: "/catalog?filters[kind]=api"
      icon: "api"
    
    - title: "Documentation"
      description: "Learn about Fusion capabilities"
      url: "/docs"
      icon: "docs"
    
    - title: "Templates"
      description: "Browse application templates"
      url: "/create"
      icon: "template"
```

**Available Icons:**
- `add` - Plus sign
- `catalog` - Grid/catalog icon
- `docs` - Document icon
- `api` - API/integration icon
- `smart_toy` - AI/robot icon
- `autorenew` - Refresh/transform icon
- `template` - Template/blueprint icon
- `code` - Code brackets
- `cloud` - Cloud icon
- `security` - Shield/lock icon

## Featured Content

Highlight key capabilities and resources on the homepage.

```yaml
homepage:
  featuredContent:
    - title: "🚀 AI-Powered Development"
      description: "Leverage IBM watsonx and Granite models for intelligent development"
      links:
        - text: "Explore AI Templates"
          url: "/create?filters[tags]=ai"
        - text: "AI Capabilities Guide"
          url: "/docs/ai-capabilities"
        - text: "Code Generation Demo"
          url: "/docs/demos/code-generation"
    
    - title: "🔄 Application Modernization"
      description: "Transform legacy applications with automated tools"
      links:
        - text: "Transformation Advisor"
          url: "/transformation-advisor"
        - text: "Mono2Micro Analysis"
          url: "/mono2micro"
        - text: "Migration Patterns"
          url: "/docs/modernization/patterns"
    
    - title: "📊 Analytics & Insights"
      description: "Track development metrics and AI usage"
      links:
        - text: "Team Dashboard"
          url: "/analytics/team"
        - text: "AI Usage Reports"
          url: "/analytics/ai-usage"
        - text: "Cost Optimization"
          url: "/analytics/costs"
    
    - title: "🎓 Learning Resources"
      description: "Get started with Fusion Developer Hub"
      links:
        - text: "Quick Start Guide"
          url: "/docs/getting-started"
        - text: "Video Tutorials"
          url: "/docs/tutorials"
        - text: "Best Practices"
          url: "/docs/best-practices"
```

## Complete Example

Here's a complete example for a company using Fusion AI:

```yaml
developerHub:
  config:
    title: "Acme Corp Developer Hub"
    organizationName: "Acme Corporation"
    
    homepage:
      # Branding
      companyLogo: "https://cdn.acme.com/acme-logo-200x50.png"
      companyLogoIcon: "https://cdn.acme.com/acme-icon-32x32.png"
      
      # Welcome section
      welcomeTitle: "Welcome to Acme Developer Hub"
      welcomeMessage: |
        Accelerate innovation with AI-powered development tools:
        • Generate code with IBM watsonx and Granite models
        • Modernize legacy applications automatically
        • Discover and integrate APIs intelligently
        • Collaborate with AI-assisted code reviews
        
        Join 500+ developers building the future at Acme!
      
      # Quick access
      quickLinks:
        - title: "Create Application"
          description: "Start with AI-powered templates"
          url: "/create"
          icon: "add"
        
        - title: "AI Code Assistant"
          description: "Get intelligent coding help"
          url: "/ai-assistant"
          icon: "smart_toy"
        
        - title: "Modernize App"
          description: "Transform legacy applications"
          url: "/transformation-advisor"
          icon: "autorenew"
        
        - title: "API Catalog"
          description: "Browse 200+ internal APIs"
          url: "/catalog?filters[kind]=api"
          icon: "api"
        
        - title: "Documentation"
          description: "Guides and tutorials"
          url: "/docs"
          icon: "docs"
        
        - title: "Team Dashboard"
          description: "View team metrics"
          url: "/analytics/team"
          icon: "dashboard"
      
      # Featured content
      featuredContent:
        - title: "🚀 AI-Powered Development"
          description: "Build faster with IBM watsonx and Granite models"
          links:
            - text: "AI Templates Library"
              url: "/create?filters[tags]=ai"
            - text: "Code Generation Guide"
              url: "/docs/ai/code-generation"
            - text: "AI Best Practices"
              url: "/docs/ai/best-practices"
        
        - title: "🔄 Legacy Modernization"
          description: "Transform monoliths to microservices"
          links:
            - text: "Start Analysis"
              url: "/transformation-advisor"
            - text: "Success Stories"
              url: "/docs/case-studies"
            - text: "Migration Playbook"
              url: "/docs/modernization/playbook"
        
        - title: "📚 New to Fusion?"
          description: "Get started in minutes"
          links:
            - text: "5-Minute Quick Start"
              url: "/docs/quickstart"
            - text: "Video Tutorials"
              url: "/docs/tutorials"
            - text: "Live Training Schedule"
              url: "/training"
        
        - title: "🎯 This Week's Focus"
          description: "Q4 2024 Modernization Sprint"
          links:
            - text: "Sprint Goals"
              url: "/docs/sprints/q4-2024"
            - text: "Team Leaderboard"
              url: "/analytics/leaderboard"
            - text: "Submit Your App"
              url: "/modernization/submit"
```

## Deployment

After customizing your values file:

```bash
# Deploy new installation
helm install fusion-hub ./helm-charts/fusion-developer-hub \
  --namespace fusion-hub \
  --create-namespace \
  -f your-custom-values.yaml

# Update existing installation
helm upgrade fusion-hub ./helm-charts/fusion-developer-hub \
  --namespace fusion-hub \
  -f your-custom-values.yaml
```

Changes take effect immediately after the Developer Hub pods restart (typically 30-60 seconds).

## Best Practices

### Logo Guidelines

1. **Use vector formats (SVG)** when possible for crisp display at any resolution
2. **Optimize file sizes** - logos should be < 50KB
3. **Test on dark backgrounds** - ensure logo works with Developer Hub's dark theme
4. **Provide both full logo and icon** for best mobile experience

### Content Guidelines

1. **Keep welcome messages concise** - 3-5 bullet points maximum
2. **Update featured content regularly** - highlight current initiatives
3. **Use action-oriented link text** - "Start Analysis" vs "Click Here"
4. **Test all links** before deployment
5. **Consider your audience** - tailor content to developer needs

### Performance Tips

1. **Host logos on a CDN** for fast loading
2. **Limit quick links to 6-8 items** to avoid overwhelming users
3. **Keep featured content to 3-4 sections** for optimal layout
4. **Use relative URLs** when linking to Developer Hub pages

## Troubleshooting

### Logo Not Displaying

**Problem:** Logo URL returns 404 or CORS error

**Solution:**
```yaml
# Ensure URL is accessible
homepage:
  companyLogo: "https://your-cdn.com/logo.png"  # Must be publicly accessible

# Or use base64 encoding
homepage:
  companyLogo: "data:image/png;base64,iVBORw0KG..."
```

### Quick Links Not Working

**Problem:** Links return 404

**Solution:**
```yaml
# Use relative URLs for internal pages
quickLinks:
  - title: "Catalog"
    url: "/catalog"  # Correct - relative URL
    # url: "https://full-url.com/catalog"  # Avoid - may break

# For external links, use full URLs
  - title: "Company Wiki"
    url: "https://wiki.acme.com"  # Correct for external
```

### Changes Not Appearing

**Problem:** Updated values but homepage unchanged

**Solution:**
```bash
# Force pod restart
kubectl rollout restart deployment/developerhub -n fusion-hub

# Or delete pods to force recreation
kubectl delete pods -l app=developerhub -n fusion-hub

# Verify ConfigMap was updated
kubectl get configmap developerhub-app-config -n fusion-hub -o yaml
```

## Examples by Use Case

### Startup/Small Team

Focus on simplicity and getting started:

```yaml
homepage:
  welcomeTitle: "Welcome to DevHub"
  welcomeMessage: "Build faster with AI-powered tools"
  
  quickLinks:
    - title: "Create App"
      url: "/create"
      icon: "add"
    - title: "Browse Catalog"
      url: "/catalog"
      icon: "catalog"
    - title: "Docs"
      url: "/docs"
      icon: "docs"
```

### Enterprise

Comprehensive with governance and compliance:

```yaml
homepage:
  welcomeTitle: "Enterprise Developer Hub"
  welcomeMessage: |
    Secure, compliant, AI-powered development platform
    • SOC 2 Type II certified
    • GDPR compliant
    • 99.9% uptime SLA
  
  quickLinks:
    - title: "Create Application"
      url: "/create"
    - title: "Security Scan"
      url: "/security"
    - title: "Compliance Check"
      url: "/compliance"
    - title: "API Catalog"
      url: "/catalog?filters[kind]=api"
    - title: "Architecture Review"
      url: "/architecture"
    - title: "Cost Dashboard"
      url: "/analytics/costs"
```

### Modernization Focus

Highlight transformation capabilities:

```yaml
homepage:
  welcomeTitle: "Modernization Hub"
  welcomeMessage: "Transform legacy applications to cloud-native"
  
  featuredContent:
    - title: "🔄 Start Modernization"
      description: "Analyze and transform your applications"
      links:
        - text: "Upload Application"
          url: "/transformation-advisor/upload"
        - text: "View Analysis"
          url: "/transformation-advisor/results"
    
    - title: "📊 Track Progress"
      description: "Monitor modernization initiatives"
      links:
        - text: "Portfolio Dashboard"
          url: "/analytics/portfolio"
        - text: "ROI Calculator"
          url: "/analytics/roi"
```

## Related Documentation

- [Backstage Customization](https://backstage.io/docs/getting-started/homepage)
- [IBM Fusion AI Documentation](../README.md)
- [Deployment Guide](./operator-getting-started.md)
- [Troubleshooting Guide](./troubleshooting/README.md)

## Support

For questions or issues with homepage customization:
- Check the [Troubleshooting Guide](./troubleshooting/README.md)
- Review [Backstage Documentation](https://backstage.io/docs)
- Contact your platform team