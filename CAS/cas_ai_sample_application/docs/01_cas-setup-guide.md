# CAS Cluster Setup & Vector Store Onboarding Guide
#  Authors: Vitaliy Kornev & Priyas Ojha
**Purpose:** Configure IBM Fusion Content Aware Storage (CAS) to ingest documents and expose a queryable vector store.

By the end of this guide you will have a connected data source, a running vector store with completed ingestion, and a verified search API endpoint ready to use with this application.

---

## Step 1 — Gather Cluster Information

You will need two things before starting:

- **Console URL** — the base URL for your OpenShift cluster
- **API token** — used to authenticate with CAS and as your frontend login credential

To get your token: log into the OpenShift console, open the user menu (top-right corner), and click **Copy login command → Display Token**.

Contact your cluster administrator if you do not have access. If the cluster is behind a VPN, connect before continuing.

---

## Step 2 — Open the IBM Fusion Console

In the OpenShift console, click the applications icon (the grid/rubik's cube icon in the top navigation bar), then select **IBM Fusion** from the list.

---

## Step 3 — Set Up Your Data Source

Prepare your storage (S3-compatible object storage, IBM Storage Scale, or another supported backend) and have your connection credentials ready.

For full instructions on creating a domain and connecting a data source, see the [CAS documentation](https://www.ibm.com/docs/en/fusion-hci-systems/2.12.x?topic=cas-creating-domain-connecting-data-source).

---

## Steps 4–6 — Configure CAS, Create the Vector Store, and Verify Ingestion

Follow the [CAS documentation](https://www.ibm.com/docs/en/fusion-hci-systems/2.12.x?topic=cas-configuring-content-aware-storage) to:

1. Connect your data source in the Fusion CAS console.
2. Create a vector store and configure ingestion options.
3. Confirm ingestion has completed before continuing.

---

## Step 7 — Verify with Swagger

1. In the Fusion console, go to **Content-Aware-Storage → Vector Stores**, select your vector store, and click **Actions → View Search APIs** to open the Swagger UI. This also gives you the CAS endpoint URL needed for this application.
2. In Swagger, run **GET /vector_stores** to confirm your vector store is listed and accessible.
3. Run **POST /search**, replace `"query": "string"` with a question about your ingested documents, and confirm results are returned.

For more detail on the search API, see the [CAS documentation](https://www.ibm.com/docs/en/fusion-hci-systems/2.12.x?topic=cas-configuring-content-aware-storage).

---

You now have everything you need from CAS:
- ✓ A populated vector store
- ✓ A verified search API endpoint URL (from the Swagger UI above)
- ✓ An API token (from Step 1)

Return to **[Getting Started → Step 2](GETTING_STARTED.md#step-2--get-an-llm-running)** to set up your LLM, run the application, and log in.
