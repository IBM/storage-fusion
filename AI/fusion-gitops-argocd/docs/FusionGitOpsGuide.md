# Fusion GitOpsGuide
# GitOps in Action: A Hands-On Guide to Argo CD Using a Dynamic Web Application

Deploy, auto-sync, detect drift, and manually synchronize Kubernetes applications using Argo CD on OpenShift.

As Kubernetes adoption grows, so does the complexity of managing applications running on it. Multiple environments, frequent changes, and manual deployments often lead to configuration drift, inconsistent releases, and difficult-to-trace failures. This is exactly the problem that GitOps was created to solve.

GitOps is a deployment and operations model where Git becomes the single source of truth for both application code and infrastructure configuration. Instead of directly applying changes to a cluster, teams make changes in Git. The cluster then continuously reconciles itself to match what is defined in the repository.

## In a GitOps workflow:
- Git represents the desired state
- Kubernetes represents the actual state
- Any difference between the two is treated as a problem that must be corrected

This approach brings strong benefits such as version control, easy rollbacks, clear audit trails, and safer deployments.

This is where Argo CD fits in.

Argo CD is a Kubernetes native GitOps continuous delivery tool that continuously monitors Git repositories and ensures that the cluster state always matches what is declared in Git. Instead of _pushing_ changes to Kubernetes, Argo CD _pulls_ changes from Git and either applies them automatically or on demand.

## By combining GitOps principles with Argo CD:
- You deploy applications declaratively
- You eliminate manual kubectl apply workflows
- You detect and prevent configuration drift
- You gain full visibility into application health and sync status
- You can roll back to any Git commit with confidence

In this blog, we'll move beyond theory and learn GitOps the practical way using Argo CD. We'll deploy a dynamic web application, update it purely through Git commits, observe how Argo CD auto-syncs changes, and finally see how drift is detected when auto-sync is disabled.

By the end of this walkthrough, you will clearly understand how GitOps works in real life, not just on slides.

## What You Will Learn in This Blog

- What GitOps is and how it differs from traditional Kubernetes deployments
- How Argo CD implements GitOps using pull-based reconciliation
- How to deploy an application using Argo CD on OpenShift
- How auto-sync works using a real ConfigMap change
- How Argo CD detects drift when auto-sync is disabled
- How to safely manually review and synchronize changes

## Installing Argo CD on OpenShift

On OpenShift, install Argo CD using the Red Hat OpenShift GitOps Operator.

  1. Go to OperatorHub and search for openshift-gitops
  <p align="center"><img width="1722" alt="Screenshot 2025-12-06 at 9 36 16 PM" src="https://github.ibm.com/user-attachments/assets/5167bf29-e784-4510-a4b2-3e176d0eb480" /></p>

  2. Select Red Hat OpenShift GitOps and choose the required version
  <p align="center"><img width="1721" alt="Screenshot 2025-12-06 at 9 36 38 PM" src="https://github.ibm.com/user-attachments/assets/4cf6f708-1705-4552-8489-2314f130d932" /></p>

  3. Click Install
  <img width="1721" alt="Screenshot 2025-12-06 at 9 37 42 PM" src="https://github.ibm.com/user-attachments/assets/019c7c10-ddfd-4964-a867-522c4309ad0f" /></p>
  
  <p align="center"><img width="565" alt="Screenshot 2025-12-06 at 9 41 33 PM" src="https://github.ibm.com/user-attachments/assets/4b02eb78-14eb-4460-8fb5-d6c677199fbe" /></p>


Installing Argo CD through the OpenShift GitOps Operator ensures that the cluster automatically manages Argo CD’s lifecycle. As a result, upgrades, RBAC integration, and component health are consistently managed using Kubernetes-native patterns.

## Accessing the Argo CD Console

After installation, access the Argo CD UI from:

Red Hat Applications → OpenShift GitOps → Cluster Argo CD

<p align="center"><img width="308" alt="image" src="https://github.ibm.com/user-attachments/assets/8076101f-8dd2-49db-b2f2-35d2832ddea9" /></p>


ArgoCD console:

<p align="center"><img width="1049" alt="image" src="https://github.ibm.com/user-attachments/assets/f6bb488e-d842-4408-9a26-8a428b6bd5b9" /></p>


## Argo CD Authentication Methods

There are two ways authenticate via log in.

**OpenShift Authentication**

Users in the cluster-admins group can log in using OpenShift credentials.

**Local Admin User**

Login to the cluster:

```bash
oc login --token=<TOKEN> --server=<API_SERVER>
```

Grant the required permissions:

```bash
oc adm policy add-cluster-role-to-user cluster-admin \
  -z openshift-gitops-argocd-application-controller \
  -n openshift-gitops
```

Retrieve the Argo CD admin password:

```bash
argoPass=$(oc get secret/openshift-gitops-cluster \
  -n openshift-gitops \
  -o jsonpath='{.data.admin\.password}' | base64 -d)

echo $argoPass
```

While OpenShift authentication is recommended for production environments, the local admin user is practical for learning, demos, and troubleshooting scenarios.

## Example Application Used in This Blog

To explore Argo CD in a practical way, we’ll work with the following GitHub repository:
https://github.com/the-dev-collection/gitops-dynamic-webapp-sidecar

This is a dynamic web application designed to demonstrate GitOps behaviour:

- The web page content is stored in a ConfigMap
- The application reads content dynamically without pod restarts
- Any change to the ConfigMap in Git is reflected in the UI

This example is simple by design, allowing the focus to remain on GitOps behaviour rather than application complexity. Because the application reads content directly from a ConfigMap, it clearly demonstrates how Git-driven configuration changes can be applied without requiring rebuilding images or restarting pods.

**Directory structure of the example:**

```
├── k8s
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── route.yaml
│   ├── configmap.yaml
├── argocd
│   ├── application.yaml
├── README.md
```

- k8s/ → Application Kubernetes manifests
- configmap.yaml → Controls web content & version
- argocd/application.yaml → Argo CD Application CR


## Applying the Application Using Argo CD

**Creating the Argo CD Application**

Edit argocd/application.yaml

Replace repoURL with your forked repository URL:

```
repoURL: https://github.com/the-dev-collection/gitops-dynamic-webapp-sidecar
```

Keep the cluster destination as: server: https://kubernetes.default.svc

This tells Argo CD to deploy to the local cluster.

Apply the application.yaml:

```bash
oc apply -f argocd/application.yaml
```

At this stage, Argo CD starts continuously watching the Git repository and compares the declared manifests with the live cluster state.

The Argo CD UI now shows the dynamic-web application with status Synced and Healthy

<p align="center"><img width="1728" alt="image" src="https://github.ibm.com/user-attachments/assets/1f681d38-6fd6-451d-9cf1-b49b70f16803" /></p>

You can also see the dynamic-web Application CR under the argoproj Application CRD.

<p align="center"><img width="1724" alt="Screenshot 2025-12-07 at 1 15 08 AM" src="https://github.ibm.com/user-attachments/assets/ab5c7fb3-a029-4bed-8795-6749c4ad7ae2" /></p>


**Viewing the Application**

  1. Navigate to Networking → Routes and switch to the dynamic-web namespace
  2. Click the Location URL

The browser displays: "Welcome to GitOps Dynamic App — Version 1"

<p align="center"><img width="1718" alt="Screenshot 2025-12-07 at 1 21 09 AM" src="https://github.ibm.com/user-attachments/assets/54a39fb4-7921-42cd-8a01-280235b34ac9" /></p>


This welcome message confirms the following status:

- The application was successfully deployed by Argo CD and is actively running in the cluster.
- The web page is dynamically reading its content from the web-content ConfigMap rather than being hardcoded inside the container image.
- The Kubernetes resources defined in the Git repository were correctly applied to the cluster.
- Argo CD reconciled the desired state from Git with the live state of the cluster and found them to be in sync.
- The application is now fully managed through GitOps; as a result, any future updates made in Git will be reflected in the application according to the configured sync policy.


<p align="center"><img width="1728" alt="image" src="https://github.ibm.com/user-attachments/assets/3082afdb-0452-4fb7-a052-e758b7750eb2" /></p>


At this stage, Git has successfully become the deployment interface for the application. The commit that created the initial application is visible in Argo CD under LAST SYNC.


## Updating ConfigMap with Auto Sync Enabled

Now we'll update the application only via Git.

**Update the ConfigMap**

Edit k8s/configmap.yaml

Change "Welcome to GitOps Dynamic App — Version 1" to "Welcome to GitOps Dynamic App — Version 2"

Commit and push the change with a commit message "update version to version 2 in configmap.yaml"

**What Happens Next?**

Because auto-sync is enabled, Argo CD continuously monitors the configured Git repository for changes.

- Argo CD detects the new Git commit as soon as the updated configmap.yaml is pushed to the repository.
- It compares the _desired_ state defined in Git with the _current live_ state of the cluster and identified that the web-content ConfigMap has changed.
- Argo CD automatically applies the updated ConfigMap to the cluster without any manual intervention.
- The live cluster state is updated immediately, and the application reflects the new content even though no pods are restarted.
- Once the changes are applied, Argo CD marks the application as Synced and Healthy, indicating that the cluster state is back in alignment with Git.

The Argo CD UI shows a successful sync. The application tree shows the updated ConfigMap:

<p align="center"><img width="1712" alt="image" src="https://github.ibm.com/user-attachments/assets/86034456-c89b-4a57-bd81-418e3ff1dd48" /></p>

Refresh the Route URL and you will see:
Welcome to GitOps Dynamic App — Version 2

<p align="center"><img width="950" alt="Screenshot 2025-12-07 at 1 34 16 AM" src="https://github.ibm.com/user-attachments/assets/70dd4d35-682f-4884-9362-0fbcafd73a36" /></p>


No manual intervention. No pod restarts. Pure GitOps.

**GitOps in Action:**
The cluster changed because Git changed, not because a person ran a command against Kubernetes.

## Disable Auto Sync and Apply Changes

**Disable Auto Sync**

Disabling auto-sync is common in production environments when teams want to review changes before applying them, especially for sensitive or high-risk updates.

Edit the Application CR and disable the auto sync by removing syncPolicy.automated

```yaml
syncPolicy:
  automated: {}
```

<p align="center"><img width="614" alt="Screenshot 2025-12-07 at 1 38 24 AM" src="https://github.ibm.com/user-attachments/assets/6f9e2aca-6ab4-42a1-b21e-2330ebd337fe" /></p>


**Update ConfigMap Again**

Edit k8s/configmap.yaml:

Change the heading to " Welcome to GitOps Dynamic App — Version 3" and add ` "<p>Disabled auto sync in Argo application</p>" `

Commit and push with the commit message "disable autosync in argo application"

**Argo CD Detects Drift**

Because auto-sync is disabled, the following actions occur:

- Argo CD detects the Git change but does not automatically apply it.
- The application status changes to OutOfSync, showing that Git and the cluster are no longer aligned.
- The mismatch is caused by the updated web-content ConfigMap, which has not yet been synchronized.

<p align="center"><img width="1406" alt="image" src="https://github.ibm.com/user-attachments/assets/9802dd95-3ee3-4a8c-8aac-cd27755860d1" /></p>


**Viewing Differences Using DIFF**

Click DIFF in the Argo CD UI:

<p align="center"><img width="1344" alt="Screenshot 2025-12-07 at 1 47 55 AM" src="https://github.ibm.com/user-attachments/assets/95fb4c3d-ef83-4cda-8677-2232ab98eab5" /></p>


The diff screen shows a side-by-side comparison between the _live_ and _desired_ states.

This makes it very easy to:

- Review changes
- Validate changes before applying them
- Avoid accidental deployments

In real-world environments, this diff view is often used as a final validation step before syncing changes to production.

**Manually Syncing the Application**

Click SYNC and select:

- PRUNE (removes resources no longer defined in Git)
- AUTO-CREATE NAMESPACE (creates the namespace if it doesn't exist)
- All resources under SYNCHRONIZE RESOURCES

Click SYNCHRONIZE.

<p align="center"><img width="1408" alt="image" src="https://github.ibm.com/user-attachments/assets/f66dfda0-3d47-42d3-8bc8-95fa882a5a1e" />
</p>


After sync, the following actions occur:

- The SYNC STATUS changes to Synced, confirming that the cluster state now matches Git.
- The Git commit message is visible in the Argo CD UI, showing exactly what change was applied.
- The application and UI update immediately, reflecting the latest ConfigMap changes.

<p align="center"><img width="1556" alt="image" src="https://github.ibm.com/user-attachments/assets/945d4e3c-36f2-4699-b468-e6cd2c820f3c" /></p>


Browser now shows:
Welcome to GitOps Dynamic App — Version 3
Disabled auto sync in Argo application

<p align="center"><img width="990" alt="Screenshot 2025-12-07 at 2 08 09 AM" src="https://github.ibm.com/user-attachments/assets/cfa3a8e1-32bc-471f-a968-36e3fcfdbe4d" /></p>


## Final Thoughts

- GitOps shifts operational control from clusters to Git
- Argo CD continuously enforces this model
- Auto-sync enables fast, safe delivery
- Manual sync provides control and safety
- Drift detection prevents silent configuration changes
