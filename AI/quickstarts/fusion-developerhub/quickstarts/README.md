# Quickstarts

Interactive tutorials for IBM Fusion Developer Hub that appear in the OpenShift web console.

## What are Console QuickStarts?

Console QuickStarts are guided, interactive tutorials that appear directly in the OpenShift web console. They provide step-by-step instructions to help users learn how to use Fusion Developer Hub features.

## Available QuickStarts

### Getting Started with IBM Fusion Developer Hub

**File**: `console-quickstarts/getting-started.yaml`  
**Duration**: ~15 minutes  
**Level**: Beginner

Learn how to:
- Navigate the Developer Hub interface
- Create AI-powered applications
- Use modernization tools
- Deploy to OpenShift

## Deployment

### Deploy to Your Cluster

```bash
# Deploy the getting started tutorial
oc apply -f console-quickstarts/getting-started.yaml

# Verify deployment
oc get consolequickstart fusion-getting-started
```

### Access in OpenShift Console

1. Open your OpenShift web console
2. Click the **"?"** (help) icon in the top right corner
3. Select **"Quick Starts"** from the dropdown
4. Find **"Getting Started with IBM Fusion Developer Hub"**
5. Click **"Start"** to begin the tutorial

## Creating Custom QuickStarts

See the [Console QuickStarts README](./console-quickstarts/README.md) for detailed information on creating your own interactive tutorials.

## Related Resources

- **[Console QuickStarts Documentation](./console-quickstarts/README.md)** - Detailed guide for creating QuickStarts
- **[Testing Utilities](../testing/)** - Tools for testing operator deployments
- **[Getting Started Guide](../docs/getting-started/operator-getting-started.md)** - Full deployment documentation
- **[Helm Charts](../helm-charts/fusion-developer-hub/)** - Production deployment

---

[← Back to Repository Root](../)