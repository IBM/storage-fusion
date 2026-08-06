# IBM Fusion Developer Hub — Deployment Runbook

> **Who this is for:** A junior engineer deploying IBM Fusion Developer Hub for the first time.
> Every step is manual. Every command is shown in full. Read each step completely before running it.

---

## Before You Begin

### What you are building

You will deploy **IBM Red Hat Developer Hub (RHDH)** — branded as *IBM Fusion Developer Hub* —
onto an OpenShift cluster using ArgoCD (GitOps). At the end, a browser UI will show
catalog entries for every IBM Fusion HCI cluster you register.

### Two cluster concepts

Throughout this runbook, two different OpenShift clusters are involved:

| Name | What it is |
|---|---|
| **RHDH cluster** | The OpenShift cluster where Developer Hub itself runs. You deploy here. |
| **Fusion cluster** | A remote IBM Fusion HCI cluster whose services (DCS, CAS) you want to show in Developer Hub. |

You will log in and out of both clusters. Each time, the runbook tells you exactly which one to use.

### Two registration modes

| Mode | When to use | Requires tokens? |
|---|---|---|
| **self-hosted** | You have `oc` CLI access to the Fusion cluster | Yes — Phases 1–9 |
| **proxy-only** | You have no `oc` access to the Fusion cluster | No — skip Phase 2, follow Phase 8 |

---

## Gather Your Values

Fill in this table **before running any command**. Every `<PLACEHOLDER>` in this runbook maps to one row.

| Variable | What it is | How to find it |
|---|---|---|
| `CLUSTER_ID` | Short name you choose for the Fusion cluster | Make it up — e.g. `prod-east-01` |
| `CLUSTER_DOMAIN` | Base domain of the Fusion cluster, **without** leading `apps.` | Run `oc get ingress.config.openshift.io cluster -o jsonpath='{.spec.domain}'` on the Fusion cluster, then remove the leading `apps.` |
| `DCS_NAMESPACE` | Namespace where DCS runs on the Fusion cluster | `oc get pods -A \| grep isd` |
| `CAS_NAMESPACE` | Namespace where CAS runs on the Fusion cluster | `oc get pods -A \| grep cas` |
| `DCS_VERSION` | Installed DCS version | Run on Fusion cluster — see Phase 2, Step 2.2 |
| `CAS_VERSION` | Installed CAS version | Run on Fusion cluster — see Phase 2, Step 2.2 |
| `RWX_STORAGE_CLASS` | A storage class on the **RHDH cluster** that supports `ReadWriteMany` | `oc get storageclass` — look for CephFS or NFS |
| `GIT_REPO_URL` | Full URL of your Git repository | e.g. `https://github.ibm.com/your-org/Fusion-AI` |
| `GIT_BRANCH` | Branch ArgoCD will watch | e.g. `main` |
| `GITHUB_PAT` | GitHub Personal Access Token | GitHub → Settings → Developer settings → Tokens (needs `repo` read scope) |

**Derived values** — compute these from the table above before starting:

| Derived variable | How to compute |
|---|---|
| `OCP_API_URL` | `https://api.<CLUSTER_DOMAIN>:6443` |
| `WILDCARD_DOMAIN` | `apps.<CLUSTER_DOMAIN>` |
| `CLUSTER_ID_UPPER` | Uppercase `CLUSTER_ID`, replace every `-` with `_` |
| `DCS_TOKEN_KEY` | `FUSION_<CLUSTER_ID_UPPER>_SA_TOKEN` |
| `CAS_TOKEN_KEY` | `FUSION_<CLUSTER_ID_UPPER>_CAS_SA_TOKEN` |

**Example** — used in every command below:

| Variable | Example value |
|---|---|
| `CLUSTER_ID` | `prod-east-01` |
| `CLUSTER_DOMAIN` | `prod-east-01.fusion.example.com` |
| `OCP_API_URL` | `https://api.prod-east-01.fusion.example.com:6443` |
| `WILDCARD_DOMAIN` | `apps.prod-east-01.fusion.example.com` |
| `DCS_NAMESPACE` | `ibm-data-cataloging` |
| `CAS_NAMESPACE` | `ibm-cas` |
| `DCS_VERSION` | `2.5.3` |
| `CAS_VERSION` | `1.1.5` |
| `RWX_STORAGE_CLASS` | `ocs-storagecluster-cephfs` |
| `GIT_REPO_URL` | `https://github.ibm.com/your-org/Fusion-AI` |
| `GIT_BRANCH` | `main` |
| `CLUSTER_ID_UPPER` | `PROD_EAST_01` |
| `DCS_TOKEN_KEY` | `FUSION_PROD_EAST_01_SA_TOKEN` |
| `CAS_TOKEN_KEY` | `FUSION_PROD_EAST_01_CAS_SA_TOKEN` |

---

## Table of Contents

1. [Phase 0 — Check Prerequisites](#phase-0--check-prerequisites)
2. [Phase 1 — Fork and Clone the Repository](#phase-1--fork-and-clone-the-repository)
3. [Phase 2 — Create ServiceAccount Tokens on the Fusion Cluster](#phase-2--create-serviceaccount-tokens-on-the-fusion-cluster) *(self-hosted only)*
4. [Phase 3 — Edit the Configuration Files](#phase-3--edit-the-configuration-files)
5. [Phase 4 — Push Your Changes to Git](#phase-4--push-your-changes-to-git)
6. [Phase 5 — Create Kubernetes Secrets on the RHDH Cluster](#phase-5--create-kubernetes-secrets-on-the-rhdh-cluster)
7. [Phase 6 — Pre-create the Plugins Storage Volume](#phase-6--pre-create-the-plugins-storage-volume)
8. [Phase 7 — Apply the ArgoCD Application](#phase-7--apply-the-argocd-application)
9. [Phase 8 — Watch the Deployment Progress](#phase-8--watch-the-deployment-progress)
10. [Phase 9 — Verify the Deployment](#phase-9--verify-the-deployment)
11. [Phase 10 — Verify Catalog Entities in the UI](#phase-10--verify-catalog-entities-in-the-ui)
12. [Day-2: Add Another Cluster (Self-Hosted)](#day-2-add-another-cluster-self-hosted)
13. [Day-2: Add Another Cluster (Proxy-Only)](#day-2-add-another-cluster-proxy-only)
14. [Day-2: Update CAS or DCS Version](#day-2-update-cas-or-dcs-version)
15. [Day-2: Roll Back a Change](#day-2-roll-back-a-change)
16. [Troubleshooting](#troubleshooting)
17. [Quick Reference](#quick-reference)

---

## Phase 0 — Check Prerequisites

> **Where to run:** Your local workstation.

### Step 0.1 — Check that required tools are installed

Run each command. If a command is not found, install it using the instructions below.

```bash
oc version
```
Expected: `Client Version: 4.x.x` — must be 4.12 or later.
If missing: open your OpenShift cluster console, click **?** → **Command line tools**, download `oc`.

```bash
helm version
```
Expected: `version.BuildInfo{Version:"v3.x.x"...}` — must be 3.8 or later.
If missing (macOS): `brew install helm`
If missing (Linux): `curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash`

```bash
git --version
```
Expected: `git version 2.x.x`
If missing (macOS): `xcode-select --install`
If missing (Linux): `sudo apt install git` or `sudo yum install git`

```bash
python3 --version
```
Expected: `Python 3.x.x`
If missing (macOS): `brew install python3`
If missing (Linux): `sudo apt install python3`

---

### Step 0.2 — Log in to the RHDH cluster

The RHDH cluster is where Developer Hub will be deployed. You need cluster-admin access.

```bash
# Replace <RHDH_CLUSTER_DOMAIN> with your RHDH cluster domain:
oc login --server=https://api.<RHDH_CLUSTER_DOMAIN>:6443
```

After logging in, confirm you have the right permissions:

```bash
oc whoami
oc auth can-i create namespace --all-namespaces
```

Expected output of the second command: `yes`
If you see `no`, contact your cluster admin — you need cluster-admin privileges.

---

### Step 0.3 — Find your wildcard domain and storage class

Run these two commands on the RHDH cluster:

```bash
oc get ingress.config.openshift.io cluster -o jsonpath='{.spec.domain}'
```

Example output: `apps.prod-east-01.fusion.example.com`
This is your `WILDCARD_DOMAIN`. Your `CLUSTER_DOMAIN` is the same without the leading `apps.`.

```bash
oc get storageclass
```

Look for a storage class with `ReclaimPolicy=Delete` and a provisioner that supports `ReadWriteMany` (RWX). Typical names:
- `ocs-storagecluster-cephfs` ← use this if present
- `nfs-client`
- `azurefile`

Write this down as your `RWX_STORAGE_CLASS`.

---

### Step 0.4 — Confirm ArgoCD is running

```bash
oc get pods -n openshift-gitops | grep -v Completed
```

Expected: all pods show `Running`. You should see at least:
- `openshift-gitops-server-*`
- `openshift-gitops-repo-server-*`
- `openshift-gitops-application-controller-*`

If no pods appear, ArgoCD is not installed. Install the OpenShift GitOps operator from OperatorHub before continuing.

---

**✅ Phase 0 complete when:**
- [ ] `oc`, `helm`, `git`, `python3` all return a version number
- [ ] `oc auth can-i create namespace --all-namespaces` returns `yes`
- [ ] `WILDCARD_DOMAIN` is written down
- [ ] `RWX_STORAGE_CLASS` is written down
- [ ] ArgoCD pods are `Running` in `openshift-gitops`

---

## Phase 1 — Fork and Clone the Repository

> **Where to run:** Your web browser and local workstation.
> ArgoCD deploys from a Git repository. You must have your own copy (fork) so you can commit changes.

---

### Step 1.1 — Fork the repository

1. Open `https://github.ibm.com/ProjectAbell/Fusion-AI` in your browser
2. Click **Fork** in the top-right corner
3. Select your GitHub organization or personal account
4. Wait for the fork to be created

You now have your own copy at `https://github.ibm.com/<YOUR-ORG>/Fusion-AI`.
Write this URL down as `GIT_REPO_URL`.

---

### Step 1.2 — Clone your fork to your workstation

Open a terminal and run:

```bash
# Replace <YOUR-ORG> with your GitHub organization name:
git clone https://github.ibm.com/<YOUR-ORG>/Fusion-AI.git
cd Fusion-AI
```

Example:
```bash
git clone https://github.ibm.com/your-org/Fusion-AI.git
cd Fusion-AI
```

---

### Step 1.3 — Create a working branch

```bash
# Replace <CLUSTER_ID> with your cluster's short name:
git checkout -b deploy/<CLUSTER_ID>
```

Example:
```bash
git checkout -b deploy/prod-east-01
```

---

### Step 1.4 — Navigate to the working directory

All file edits in this runbook are relative to this path. Run this once and keep this terminal open:

```bash
cd quickstarts/fusion-developerhub
```

Verify you are in the right place:

```bash
ls
```

Expected output should include: `deploy/`, `docs/`, `README.md`

---

**✅ Phase 1 complete when:**
- [ ] Repository is forked to your account
- [ ] Cloned locally and `cd`'d into `quickstarts/fusion-developerhub`
- [ ] `git status` shows `On branch deploy/<CLUSTER_ID>`, nothing to commit

---

## Phase 2 — Create ServiceAccount Tokens on the Fusion Cluster

> **Where to run:** The remote **Fusion cluster** (the cluster whose services you are registering).
> **Self-hosted clusters only.** If you have no `oc` access to the Fusion cluster, skip this phase and go to [Phase 3](#phase-3--edit-the-configuration-files).

A ServiceAccount (SA) is a non-human identity that gives the Developer Hub pod read-only access
to the Fusion cluster's DCS and CAS resources. You will create one SA for DCS and one for CAS.

---

### Step 2.1 — Log in to the Fusion cluster

Open a **second terminal**. Keep your first terminal (on the RHDH cluster) open.

```bash
# Replace with your Fusion cluster token and domain:
oc login --token=<YOUR_TOKEN> --server=https://api.<CLUSTER_DOMAIN>:6443
```

Example:
```bash
oc login --token=sha256~abc123xyz --server=https://api.prod-east-01.fusion.example.com:6443
```

Verify the login worked:

```bash
oc whoami
```

Expected: your username on the Fusion cluster (not the RHDH cluster).

---

### Step 2.2 — Find the installed DCS and CAS versions

```bash
# Get DCS version — replace <DCS_NAMESPACE> with your namespace (e.g. ibm-data-cataloging):
oc get spectrumdisc -n <DCS_NAMESPACE> -o jsonpath='{.items[0].status.installedVersion}{"\n"}'
```

Example:
```bash
oc get spectrumdisc -n ibm-data-cataloging -o jsonpath='{.items[0].status.installedVersion}{"\n"}'
```
Expected output: `2.5.3`

```bash
# Get CAS version — replace <CAS_NAMESPACE> with your namespace (e.g. ibm-cas):
oc get casinstall -n <CAS_NAMESPACE> -o jsonpath='{.items[0].status.installedVersion}{"\n"}'
```

Example:
```bash
oc get casinstall -n ibm-cas -o jsonpath='{.items[0].status.installedVersion}{"\n"}'
```
Expected output: `1.1.5`

Write both down as `DCS_VERSION` and `CAS_VERSION`.

---

### Step 2.3 — Create the DCS ServiceAccount

```bash
# Replace <DCS_NAMESPACE>:
oc create serviceaccount rhdh-dcs-reader -n <DCS_NAMESPACE>
```

Example:
```bash
oc create serviceaccount rhdh-dcs-reader -n ibm-data-cataloging
```

Expected output:
```
serviceaccount/rhdh-dcs-reader created
```

If you see `Error from server (AlreadyExists)`, the SA already exists. That is fine, continue to the next step.

---

### Step 2.4 — Grant the DCS ServiceAccount read access

```bash
# Replace <DCS_NAMESPACE>:
oc create clusterrolebinding rhdh-dcs-reader \
  --clusterrole=view \
  --serviceaccount=<DCS_NAMESPACE>:rhdh-dcs-reader
```

Example:
```bash
oc create clusterrolebinding rhdh-dcs-reader \
  --clusterrole=view \
  --serviceaccount=ibm-data-cataloging:rhdh-dcs-reader
```

Expected output:
```
clusterrolebinding.rbac.authorization.k8s.io/rhdh-dcs-reader created
```

If you see `AlreadyExists`, patch the namespace instead:
```bash
# Replace <DCS_NAMESPACE>:
oc patch clusterrolebinding rhdh-dcs-reader \
  --type=json \
  -p='[{"op":"replace","path":"/subjects/0/namespace","value":"<DCS_NAMESPACE>"}]'
```

---

### Step 2.5 — Create the CAS ServiceAccount

```bash
# Replace <CAS_NAMESPACE>:
oc create serviceaccount rhdh-cas-reader -n <CAS_NAMESPACE>
```

Example:
```bash
oc create serviceaccount rhdh-cas-reader -n ibm-cas
```

Expected output:
```
serviceaccount/rhdh-cas-reader created
```

---

### Step 2.6 — Grant the CAS ServiceAccount read access

```bash
# Replace <CAS_NAMESPACE>:
oc create clusterrolebinding rhdh-cas-reader \
  --clusterrole=view \
  --serviceaccount=<CAS_NAMESPACE>:rhdh-cas-reader
```

Example:
```bash
oc create clusterrolebinding rhdh-cas-reader \
  --clusterrole=view \
  --serviceaccount=ibm-cas:rhdh-cas-reader
```

Expected output:
```
clusterrolebinding.rbac.authorization.k8s.io/rhdh-cas-reader created
```

---

### Step 2.7 — Create a long-lived token for the DCS ServiceAccount

A ServiceAccount token is a JWT string that the Developer Hub pod uses to authenticate to the Fusion cluster.
You must use `oc apply -f -` (not `oc create`) because the `kubernetes.io/service-account.name` annotation
requires the object to exist before the token controller populates it.

```bash
# Replace <DCS_NAMESPACE>:
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: rhdh-dcs-reader-token
  namespace: <DCS_NAMESPACE>
  annotations:
    kubernetes.io/service-account.name: rhdh-dcs-reader
type: kubernetes.io/service-account-token
EOF
```

Example:
```bash
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: rhdh-dcs-reader-token
  namespace: ibm-data-cataloging
  annotations:
    kubernetes.io/service-account.name: rhdh-dcs-reader
type: kubernetes.io/service-account-token
EOF
```

Expected output:
```
secret/rhdh-dcs-reader-token created
```

---

### Step 2.8 — Create a long-lived token for the CAS ServiceAccount

```bash
# Replace <CAS_NAMESPACE>:
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: rhdh-cas-reader-token
  namespace: <CAS_NAMESPACE>
  annotations:
    kubernetes.io/service-account.name: rhdh-cas-reader
type: kubernetes.io/service-account-token
EOF
```

Example:
```bash
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: rhdh-cas-reader-token
  namespace: ibm-cas
  annotations:
    kubernetes.io/service-account.name: rhdh-cas-reader
type: kubernetes.io/service-account-token
EOF
```

Expected output:
```
secret/rhdh-cas-reader-token created
```

---

### Step 2.9 — Wait for the tokens to be populated, then extract them

The Kubernetes token controller takes a few seconds to sign and populate the token.
Wait 15 seconds, then run:

```bash
sleep 15
```

Now extract the DCS token into a shell variable:

```bash
# Replace <DCS_NAMESPACE>:
DCS_TOKEN=$(oc get secret rhdh-dcs-reader-token \
  -n <DCS_NAMESPACE> \
  -o jsonpath='{.data.token}' | base64 -d)

echo "DCS token length: ${#DCS_TOKEN}"
```

Example:
```bash
DCS_TOKEN=$(oc get secret rhdh-dcs-reader-token \
  -n ibm-data-cataloging \
  -o jsonpath='{.data.token}' | base64 -d)

echo "DCS token length: ${#DCS_TOKEN}"
```

Expected output: `DCS token length: 1842` (must be greater than 1000)

Now extract the CAS token:

```bash
# Replace <CAS_NAMESPACE>:
CAS_TOKEN=$(oc get secret rhdh-cas-reader-token \
  -n <CAS_NAMESPACE> \
  -o jsonpath='{.data.token}' | base64 -d)

echo "CAS token length: ${#CAS_TOKEN}"
```

Example:
```bash
CAS_TOKEN=$(oc get secret rhdh-cas-reader-token \
  -n ibm-cas \
  -o jsonpath='{.data.token}' | base64 -d)

echo "CAS token length: ${#CAS_TOKEN}"
```

Expected output: `CAS token length: 1796` (must be greater than 1000)

If either length is `0`, the token has not been populated yet. Wait 10 more seconds and re-run the extract commands.

> **Keep this terminal open.** You need `$DCS_TOKEN` and `$CAS_TOKEN` in Phase 5.

---

**✅ Phase 2 complete when:**
- [ ] `rhdh-dcs-reader` SA exists in `<DCS_NAMESPACE>`
- [ ] `rhdh-cas-reader` SA exists in `<CAS_NAMESPACE>`
- [ ] Both ClusterRoleBindings exist
- [ ] `echo ${#DCS_TOKEN}` prints a number greater than 1000
- [ ] `echo ${#CAS_TOKEN}` prints a number greater than 1000

---

## Phase 3 — Edit the Configuration Files

> **Where to run:** Your local workstation, first terminal, inside the `quickstarts/fusion-developerhub` directory.
> You need to edit two files. Do **not** skip either one.

---

### Step 3.1 — Open `application.yaml` in your editor

This file tells ArgoCD where your Git repository is and what values to use for the deployment.

```bash
# From quickstarts/fusion-developerhub:
vim deploy/gitops/environments/prod/application.yaml
```

You can use any editor: `nano`, `code`, `vim`, etc.

---

### Step 3.2 — Set the repository URL

Find the line that starts with `repoURL:` (around line 18). Replace the value with your fork URL.

Before:
```yaml
    repoURL: https://github.ibm.com/ProjectAbell/Fusion-AI
```

After (replace with your own URL):
```yaml
    repoURL: https://github.ibm.com/your-org/Fusion-AI
```

---

### Step 3.3 — Set the target branch

Find the line that starts with `targetRevision:` (around line 21). Replace the value with your branch name.

Before:
```yaml
    targetRevision: cas-dcs-rhdh
```

After:
```yaml
    targetRevision: main
```

---

### Step 3.4 — Set the wildcard domain

Find the line that starts with `wildcardDomain:` inside the `valuesObject:` section (around line 30).

Before:
```yaml
          wildcardDomain: apps.f80l034.fusion.tadn.ibm.com
```

After (use your WILDCARD_DOMAIN from Step 0.3):
```yaml
          wildcardDomain: apps.prod-east-01.fusion.example.com
```

---

### Step 3.5 — Set the storage class

Find the line that starts with `storageClassName:` inside `valuesObject.developerHub.storage` (around line 34).

Before:
```yaml
            storageClassName: "ocs-storagecluster-cephfs"
```

After (use your RWX_STORAGE_CLASS from Step 0.3, must support ReadWriteMany):
```yaml
            storageClassName: "ocs-storagecluster-cephfs"
```

> **Important:** If you need to change this, the value must be an RWX storage class. Using an RWO class
> (e.g. `ocs-storagecluster-ceph-rbd`) will leave pods stuck in `Pending` because the PVC requires
> `ReadWriteMany` access mode.

Save and close `application.yaml`.

---

### Step 3.6 — Open `prod/values.yaml` in your editor

This file configures every aspect of the deployment including which Fusion clusters appear in the catalog.

```bash
# From quickstarts/fusion-developerhub:
vim deploy/helm/environments/prod/values.yaml
```

---

### Step 3.7 — Set the wildcard domain in values.yaml

Find `wildcardDomain:` near the top of the file (around line 6). Update it to match what you set in `application.yaml`.

```yaml
global:
  wildcardDomain: apps.prod-east-01.fusion.example.com
```

---

### Step 3.8 — Set the storage class in values.yaml (three places)

Search for `storageClassName:` in the file. There are three occurrences — update all three
to your `RWX_STORAGE_CLASS`:

1. Under `developerHub.storage`:
```yaml
developerHub:
  storage:
    storageClassName: "ocs-storagecluster-cephfs"
```

2. Under `postgresql.storage`:
```yaml
postgresql:
  storage:
    storageClassName: "ocs-storagecluster-cephfs"
```

3. Under `postgresql.backup.repos[0].volume.volumeClaimSpec`:
```yaml
      volumeClaimSpec:
        storageClassName: "ocs-storagecluster-cephfs"
```

---

### Step 3.9 — Confirm the token secrets are active

Search the file for `extraEnvs`. Find the `secrets:` list and confirm **neither line is commented out**:

```yaml
developerHub:
  extraEnvs:
    secrets:
      - name: fusion-cluster-tokens
      - name: github-auth-secret
```

If either line starts with `#`, remove the `#` character to uncomment it.

---

### Step 3.10 — Add your Fusion cluster to the clusters list

Find the `clusters:` list under `developerHub.fusionServices`. It may be empty (`clusters: []`)
or have existing entries. Append your cluster block inside this list.

**Generic form:**
```yaml
developerHub:
  fusionServices:
    enabled: true
    clusters:
      - name: <CLUSTER_ID>
        ocpApiUrl: https://api.<CLUSTER_DOMAIN>:6443
        clusterType: self-hosted
        services:
          dcs:
            enabled: true
            version: "<DCS_VERSION>"
            namespace: <DCS_NAMESPACE>
            k8s:
              tokenEnvVar: FUSION_<CLUSTER_ID_UPPER>_SA_TOKEN
              labelSelector: "app=isd,component=discover"
          cas:
            enabled: true
            version: "<CAS_VERSION>"
            namespace: <CAS_NAMESPACE>
            k8s:
              tokenEnvVar: FUSION_<CLUSTER_ID_UPPER>_CAS_SA_TOKEN
              labelSelector: "app.kubernetes.io/name=cas.isf.ibm.com"
```

**Concrete example** (fill in your actual values — do not copy these verbatim):
```yaml
developerHub:
  fusionServices:
    enabled: true
    clusters:
      - name: prod-east-01
        ocpApiUrl: https://api.prod-east-01.fusion.example.com:6443
        clusterType: self-hosted
        services:
          dcs:
            enabled: true
            version: "2.5.3"
            namespace: ibm-data-cataloging
            k8s:
              tokenEnvVar: FUSION_PROD_EAST_01_SA_TOKEN
              labelSelector: "app=isd,component=discover"
          cas:
            enabled: true
            version: "1.1.5"
            namespace: ibm-cas
            k8s:
              tokenEnvVar: FUSION_PROD_EAST_01_CAS_SA_TOKEN
              labelSelector: "app.kubernetes.io/name=cas.isf.ibm.com"
```

> **How to compute `CLUSTER_ID_UPPER`:**
> Uppercase the `CLUSTER_ID` and replace every `-` with `_`.
> Examples: `prod-east-01` → `PROD_EAST_01` | `mycluster` → `MYCLUSTER` | `my-site-2` → `MY_SITE_2`

> **The `tokenEnvVar` value must exactly match the key name in the Kubernetes secret you create in Phase 5.**
> A mismatch means the pod starts but the token is never injected.

Save and close `values.yaml`.

---

**✅ Phase 3 complete when:**
- [ ] `application.yaml` has your `repoURL`, `targetRevision`, `wildcardDomain`, `storageClassName`
- [ ] `prod/values.yaml` has your `wildcardDomain` (matching `application.yaml`)
- [ ] `prod/values.yaml` has all three `storageClassName` values updated
- [ ] `fusion-cluster-tokens` and `github-auth-secret` are both **uncommented** under `extraEnvs.secrets`
- [ ] Your cluster entry is added to the `clusters:` list with correct `tokenEnvVar` key names

---

## Phase 4 — Push Your Changes to Git

> **Where to run:** Your local workstation, first terminal.
> ArgoCD reads from Git — until you push, it sees nothing.

### Step 4.1 — Check what you changed

```bash
# From the repo root (cd ../ twice from quickstarts/fusion-developerhub):
cd ../..
git diff --stat
```

Expected output: two files changed:
```
quickstarts/fusion-developerhub/deploy/gitops/environments/prod/application.yaml
quickstarts/fusion-developerhub/deploy/helm/environments/prod/values.yaml
```

---

### Step 4.2 — Stage the two files

```bash
git add \
  quickstarts/fusion-developerhub/deploy/gitops/environments/prod/application.yaml \
  quickstarts/fusion-developerhub/deploy/helm/environments/prod/values.yaml
```

---

### Step 4.3 — Commit with a descriptive message

```bash
# Replace placeholders with your actual values:
git commit -m "feat(prod): add Fusion cluster <CLUSTER_ID> — DCS <DCS_VERSION>, CAS <CAS_VERSION>"
```

Example:
```bash
git commit -m "feat(prod): add Fusion cluster prod-east-01 — DCS 2.5.3, CAS 1.1.5"
```

Expected output:
```
[main a1b2c3d] feat(prod): add Fusion cluster prod-east-01 — DCS 2.5.3, CAS 1.1.5
 2 files changed, 18 insertions(+), 3 deletions(-)
```

---

### Step 4.4 — Push to your branch

```bash
# Replace <GIT_BRANCH> with your branch name:
git push origin <GIT_BRANCH>
```

Example:
```bash
git push origin main
```

Expected output:
```
To https://github.ibm.com/your-org/Fusion-AI.git
   abc1234..def5678  main -> main
```

---

**✅ Phase 4 complete when:**
- [ ] `git push` exited with no error
- [ ] Open the URL in your browser and confirm both files show your changes

---

## Phase 5 — Create Kubernetes Secrets on the RHDH Cluster

> **Where to run:** The **RHDH cluster** — switch back to your first terminal.
> These secrets must exist **before** ArgoCD deploys the Backstage pod.
> The pod reads them at startup. If they are missing, the pod enters `CrashLoopBackOff`.

---

### Step 5.1 — Switch back to the RHDH cluster

If you logged in to the Fusion cluster in Phase 2 (second terminal), go back to your first terminal or log in again:

```bash
oc login --server=https://api.<RHDH_CLUSTER_DOMAIN>:6443
oc whoami
```

Confirm you are on the RHDH cluster (not the Fusion cluster).

---

### Step 5.2 — Create the namespace

```bash
oc create namespace fusion-developer-hub
```

If you see `Error from server (AlreadyExists)`, the namespace already exists. That is fine, continue.

---

### Step 5.3 — Create the ServiceAccount token secret

This secret holds the DCS and CAS tokens you extracted in Phase 2.
The key names **must exactly match** the `tokenEnvVar` values you wrote in Step 3.10.

```bash
# Replace all four placeholders:
oc create secret generic fusion-cluster-tokens \
  --from-literal=FUSION_<CLUSTER_ID_UPPER>_SA_TOKEN="<DCS_TOKEN>" \
  --from-literal=FUSION_<CLUSTER_ID_UPPER>_CAS_SA_TOKEN="<CAS_TOKEN>" \
  -n fusion-developer-hub
```

In the example, `$DCS_TOKEN` and `$CAS_TOKEN` are still set from Phase 2.
If you are in the same terminal session:

```bash
oc create secret generic fusion-cluster-tokens \
  --from-literal=FUSION_PROD_EAST_01_SA_TOKEN="$DCS_TOKEN" \
  --from-literal=FUSION_PROD_EAST_01_CAS_SA_TOKEN="$CAS_TOKEN" \
  -n fusion-developer-hub
```

Expected output:
```
secret/fusion-cluster-tokens created
```

> **Never paste raw token values into a command visible in your shell history if working on a shared machine.**
> Use environment variables (`$DCS_TOKEN`, `$CAS_TOKEN`) as shown above.

---

### Step 5.4 — Verify the token secret was created correctly

```bash
oc get secret fusion-cluster-tokens -n fusion-developer-hub \
  -o jsonpath='{.data}' | python3 -c "
import sys, json, base64
d = json.load(sys.stdin)
for k, v in sorted(d.items()):
    tok = base64.b64decode(v).decode()
    print(f'{k}: length={len(tok)}, starts_with={tok[:20]}...')
"
```

Expected output (lengths will differ, but must be > 1000):
```
FUSION_PROD_EAST_01_CAS_SA_TOKEN: length=1796, starts_with=eyJhbGciOiJSUzI1...
FUSION_PROD_EAST_01_SA_TOKEN:     length=1842, starts_with=eyJhbGciOiJSUzI1...
```

Both tokens must:
- Have `length > 1000`
- Start with `eyJhbGci` (this is the base64 encoding of a JWT header)

If a token shows `length=0`, go back to Phase 2 and re-extract the token.

---

### Step 5.5 — Create the GitHub authentication secret

The Developer Hub pod needs a GitHub Personal Access Token to read catalog YAML files from
your private repository.

```bash
# Replace <GITHUB_PAT> with your actual token (starts with ghp_ or github_pat_):
oc create secret generic github-auth-secret \
  --from-literal=GITHUB_TOKEN=<GITHUB_PAT> \
  -n fusion-developer-hub
```

Example:
```bash
oc create secret generic github-auth-secret \
  --from-literal=GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx \
  -n fusion-developer-hub
```

Expected output:
```
secret/github-auth-secret created
```

Verify it exists:
```bash
oc get secret github-auth-secret -n fusion-developer-hub
```

Expected output:
```
NAME                 TYPE     DATA   AGE
github-auth-secret   Opaque   1      3s
```

---

**✅ Phase 5 complete when:**
- [ ] `fusion-developer-hub` namespace exists
- [ ] `fusion-cluster-tokens` secret exists; both token keys show `length > 1000`
- [ ] `github-auth-secret` exists with `DATA=1`

---

## Phase 6 — Pre-create the Plugins Storage Volume

> **Where to run:** The RHDH cluster.
> You must do this **before** applying the ArgoCD Application in Phase 7.

**Why this step exists:** ArgoCD deploys in waves. Wave 65 creates the `dynamic-plugins-root`
storage volume (PVC). Wave 70 deploys the Backstage pod. However, the RHDH operator reacts
to the Backstage resource almost instantly and schedules pods before the Wave 65 volume has
been provisioned by the storage system. The pods enter `Pending` with the error:
`persistentvolumeclaim "dynamic-plugins-root" not found`.

Pre-creating the volume now — before ArgoCD runs at all — eliminates this race condition.

---

### Step 6.1 — Create the storage volume

```bash
# Replace <RWX_STORAGE_CLASS> with your storage class:
cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dynamic-plugins-root
  namespace: fusion-developer-hub
  annotations:
    argocd.argoproj.io/sync-wave: "65"
spec:
  storageClassName: <RWX_STORAGE_CLASS>
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 5Gi
EOF
```

Example:
```bash
cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dynamic-plugins-root
  namespace: fusion-developer-hub
  annotations:
    argocd.argoproj.io/sync-wave: "65"
spec:
  storageClassName: ocs-storagecluster-cephfs
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 5Gi
EOF
```

Expected output:
```
persistentvolumeclaim/dynamic-plugins-root created
```

---

### Step 6.2 — Wait for the volume to reach `Bound` status

```bash
oc get pvc dynamic-plugins-root -n fusion-developer-hub -w
```

Watch the output. Press `Ctrl+C` when STATUS changes to `Bound`:

```
NAME                   STATUS    VOLUME       CAPACITY   ACCESS MODES
dynamic-plugins-root   Pending
dynamic-plugins-root   Bound     pvc-a1b2c3   5Gi        RWX
```

This usually takes 10–30 seconds.

If it stays `Pending` for more than 60 seconds:
```bash
oc describe pvc dynamic-plugins-root -n fusion-developer-hub
```
Look at the **Events** section at the bottom. Common causes:
- `no PersistentVolumes available for this claim` — the storage class provisioner is not running
- `Multi-Attach error` — you used an RWO storage class instead of RWX

---

**✅ Phase 6 complete when:**
- [ ] `oc get pvc dynamic-plugins-root -n fusion-developer-hub` shows `STATUS=Bound`
- [ ] `ACCESS MODES` includes `RWX`

---

## Phase 7 — Apply the ArgoCD Application

> **Where to run:** The RHDH cluster, from the `quickstarts/fusion-developerhub` directory.
> This single command tells ArgoCD to start deploying everything.

---

### Step 7.1 — Apply the Application manifest

```bash
# From quickstarts/fusion-developerhub:
oc apply -f deploy/gitops/environments/prod/application.yaml
```

Expected output (first time):
```
application.argoproj.io/fusion-developer-hub created
```

Expected output (if you run this again later):
```
application.argoproj.io/fusion-developer-hub configured
```

---

### Step 7.2 — Confirm ArgoCD registered the Application

```bash
oc get application fusion-developer-hub -n openshift-gitops
```

Expected output immediately after apply:
```
NAME                   SYNC STATUS   HEALTH STATUS
fusion-developer-hub   OutOfSync     Missing
```

`OutOfSync / Missing` is **normal** — ArgoCD has not started deploying yet. It will begin within 30 seconds.

---

### Step 7.3 — If ArgoCD does not start syncing within 60 seconds

Run these two commands in order:

**Step A — Force ArgoCD to re-read from Git:**
```bash
oc annotate application.argoproj.io fusion-developer-hub \
  -n openshift-gitops \
  --overwrite \
  "argocd.argoproj.io/refresh=hard"
```

**Wait 30 seconds**, then:

**Step B — Trigger a manual sync:**
```bash
# Replace <GIT_BRANCH> with your branch:
oc patch application.argoproj.io fusion-developer-hub \
  -n openshift-gitops --type=merge \
  -p '{"operation":{"initiatedBy":{"username":"manual"},"sync":{"revision":"<GIT_BRANCH>"}}}'
```

Example:
```bash
oc patch application.argoproj.io fusion-developer-hub \
  -n openshift-gitops --type=merge \
  -p '{"operation":{"initiatedBy":{"username":"manual"},"sync":{"revision":"main"}}}'
```

---

**✅ Phase 7 complete when:**
- [ ] `oc get application fusion-developer-hub -n openshift-gitops` returns a row
- [ ] `SYNC STATUS` is `OutOfSync`, `Syncing`, or `Synced`

---

## Phase 8 — Watch the Deployment Progress

> **Where to run:** The RHDH cluster.
> Total expected time: **10–20 minutes** for a fresh installation.

---

### Step 8.1 — Open a dedicated monitoring terminal

Open a new terminal window and run:

```bash
watch -n 5 "oc get application.argoproj.io fusion-developer-hub \
  -n openshift-gitops \
  -o jsonpath='SYNC={.status.sync.status}  HEALTH={.status.health.status}  PHASE={.status.operationState.phase}\nMSG={.status.operationState.message}'"
```

Leave this running. It updates every 5 seconds.

---

### Step 8.2 — Understand the sync waves

ArgoCD deploys in numbered waves. Each wave waits for the previous one to be healthy before starting.

| Wave | What is deployed | Typical time |
|---|---|---|
| −10 | RBAC: ClusterRoles, ServiceAccounts, ArgoCD permissions | < 10 s |
| 0 | Namespaces for operators | < 5 s |
| 10 | Pre-install jobs (operator check, namespace labeler) | 30–60 s |
| 20 | OperatorGroups | < 5 s |
| 30 | Operator Subscriptions (Crunchy PostgreSQL + RHDH) | 1–3 min |
| 40 | CRD readiness check jobs | 1–3 min |
| 50 | ConfigMaps, Secrets, NetworkPolicy | < 30 s |
| 60 | PostgreSQL cluster (3 instances + backup) | 3–5 min |
| 65 | `dynamic-plugins-root` PVC (already `Bound` — skipped) | < 5 s |
| 70 | Backstage CR → RHDH pods start | 2–4 min |

---

### Step 8.3 — Watch pods in a second terminal

Open another terminal and run:

```bash
watch -n 5 "oc get pods -n fusion-developer-hub"
```

**What to expect as pods appear (in order):**

First, job pods from waves 10 and 40:
```
rhdh-operator-check-xxxxx    0/1   Completed   0   5m
wait-for-crds-xxxxx          0/1   Completed   0   4m
```

Then, PostgreSQL pods from wave 60:
```
developerhub-postgres-instance1-xxxx-0   4/4   Running   0   3m
developerhub-postgres-instance1-yyyy-0   4/4   Running   0   3m
developerhub-postgres-instance1-zzzz-0   4/4   Running   0   3m
developerhub-postgres-repo-host-0        2/2   Running   0   3m
```

Finally, Backstage pods from wave 70:
```
backstage-developer-hub-xxxxxxxxx-aaaaa   5/5   Running   0   2m
backstage-developer-hub-xxxxxxxxx-bbbbb   5/5   Running   0   2m
backstage-developer-hub-xxxxxxxxx-ccccc   5/5   Running   0   2m
```

> **Normal behavior during PostgreSQL startup:** You may see `bootstrap from leader ... in progress` in the
> PostgreSQL pod logs. This is expected and takes 2–5 minutes. Do not restart the pods.

---

### Step 8.4 — Final status check

When all waves complete, run:

```bash
oc get application.argoproj.io fusion-developer-hub \
  -n openshift-gitops \
  -o jsonpath='SYNC={.status.sync.status}  HEALTH={.status.health.status}{"\n"}'
```

Expected output:
```
SYNC=Synced  HEALTH=Healthy
```

---

**✅ Phase 8 complete when:**
- [ ] `SYNC=Synced  HEALTH=Healthy`
- [ ] 3 × `backstage-developer-hub-*` pods show `5/5 Running`
- [ ] 3 × `developerhub-postgres-instance1-*` pods show `4/4 Running`
- [ ] All job pods show `0/1 Completed`

---

## Phase 9 — Verify the Deployment

> **Where to run:** The RHDH cluster.

---

### Step 9.1 — Get the Developer Hub URL

```bash
oc get route backstage-developer-hub -n fusion-developer-hub \
  -o jsonpath='https://{.spec.host}{"\n"}'
```

Example output:
```
https://backstage-developer-hub-fusion-developer-hub.apps.prod-east-01.fusion.example.com
```

Open this URL in your web browser. You should see the IBM Fusion Developer Hub login page.
Click **Enter** to log in as a guest.

---

### Step 9.2 — Verify the GitHub token is loaded in the pod

The `GITHUB_TOKEN` environment variable must be present inside the running pod.
Without it, catalog imports from your private repository will fail with `406 Not Acceptable`.

```bash
POD=$(oc get pods -n fusion-developer-hub \
  | grep "backstage-developer-hub.*Running" | head -1 | awk '{print $1}')

oc exec -n fusion-developer-hub "$POD" -- env | grep -c GITHUB_TOKEN
```

Expected output: `1`

If the result is `0`:
1. Confirm `github-auth-secret` is listed and **not commented out** in `prod/values.yaml` under `developerHub.extraEnvs.secrets`
2. Then restart the deployment:
```bash
oc rollout restart deployment/backstage-developer-hub -n fusion-developer-hub
oc rollout status deployment/backstage-developer-hub -n fusion-developer-hub --timeout=180s
```

---

### Step 9.3 — Verify the homepage loads

In the browser at the RHDH URL, confirm:
- IBM Fusion AI branding is visible
- The **Quick Access** section appears (Blueprints & Quickstarts, Documentation, Models, Community)
- Left navigation shows: **Catalog**, **Create**, **Docs**
- Click **Catalog** — components should appear
- Click **Create** — AI application templates should appear

---

**✅ Phase 9 complete when:**
- [ ] RHDH URL opens in browser
- [ ] Homepage loads with IBM Fusion branding
- [ ] `GITHUB_TOKEN` count = 1 in pod
- [ ] Catalog and Create pages load

---

## Phase 10 — Verify Catalog Entities in the UI

> **Where to run:** RHDH cluster and browser.
> Each registered Fusion cluster produces exactly 5 catalog entities.

---

### Step 10.1 — Check the ConfigMap contains your cluster's file

ArgoCD creates a ConfigMap called `fusion-ai-clusters` during Wave 50. It contains one YAML
file per registered cluster.

```bash
oc get configmap fusion-ai-clusters -n fusion-developer-hub \
  -o jsonpath='{.data}' | python3 -c "
import sys, json
d = json.load(sys.stdin)
for k in sorted(d): print(k)
"
```

Expected output (one line per cluster):
```
fusion-prod-east-01-catalog-info.yaml
```

If your cluster key is missing, ArgoCD has not yet synced Wave 50. Force a sync:
```bash
oc annotate application.argoproj.io fusion-developer-hub \
  -n openshift-gitops --overwrite "argocd.argoproj.io/refresh=hard"
```

---

### Step 10.2 — Confirm the catalog file is mounted in the pod

The ConfigMap is volume-mounted into each Backstage pod. The mount takes up to 60 seconds after the ConfigMap is updated.

```bash
POD=$(oc get pods -n fusion-developer-hub --no-headers \
  | grep "backstage-developer-hub.*Running" | awk 'NR==1{print $1}')

oc exec -n fusion-developer-hub "$POD" -- \
  ls /opt/app-root/src/fusion-clusters/
```

Expected output:
```
fusion-prod-east-01-catalog-info.yaml
```

If the file is not there yet, wait 60 seconds and try again — Kubernetes propagates ConfigMap changes to pods asynchronously.

---

### Step 10.3 — Check the catalog config points to the file, not the directory

```bash
oc exec -n fusion-developer-hub "$POD" -- \
  grep -A3 "fusion-clusters" /opt/app-root/src/app-config-fusion-services.yaml
```

Expected output — `target:` must end with the file name, not stop at the directory:
```yaml
- type: file
  target: /opt/app-root/src/fusion-clusters/fusion-prod-east-01-catalog-info.yaml
  rules:
    - allow: [Component, System, API, Resource]
```

If `target:` points to `/opt/app-root/src/fusion-clusters` without a file name at the end,
see [Troubleshooting — EISDIR](#eisdir-illegal-operation-on-a-directory).

---

### Step 10.4 — Check for errors in the pod logs

```bash
oc logs -n fusion-developer-hub "$POD" \
  -c backstage-backend --since=10m \
  | grep -i "EISDIR\|fusion-prod-east-01\|error"
```

No `EISDIR` lines should appear. If you see them, see [Troubleshooting](#eisdir-illegal-operation-on-a-directory).

---

### Step 10.5 — Verify entities in the Catalog UI

Open RHDH in your browser → click **Catalog** in the left navigation.
Use the search box or kind filter to find each of the following 5 entities:

| Kind | Name pattern | Example name |
|---|---|---|
| System | `fusion-<CLUSTER_ID>` | `fusion-prod-east-01` |
| Component | `fusion-dcs-<CLUSTER_ID>` | `fusion-dcs-prod-east-01` |
| API | `fusion-dcs-mcp-api-<CLUSTER_ID>` | `fusion-dcs-mcp-api-prod-east-01` |
| Component | `fusion-cas-<CLUSTER_ID>` | `fusion-cas-prod-east-01` |
| API | `fusion-cas-mcp-api-<CLUSTER_ID>` | `fusion-cas-mcp-api-prod-east-01` |

All 5 entities appear within 60–120 seconds after ArgoCD syncs.

---

**✅ Phase 10 complete when:**
- [ ] `fusion-<CLUSTER_ID>-catalog-info.yaml` key exists in the `fusion-ai-clusters` ConfigMap
- [ ] The file is visible in the pod at `/opt/app-root/src/fusion-clusters/`
- [ ] `target:` in the pod config ends with the file name (not the directory)
- [ ] No `EISDIR` errors in logs
- [ ] All 5 catalog entities are visible in the RHDH Catalog UI

---

**🎉 Initial deployment is complete.**
IBM Fusion Developer Hub is running and serving catalog entities for `<CLUSTER_ID>`.

---

## Day-2: Add Another Cluster (Self-Hosted)

> Use this section when RHDH is already deployed and you want to add an additional Fusion cluster
> that you have `oc` access to. The existing cluster entries remain untouched.
>
> **Reference:** adding a second cluster `prod-west-02`.

---

### Step A.1 — Create tokens on the new Fusion cluster

Log in to the new Fusion cluster and repeat Phase 2 (Steps 2.1–2.9) for the new cluster.
Use the new cluster's `DCS_NAMESPACE` and `CAS_NAMESPACE`.

At the end of this step you will have `$DCS_TOKEN` and `$CAS_TOKEN` for the new cluster.

---

### Step A.2 — Patch the existing token secret on the RHDH cluster

The `fusion-cluster-tokens` secret already exists. Add the new cluster's keys **without** removing
the existing ones:

```bash
# Replace <NEW_CLUSTER_ID_UPPER>, and use the tokens from the new cluster:
oc patch secret fusion-cluster-tokens \
  -n fusion-developer-hub \
  --type=merge \
  -p "{
    \"stringData\": {
      \"FUSION_<NEW_CLUSTER_ID_UPPER>_SA_TOKEN\": \"$DCS_TOKEN\",
      \"FUSION_<NEW_CLUSTER_ID_UPPER>_CAS_SA_TOKEN\": \"$CAS_TOKEN\"
    }
  }"
```

Example (adding `prod-west-02`, so `CLUSTER_ID_UPPER=PROD_WEST_02`):
```bash
oc patch secret fusion-cluster-tokens \
  -n fusion-developer-hub \
  --type=merge \
  -p "{
    \"stringData\": {
      \"FUSION_PROD_WEST_02_SA_TOKEN\": \"$DCS_TOKEN\",
      \"FUSION_PROD_WEST_02_CAS_SA_TOKEN\": \"$CAS_TOKEN\"
    }
  }"
```

Verify all keys are present:
```bash
oc get secret fusion-cluster-tokens -n fusion-developer-hub \
  -o jsonpath='{.data}' | python3 -c "
import sys, json, base64
d = json.load(sys.stdin)
for k, v in sorted(d.items()):
    tok = base64.b64decode(v).decode()
    print(f'{k}: length={len(tok)}')
"
```

Every key must show `length > 1000`.

---

### Step A.3 — Append the new cluster to `prod/values.yaml`

Open `deploy/helm/environments/prod/values.yaml` and **append** the new cluster block
inside the `clusters:` list. Do not modify or remove existing entries.

```yaml
# Append after the existing entry:
      - name: prod-west-02
        ocpApiUrl: https://api.prod-west-02.fusion.example.com:6443
        clusterType: self-hosted
        services:
          dcs:
            enabled: true
            version: "2.5.3"
            namespace: ibm-data-cataloging
            k8s:
              tokenEnvVar: FUSION_PROD_WEST_02_SA_TOKEN
              labelSelector: "app=isd,component=discover"
          cas:
            enabled: true
            version: "1.1.5"
            namespace: ibm-cas
            k8s:
              tokenEnvVar: FUSION_PROD_WEST_02_CAS_SA_TOKEN
              labelSelector: "app.kubernetes.io/name=cas.isf.ibm.com"
```

---

### Step A.4 — Commit, push, and verify

```bash
# From the repo root:
git add quickstarts/fusion-developerhub/deploy/helm/environments/prod/values.yaml
git commit -m "feat(prod-west-02): add self-hosted cluster — DCS 2.5.3, CAS 1.1.5"
git push origin main
```

ArgoCD auto-syncs Wave 50 (the ConfigMap wave) in ~30 seconds. No pod restart is needed.

Verify:
```bash
oc get application.argoproj.io fusion-developer-hub \
  -n openshift-gitops \
  -o jsonpath='SYNC={.status.sync.status}  HEALTH={.status.health.status}{"\n"}'
```

Then follow Phase 10 steps to confirm the 5 new entities appear in the Catalog.

---

## Day-2: Add Another Cluster (Proxy-Only)

> Use this section when you have no `oc` access to the remote Fusion cluster.
> No token is needed. No secret changes are needed.

---

### Step B.1 — Find the CAS version (without direct cluster access)

```bash
# Replace <CLUSTER_DOMAIN>:
curl -sk https://console-ibm-spectrum-fusion-ns.apps.<CLUSTER_DOMAIN>/cas/api/v1/health \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print('CAS version:', d.get('version','not found'))"
```

For DCS version, ask the cluster administrator or check the IBM Fusion operator console.

---

### Step B.2 — Append the proxy-only cluster to `prod/values.yaml`

Open `deploy/helm/environments/prod/values.yaml` and append inside `clusters:`.
A proxy-only cluster has **no** `k8s:` block.

```yaml
      - name: <CLUSTER_ID>
        ocpApiUrl: https://api.<CLUSTER_DOMAIN>:6443
        clusterType: proxy-only
        services:
          dcs:
            enabled: true
            version: "<DCS_VERSION>"
            namespace: <DCS_NAMESPACE>
          cas:
            enabled: true
            version: "<CAS_VERSION>"
            namespace: <CAS_NAMESPACE>
```

Example:
```yaml
      - name: remote-site-03
        ocpApiUrl: https://api.remote-site-03.fusion.example.com:6443
        clusterType: proxy-only
        services:
          dcs:
            enabled: true
            version: "2.5.3"
            namespace: ibm-data-cataloging
          cas:
            enabled: true
            version: "1.1.5"
            namespace: ibm-cas
```

---

### Step B.3 — Commit, push, and verify

```bash
git add quickstarts/fusion-developerhub/deploy/helm/environments/prod/values.yaml
git commit -m "feat(remote-site-03): add proxy-only cluster — DCS 2.5.3, CAS 1.1.5"
git push origin main
```

ArgoCD syncs Wave 50 in ~30 seconds. No secret update and no pod restart needed.
Confirm using Phase 10 steps.

---

## Day-2: Update CAS or DCS Version

> Use this when a service was upgraded on a Fusion cluster and you want the Developer Hub
> catalog to show the new version number.

---

### Step C.1 — Find the new installed version

Log in to the Fusion cluster and run:

```bash
# For DCS:
oc get spectrumdisc -n <DCS_NAMESPACE> \
  -o jsonpath='{.items[0].status.installedVersion}{"\n"}'

# For CAS:
oc get casinstall -n <CAS_NAMESPACE> \
  -o jsonpath='{.items[0].status.installedVersion}{"\n"}'
```

Write down the new version numbers.

---

### Step C.2 — Update the version in `prod/values.yaml`

Open `deploy/helm/environments/prod/values.yaml`.
Find the cluster block by its `name:` field.
Change **only** the `version:` fields. Do not touch any other values.

```yaml
      - name: prod-east-01        # ← find this line
        clusterType: self-hosted
        services:
          dcs:
            version: "2.6.0"      # ← update this
          cas:
            version: "1.2.0"      # ← update this
```

---

### Step C.3 — Commit, push, and verify

```bash
git add quickstarts/fusion-developerhub/deploy/helm/environments/prod/values.yaml
git commit -m "chore(prod-east-01): bump DCS 2.5.3→2.6.0, CAS 1.1.5→1.2.0"
git push origin main
```

After ArgoCD syncs (~30 seconds):
```bash
oc get configmap fusion-ai-clusters -n fusion-developer-hub \
  -o jsonpath='{.data}' | python3 -m json.tool | grep 'service-version'
```

Expected: `"fusion.ibm.com/service-version": "2.6.0"` (for the DCS entity).

In the browser: Catalog → `fusion-dcs-prod-east-01` → **About** tab → Annotations →
`fusion.ibm.com/service-version` should show the new value.

---

## Day-2: Roll Back a Change

### Scenario 1 — Roll back a version bump

Edit `prod/values.yaml`, revert the `version:` fields to the old values, commit and push.
ArgoCD auto-syncs in ~30 seconds.

```bash
git add quickstarts/fusion-developerhub/deploy/helm/environments/prod/values.yaml
git commit -m "revert(prod-east-01): rollback DCS to 2.5.3, CAS to 1.1.5"
git push origin main
```

---

### Scenario 2 — Roll back using a saved snapshot

Snapshot files are stored in `deploy/helm/environments/prod/` with names like `value-v0-may2026.yaml`.

```bash
# List available snapshots:
ls quickstarts/fusion-developerhub/deploy/helm/environments/prod/value-*.yaml

# Restore a snapshot (replace <SNAPSHOT> with the filename):
cp quickstarts/fusion-developerhub/deploy/helm/environments/prod/<SNAPSHOT>.yaml \
   quickstarts/fusion-developerhub/deploy/helm/environments/prod/values.yaml

git add quickstarts/fusion-developerhub/deploy/helm/environments/prod/values.yaml
git commit -m "rollback: restore <SNAPSHOT> configuration"
git push origin main
```

---

### Scenario 3 — Roll back using Helm revision history

Use this only if you deployed without ArgoCD (manual Helm install):

```bash
helm history fusion-developer-hub -n fusion-developer-hub
helm rollback fusion-developer-hub <REVISION_NUMBER> -n fusion-developer-hub
```

---

## Troubleshooting

### EISDIR: illegal operation on a directory

**Symptom in pod logs:**
```
file /opt/app-root/src/fusion-clusters could not be read,
Error: EISDIR: illegal operation on a directory, read
```

**What it means:** The catalog location `type: file` is pointing at the `fusion-clusters/` directory
instead of the specific per-cluster YAML file inside it.

**Diagnose:**
```bash
POD=$(oc get pods -n fusion-developer-hub --no-headers \
  | grep "backstage-developer-hub.*Running" | awk 'NR==1{print $1}')

oc exec -n fusion-developer-hub "$POD" -- \
  grep -A3 "fusion-clusters" /opt/app-root/src/app-config-fusion-services.yaml
```

- **Correct** (ends with a file name): `target: /opt/app-root/src/fusion-clusters/fusion-prod-east-01-catalog-info.yaml`
- **Incorrect** (ends at directory): `target: /opt/app-root/src/fusion-clusters`

**Fix:** In the Helm template `deploy/helm/templates/fusion-ai-services-configmap.yaml`,
the catalog location block must loop over clusters and produce one entry per cluster:

```yaml
{{- range .Values.developerHub.fusionServices.clusters }}
- type: file
  target: /opt/app-root/src/fusion-clusters/fusion-{{ .name }}-catalog-info.yaml
  rules:
    - allow: [Component, System, API, Resource]
{{- end }}
```

After fixing the template, commit, push, and restart the pod:
```bash
oc rollout restart deployment/backstage-developer-hub -n fusion-developer-hub
oc rollout status deployment/backstage-developer-hub -n fusion-developer-hub --timeout=300s
```

---

### `dynamic-plugins-root` PVC stuck in Pending

**Diagnose:**
```bash
oc describe pvc dynamic-plugins-root -n fusion-developer-hub
```

Read the **Events** section at the bottom.

**Cause A — Wrong storage class (RWO instead of RWX):**

The event will say: `multi node access modes are only supported on rbd block type volumes`.

Fix:
```bash
# Delete the wrong PVC:
oc delete pvc dynamic-plugins-root -n fusion-developer-hub

# Re-create with the correct RWX class:
cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dynamic-plugins-root
  namespace: fusion-developer-hub
  annotations:
    argocd.argoproj.io/sync-wave: "65"
spec:
  storageClassName: ocs-storagecluster-cephfs
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 5Gi
EOF

oc get pvc dynamic-plugins-root -n fusion-developer-hub -w
```

**Cause B — Phase 6 was skipped:** Apply Phase 6 now and wait for `Bound`.

---

### ArgoCD shows `revision <branch> must be resolved`

**What it means:** ArgoCD cached a branch reference that is now invalid or the repository was
re-pointed to a new fork.

**Fix:**

Step 1 — Force ArgoCD to re-read from Git:
```bash
oc annotate application.argoproj.io fusion-developer-hub \
  -n openshift-gitops \
  --overwrite \
  "argocd.argoproj.io/refresh=hard"
```

Step 2 — Wait 30 seconds, then trigger a sync:
```bash
# Replace <GIT_BRANCH> with your branch:
oc patch application.argoproj.io fusion-developer-hub \
  -n openshift-gitops --type=merge \
  -p '{"operation":{"initiatedBy":{"username":"manual"},"sync":{"revision":"<GIT_BRANCH>"}}}'
```

---

### ArgoCD stuck on `sync=Unknown`

**What it means:** ArgoCD cannot render the Helm chart. It cannot compute what to deploy.

**Common causes:**
- YAML syntax error in `prod/values.yaml`
- ArgoCD cannot reach the Git repository (missing credentials)
- The `targetRevision` branch does not exist in the remote repository

**Diagnose:**
```bash
# Check conditions:
oc get application.argoproj.io fusion-developer-hub \
  -n openshift-gitops \
  -o yaml | grep -A5 conditions

# Check ArgoCD repo server logs:
oc logs -n openshift-gitops \
  -l app.kubernetes.io/name=argocd-repo-server --tail=40
```

**Validate your YAML file locally:**
```bash
python3 -c "import yaml; yaml.safe_load(open('quickstarts/fusion-developerhub/deploy/helm/environments/prod/values.yaml'))"
```

No output means the YAML is valid. An error message tells you the line number with the problem.

---

### 406 Not Acceptable when importing a catalog URL

**What it means:** `GITHUB_TOKEN` is not loaded in the pod.

**Diagnose:**
```bash
# Check the secret exists:
oc get secret github-auth-secret -n fusion-developer-hub

# Check it is referenced in the deployment config:
grep -A5 "extraEnvs" quickstarts/fusion-developerhub/deploy/helm/environments/prod/values.yaml \
  | grep github-auth-secret
```

Expected: `- name: github-auth-secret` (no leading `#`).

**Fix:** If the line was commented out, uncomment it, commit, push, and restart:
```bash
oc rollout restart deployment/backstage-developer-hub -n fusion-developer-hub
oc rollout status deployment/backstage-developer-hub -n fusion-developer-hub --timeout=300s
```

---

### Operator install plan waiting for manual approval

**Symptom:** Wave 30 (Subscriptions) never progresses. The operators stay in `Installing` state.

**Diagnose:**
```bash
oc get installplan -n rhdh-operator
oc get installplan -n postgres-operator
```

**Fix:** Approve each pending install plan:
```bash
# Replace <INSTALLPLAN_NAME> with the name from the command above (e.g. ip-abc12):
oc patch installplan <INSTALLPLAN_NAME> -n rhdh-operator \
  --type=merge -p '{"spec":{"approved":true}}'

oc patch installplan <INSTALLPLAN_NAME> -n postgres-operator \
  --type=merge -p '{"spec":{"approved":true}}'
```

---

### Catalog entities not appearing after 5 minutes

Force catalog re-ingestion. This is a rolling restart — zero downtime if you have 3 replicas:

```bash
oc rollout restart deployment/backstage-developer-hub -n fusion-developer-hub
oc rollout status deployment/backstage-developer-hub -n fusion-developer-hub --timeout=300s
```

Catalog re-ingestion runs on pod startup. After the rollout completes, wait 2 minutes and check the UI.

---

### GitHub raw URL gives 404 on catalog import

**What it means:** The `rawBaseUrl` in the ConfigMap points to the wrong SCM host.

**Diagnose:**
```bash
oc get cm app-config-fusion-services -n fusion-developer-hub \
  -o jsonpath='{.data.app-config-fusion-services\.yaml}' | grep rawBaseUrl
```

| Your SCM host | Correct `rawBaseUrl` value |
|---|---|
| `github.ibm.com` (IBM GitHub Enterprise) | `https://raw.github.ibm.com` |
| `github.com` (GitHub.com) | `https://raw.githubusercontent.com` |

If the value is wrong, update it in `prod/values.yaml`, commit, push, and ArgoCD will resync.

---

## Quick Reference

### Essential commands

```bash
# Check all pods:
oc get pods -n fusion-developer-hub

# Get the RHDH URL:
oc get route backstage-developer-hub -n fusion-developer-hub \
  -o jsonpath='https://{.spec.host}{"\n"}'

# Check ArgoCD status:
oc get application fusion-developer-hub -n openshift-gitops

# Restart Developer Hub (zero-downtime with 3 replicas):
oc rollout restart deployment/backstage-developer-hub -n fusion-developer-hub
oc rollout status deployment/backstage-developer-hub -n fusion-developer-hub --timeout=300s

# List cluster keys in the catalog ConfigMap:
oc get configmap fusion-ai-clusters -n fusion-developer-hub \
  -o jsonpath='{.data}' | python3 -c "
import sys, json
d = json.load(sys.stdin)
for k in sorted(d): print(k)
"

# Check token lengths in the secret:
oc get secret fusion-cluster-tokens -n fusion-developer-hub \
  -o jsonpath='{.data}' | python3 -c "
import sys, json, base64
d = json.load(sys.stdin)
for k, v in sorted(d.items()):
    tok = base64.b64decode(v).decode()
    print(f'{k}: length={len(tok)}')
"

# Tail Backstage backend logs:
POD=$(oc get pods -n fusion-developer-hub --no-headers \
  | grep "backstage-developer-hub.*Running" | awk 'NR==1{print $1}')
oc logs -n fusion-developer-hub "$POD" -c backstage-backend --tail=50

# Force ArgoCD to re-read from Git:
oc annotate application.argoproj.io fusion-developer-hub \
  -n openshift-gitops --overwrite "argocd.argoproj.io/refresh=hard"
```

---

### CLUSTER_ID_UPPER derivation examples

| `CLUSTER_ID` | `CLUSTER_ID_UPPER` | `DCS_TOKEN_KEY` |
|---|---|---|
| `mycluster` | `MYCLUSTER` | `FUSION_MYCLUSTER_SA_TOKEN` |
| `prod-east-01` | `PROD_EAST_01` | `FUSION_PROD_EAST_01_SA_TOKEN` |
| `site-a-2` | `SITE_A_2` | `FUSION_SITE_A_2_SA_TOKEN` |

---

### Entities created per cluster

Each registered cluster produces exactly 5 catalog entities:

| Kind | Name |
|---|---|
| System | `fusion-<CLUSTER_ID>` |
| Component | `fusion-dcs-<CLUSTER_ID>` |
| API | `fusion-dcs-mcp-api-<CLUSTER_ID>` |
| Component | `fusion-cas-<CLUSTER_ID>` |
| API | `fusion-cas-mcp-api-<CLUSTER_ID>` |

---

### Service URLs per cluster

All URLs are derived from `ocpApiUrl` — you never enter them manually.

| Service | URL pattern |
|---|---|
| DCS Console | `https://console-ibm-data-cataloging.apps.<CLUSTER_DOMAIN>` |
| DCS MCP (HTTP) | `https://dcs-mcp-route-ibm-data-cataloging.apps.<CLUSTER_DOMAIN>/mcp/http` |
| DCS MCP (SSE) | `https://dcs-mcp-route-ibm-data-cataloging.apps.<CLUSTER_DOMAIN>/mcp` |
| CAS Console | `https://console-ibm-spectrum-fusion-ns.apps.<CLUSTER_DOMAIN>/cas/overview` |
| CAS MCP | `https://console-ibm-spectrum-fusion-ns.apps.<CLUSTER_DOMAIN>/cas/api/v1/mcp` |
| CAS Swagger | `https://console-ibm-spectrum-fusion-ns.apps.<CLUSTER_DOMAIN>/cas/api/v1/docs` |
| CAS Health | `https://console-ibm-spectrum-fusion-ns.apps.<CLUSTER_DOMAIN>/cas/api/v1/health` |

---

### Phase summary (first-time deployment)

```
Phase 0    Check tools, cluster access, storage class, ArgoCD
Phase 1    Fork repository, clone, create branch
Phase 2    Create SA tokens on Fusion cluster          (self-hosted only)
Phase 3    Edit application.yaml + prod/values.yaml
Phase 4    Commit and push both files to Git
Phase 5    Create fusion-cluster-tokens + github-auth-secret on RHDH cluster
Phase 6    Pre-create dynamic-plugins-root PVC, wait for Bound
Phase 7    Apply ArgoCD application.yaml
Phase 8    Watch sync waves complete (10–20 min)
Phase 9    Verify pods, URL, GITHUB_TOKEN
Phase 10   Verify 5 catalog entities in RHDH UI
```
