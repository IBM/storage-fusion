# Managing the Catalog

**Who this is for:** The person who deploys and manages this Developer Hub —
registering clusters, editing `values.yaml`, and extending the catalog for
other teams.

**What you need:**

- Git access to the repository hosting this Helm chart
- `oc` CLI access to the target Fusion cluster
- Knowledge of which Fusion services are installed on that cluster

---

## How this catalog works

This Developer Hub is deployed via a Helm chart. The catalog — every entity,
every endpoint, every self-service template — is driven by one file:

```
AI/quickstarts/fusion-developerhub/deploy/helm/environments/<your-env>/values.yaml
```

You edit that file and deploy. RHDH picks up the changes automatically.

**Two deployment models are supported:**

| Model | How you deploy changes |
|---|---|
| Helm only | `helm upgrade` with the updated values file |
| Helm + ArgoCD | Push to Git — ArgoCD detects the change and syncs |

Either way, the file you edit is the same.

### The branch you deployed with is the branch you must edit

This is the most common source of confusion. The Helm chart was deployed from
a specific Git branch. Changes on any other branch have no effect until they
are deployed.

**To find your deployed branch:**

1. Open your deployed `values.yaml` (the one used in `helm upgrade` or your
   ArgoCD Application spec)
2. Find the `fusionServices.gitBranch` field — that is the branch this
   deployment is tracking
3. Always check out that branch before making changes

---

## Register a Fusion AI Service cluster

### Step 1 — Gather what you need

Before opening any template or editing any file, collect the following:

**For all cluster types:**

| What | How to find it |
|---|---|
| Cluster short name | You choose — lowercase, hyphens only, e.g. `prod-east` |
| OCP API URL | Run `oc cluster-info` or open the OCP console → top-right menu → Copy Login Command |
| Services installed | Check the IBM Fusion console UI or ask your cluster admin |

**If registering CAS:**

```bash
# Confirm CAS is installed and get the version
oc get casinstall -n ibm-cas -o jsonpath='{.items[0].status.installedVersion}'
```

**If registering DCS:**

```bash
# Confirm DCS is installed and get the version
oc get spectrumDiscover -n ibm-data-cataloging -o jsonpath='{.items[0].status.installedVersion}'
```

**If registering WXO:**

```bash
# Get the WXO UI route
oc get route -n watson-orchestrate
```

**Decide: proxy-only or self-hosted?**

| Type | When to use | Extra requirements |
|---|---|---|
| `proxy-only` | You have the OCP API URL. All service URLs are derived from it automatically. No cluster API access needed from RHDH. | None — just the OCP API URL |
| `self-hosted` | You want the Kubernetes plugin tab to show live cluster resources (pods, CRDs, custom resources). | ServiceAccount token per service, stored as a secret in the RHDH namespace |

**Start with `proxy-only`.** It covers catalog discovery, all endpoint links,
and MCP access without any token setup. Switch to `self-hosted` only if you
need the live Kubernetes plugin tab.

---

### Step 2 — Use the self-service template

Go to **Create** in the left nav and open the template for your service.

There are four templates available. Use the one that matches your situation:

| Template | When to use |
|---|---|
| **Add IBM Fusion CAS Cluster** | Register a CAS instance — fills all endpoints automatically |
| **Add IBM Fusion DCS Cluster** | Register a DCS instance — fills all endpoints automatically |
| **Add watsonx Orchestrate Instance** | Register a WXO instance |
#### Add IBM Fusion CAS Cluster — form fields

| Field | What to enter |
|---|---|
| Cluster Name | Short id, e.g. `prod-east`. Lowercase, hyphens only. This becomes the entity name. |
| OCP API URL | `https://api.<domain>:6443` — all CAS endpoints are derived from this automatically |
| CAS Installed Version | Optional. Run `oc get casinstall -n ibm-cas -o jsonpath='{.items[0].status.installedVersion}'` |

All CAS endpoints are auto-derived from the OCP API URL — Console, Swagger,
MCP standard, MCP streamable, Health, OCP Console.

#### Add IBM Fusion DCS Cluster — form fields

| Field | What to enter |
|---|---|
| Cluster Name | Short id, e.g. `prod-east`. Lowercase, hyphens only. |
| OCP API URL | `https://api.<domain>:6443` — all DCS endpoints are derived automatically |
| DCS Installed Version | Optional. Run `oc get spectrumDiscover -n ibm-data-cataloging -o jsonpath='{.items[0].status.installedVersion}'` |

All DCS endpoints are auto-derived — Console, MCP HTTP, MCP SSE, OCP Console.

#### Add watsonx Orchestrate Instance — form fields

| Field | What to enter |
|---|---|
| Cluster Name | Short id for this cluster |
| WXO UI URL | `https://wxo.apps.<domain>` — run `oc get route -n watson-orchestrate` to find it |
| OCP Namespace | Default: `watson-orchestrate` |
| WXO Version | Optional |

**After the template runs**, check the output page. The catalog entry is
registered and visible immediately. Copy the values.yaml snippet shown — use
that in Step 3.

---

### Step 3 — Make it permanent

The catalog entry created by the template is held in memory. To make it
survive pod restarts you must add it to `values.yaml` and deploy.

**1. Check out the right branch**

```bash
git clone https://github.com/IBM/storage-fusion.git
cd storage-fusion
git checkout <your-deployed-branch>   # must match fusionServices.gitBranch in your values
```

**2. Open the values file**

```
AI/quickstarts/fusion-developerhub/deploy/helm/environments/<your-env>/values.yaml
```

Find the `fusionServices.clusters:` section.

**3. Paste the snippet from the template output page**

The template output page shows the exact block to add. Paste it under
`clusters:`.

**proxy-only example (for reference):**

```yaml
- name: prod-east
  ocpApiUrl: https://api.prod-east.example.com:6443
  clusterType: proxy-only
  services:
    cas:
      enabled: true
      version: "1.1.5"
      namespace: ibm-cas
    dcs:
      enabled: true
      version: "2.5.3"
      namespace: ibm-data-cataloging
    wxo:                          # only include if WXO is installed
      enabled: true
      wxoUrl: "https://wxo.apps.prod-east.example.com"
      namespace: watson-orchestrate
      version: "2.1.0"
```

**self-hosted — extra steps before editing values.yaml:**

First, create SA tokens on the cluster and store them as secrets in the
RHDH namespace. **Never paste tokens in Git.**

```bash
# Create tokens (adjust SA names for your cluster)
oc create token -n ibm-data-cataloging isd-sa --duration=8760h
oc create token -n ibm-cas cas-sa --duration=8760h

# Store as a secret in the RHDH namespace
# CLUSTER_ID_UPPER = cluster name uppercased, hyphens → underscores
# e.g. prod-east → PROD_EAST
oc create secret generic fusion-prod-east-tokens \
  --from-literal=FUSION_PROD_EAST_SA_TOKEN=<dcs-token> \
  --from-literal=FUSION_PROD_EAST_CAS_SA_TOKEN=<cas-token> \
  -n <rhdh-namespace>
```

Then in `values.yaml`, reference the env var names (not the token values):

```yaml
- name: prod-east
  ocpApiUrl: https://api.prod-east.example.com:6443
  clusterType: self-hosted
  services:
    dcs:
      enabled: true
      version: "2.5.3"
      namespace: ibm-data-cataloging
      k8s:
        tokenEnvVar: FUSION_PROD_EAST_SA_TOKEN
        labelSelector: "app=isd,component=discover"
    cas:
      enabled: true
      version: "1.1.5"
      namespace: ibm-cas
      k8s:
        tokenEnvVar: FUSION_PROD_EAST_CAS_SA_TOKEN
        labelSelector: "app.kubernetes.io/name=cas.isf.ibm.com"
```

**4. Deploy**

```bash
# Helm only
helm upgrade <release-name> . -f environments/<your-env>/values.yaml -n <namespace>

# ArgoCD — push and sync
git add environments/<your-env>/values.yaml
git commit -m "feat: register prod-east cluster"
git push origin <your-deployed-branch>
```

### Step 4 — Verify

Open the [catalog](/catalog?filters%5Bkind%5D=component&filters%5Btype%5D=fusion-service)
and confirm your cluster entry is present. Click it → **Links** tab → verify
the endpoints look correct for your cluster domain.

---

## Update an existing cluster entry

Find the cluster block in `values.yaml` and make your change:

| Change | What to do |
|---|---|
| Add a new service (e.g. CAS was added later) | Append the service block under `services:` |
| Update a version | Change the `version:` field |
| Disable a service | Set `enabled: false` |
| Remove a cluster entirely | Delete the entire cluster block |

Push / deploy as in Step 3 above.

---

## Extend the catalog — add new services or templates

### Path A — One-off entry (no template needed)

For a service or entity that only needs to be registered once and won't be
self-served by other teams.

**If it maps to a cluster** → add it to `values.yaml` under `clusters[]`
as shown above.

**If it's a standalone entity** (a shared tool, a new team group, a
documentation component) → open
`deploy/helm/templates/fusion-platform-entities-configmap.yaml`
and append a new `---` YAML document inside the `data:` key. The catalog
location entry already covers this file — nothing else to change.

### Path B — Reusable self-service template

For a service that other teams should be able to register themselves —
the way CAS, DCS, and WXO work today.

Four changes are required:

**1. Add the template ConfigMap**

Open `deploy/helm/templates/fusion-scaffolder-templates-configmap.yaml`
and add a new `---` ConfigMap block. Copy the `wxo-template` block as your
pattern. Give it a unique `name:` (e.g. `my-service-template`) and put your
Backstage Template YAML in the `data:` key.

**2. Add a volume** in `deploy/helm/templates/developerhub-instance.yaml`
(around the existing volume blocks):

```yaml
- name: my-service-template
  configMap:
    name: my-service-template
    defaultMode: 0444
```

**3. Add a volumeMount** in the same file (around the existing mount blocks):

```yaml
- name: my-service-template
  mountPath: /opt/app-root/src/my-service-template.yaml
  subPath: my-service-template.yaml
```

**4. Add a catalog location** in
`deploy/helm/templates/app-config-catalog-locations.yaml`:

```yaml
- type: file
  target: /opt/app-root/src/my-service-template.yaml
  rules:
    - allow: [Template]
```

After deploying, the template appears in **Create** for anyone on the team.

---

## Reference — which file to edit for what

| I want to... | Edit this file |
|---|---|
| Register a new cluster or add a service to an existing one | `environments/<env>/values.yaml` → `fusionServices.clusters[]` |
| Add a static entity — Domain, System, Group, or standalone Component | `deploy/helm/templates/fusion-platform-entities-configmap.yaml` |
| Add or modify a self-service template | `deploy/helm/templates/fusion-scaffolder-templates-configmap.yaml` |
| Wire a new template into RHDH (volume + mount) | `deploy/helm/templates/developerhub-instance.yaml` |
| Add a new catalog location | `deploy/helm/templates/app-config-catalog-locations.yaml` |
| Change backend auth rules, proxy endpoints, or k8s plugin config | `deploy/helm/templates/fusion-ai-services-configmap.yaml` |
| Add TechDocs to a component | Add `backstage.io/techdocs-ref` annotation to the Component entity + add `mkdocs.yml` and `docs/` to the repo path |

> **Rule:** Never add `catalog.locations` to any file other than
> `app-config-catalog-locations.yaml`. Backstage uses array-replace semantics —
> the last loaded config wins and silently drops everything else.
