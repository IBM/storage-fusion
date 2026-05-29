# OpenShift Console QuickStarts

Interactive tutorials for the OpenShift web console that guide users through IBM Fusion Developer Hub features.

## What are Console QuickStarts?

Console QuickStarts are interactive, step-by-step tutorials that appear directly in the OpenShift web console. They provide:

- ✅ **Guided Learning**: Step-by-step instructions with clear objectives
- ✅ **Interactive Verification**: Users confirm completion of each step
- ✅ **Contextual Help**: Tutorials appear alongside the actual interface
- ✅ **Progress Tracking**: Resume where you left off across sessions
- ✅ **No Installation Required**: Works directly in the browser

## Available QuickStarts

### Getting Started with IBM Fusion Developer Hub

**File**: `getting-started.yaml`  
**Duration**: ~15 minutes  
**Level**: Beginner

#### What You'll Learn

1. **Explore the Developer Hub**
   - Navigate the interface
   - Understand key features
   - Access catalog and templates

2. **Create an AI-Powered Application**
   - Use software templates
   - Leverage AI code generation
   - Configure application settings

3. **Use Modernization Tools**
   - Analyze existing applications
   - Generate migration plans
   - Apply modernization patterns

4. **Deploy to OpenShift**
   - Create deployment pipelines
   - Monitor application health
   - Access deployed applications

#### Prerequisites

- Access to IBM Fusion Developer Hub
- Basic understanding of application development
- (Optional) Existing application to modernize

## Deployment

### Deploy to Your Cluster

```bash
# Deploy the QuickStart
oc apply -f getting-started.yaml

# Verify deployment
oc get consolequickstart fusion-getting-started
```

### Access in OpenShift Console

1. Open your OpenShift web console
2. Click the **"?"** (help) icon in the top right corner
3. Select **"Quick Starts"** from the dropdown
4. Find **"Getting Started with IBM Fusion Developer Hub"**
5. Click **"Start"** to begin the tutorial

## QuickStart Structure

### Metadata
```yaml
apiVersion: console.openshift.io/v1
kind: ConsoleQuickStart
metadata:
  name: fusion-getting-started
spec:
  displayName: Getting Started with IBM Fusion Developer Hub
  durationMinutes: 15
  icon: <base64-encoded-svg>
  description: Learn how to use IBM Fusion Developer Hub
```

### Sections

1. **Introduction**: Overview and prerequisites
2. **Tasks**: Step-by-step instructions with verification
3. **Conclusion**: Summary and next steps

### Task Format
```yaml
tasks:
  - title: Task Name
    description: |
      Instructions for the user
    review:
      instructions: |
        Verification steps
      failedTaskHelp: |
        Troubleshooting guidance
```

## Creating Custom QuickStarts

### Template Structure

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-quickstart
  labels:
    app.kubernetes.io/name: my-quickstart
    app.kubernetes.io/component: quickstart
data:
  quickstart.yaml: |
    apiVersion: console.openshift.io/v1
    kind: ConsoleQuickStart
    metadata:
      name: my-quickstart
    spec:
      displayName: My Custom QuickStart
      durationMinutes: 10
      description: Custom tutorial
      introduction: |
        Introduction text
      tasks:
        - title: First Task
          description: Task instructions
          review:
            instructions: Verification steps
      conclusion: |
        Conclusion text
```

### Best Practices

1. **Keep it Short**: 10-20 minutes maximum
2. **Clear Instructions**: Use simple, direct language
3. **Verify Steps**: Include verification for each task
4. **Provide Help**: Add troubleshooting guidance
5. **Test Thoroughly**: Test with real users before deploying

### Icon Guidelines

- **Format**: SVG (base64 encoded)
- **Size**: 24x24 pixels
- **Colors**: Use brand colors
- **Simple**: Keep design minimal

Generate base64 icon:
```bash
base64 -i icon.svg | tr -d '\n'
```

## Testing QuickStarts

### Local Testing

1. Deploy to a test cluster:
   ```bash
   oc apply -f my-quickstart.yaml
   ```

2. Access in OpenShift Console

3. Complete the tutorial as a user would

4. Verify all steps work correctly

### Validation Checklist

- [ ] All links work correctly
- [ ] Instructions are clear and accurate
- [ ] Verification steps are achievable
- [ ] Duration estimate is accurate
- [ ] Help text is useful
- [ ] Conclusion provides next steps
- [ ] No typos or formatting issues

## Troubleshooting

### QuickStart Not Appearing

```bash
# Check if deployed
oc get consolequickstart

# Check ConfigMap
oc get configmap -l app.kubernetes.io/component=quickstart

# View logs
oc logs -n openshift-console <console-pod>
```

### QuickStart Shows Errors

```bash
# Validate YAML syntax
oc apply --dry-run=client -f quickstart.yaml

# Check for validation errors
oc describe consolequickstart <name>
```

### Updates Not Showing

```bash
# Delete and recreate
oc delete -f quickstart.yaml
oc apply -f quickstart.yaml

# Clear browser cache
# Refresh OpenShift Console
```

## Examples

### Minimal QuickStart

```yaml
apiVersion: console.openshift.io/v1
kind: ConsoleQuickStart
metadata:
  name: minimal-example
spec:
  displayName: Minimal Example
  durationMinutes: 5
  description: A minimal QuickStart example
  introduction: |
    This is a simple example.
  tasks:
    - title: Complete This Task
      description: |
        Follow these steps:
        1. Do something
        2. Verify it worked
      review:
        instructions: |
          Did you complete the task?
  conclusion: |
    Great job! You completed the QuickStart.
```

## Resources

### Official Documentation
- [OpenShift QuickStarts Guide](https://docs.openshift.com/container-platform/latest/web_console/creating-quick-start-tutorials.html)
- [QuickStart API Reference](https://docs.openshift.com/container-platform/latest/rest_api/console_apis/consolequickstart-console-openshift-io-v1.html)

### Examples
- [OpenShift QuickStarts Repository](https://github.com/openshift/console/tree/master/frontend/packages/console-app/src/components/quick-starts/data)
- [Community QuickStarts](https://github.com/redhat-developer/openshift-quickstarts)

## Contributing

To contribute a new QuickStart:

1. Create your QuickStart YAML file
2. Test thoroughly in a cluster
3. Submit a pull request
4. Include screenshots and description
5. Update this README

---

[← Back to Quickstarts](../README.md) | [← Back to Repository Root](../../)

## Related Resources

- [Getting Started Guide](../../docs/getting-started/operator-getting-started.md) - Full deployment documentation
- [Testing Utilities](../../testing/) - Tools for testing deployments
- [Architecture Documentation](../../docs/architecture/) - System design details