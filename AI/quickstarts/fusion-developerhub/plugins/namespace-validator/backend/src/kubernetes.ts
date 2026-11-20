import { readFile } from 'node:fs/promises';
import { Agent, request } from 'node:https';

const KUBERNETES_API_URL = 'https://kubernetes.default.svc';
const SERVICE_ACCOUNT_TOKEN_PATH =
  '/var/run/secrets/kubernetes.io/serviceaccount/token';
const SERVICE_ACCOUNT_CA_PATH =
  '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt';
// OpenShift injects the full cluster CA bundle (including intermediate/root
// certificates) here. Reading both files and passing them together ensures
// the full chain is trusted even when the API server uses a self-signed or
// internally-chained certificate.
const OPENSHIFT_SERVICE_CA_PATH =
  '/var/run/secrets/kubernetes.io/serviceaccount/service-ca.crt';

const NAMESPACE_NAME_PATTERN = /^[a-z0-9]([-a-z0-9]*[a-z0-9])?$/;

export function namespaceName(projectName: string, environment: string): string {
  const name = `${projectName}-${environment}`;

  if (!NAMESPACE_NAME_PATTERN.test(name) || name.length > 63) {
    throw new Error('Namespace name must be a valid DNS label of at most 63 characters.');
  }

  return name;
}

export async function namespaceExists(name: string): Promise<boolean> {
  const [token, ca, serviceCa] = await Promise.all([
    readFile(SERVICE_ACCOUNT_TOKEN_PATH, 'utf8'),
    readFile(SERVICE_ACCOUNT_CA_PATH),
    readFile(OPENSHIFT_SERVICE_CA_PATH).catch(() => null),
  ]);

  // Build the CA bundle: always include the service account CA; append the
  // OpenShift service CA if it exists (not present on all cluster versions).
  const caBundle = serviceCa ? [ca, serviceCa] : ca;

  return new Promise((resolve, reject) => {
    const client = request(
      `${KUBERNETES_API_URL}/api/v1/namespaces/${encodeURIComponent(name)}`,
      {
        agent: new Agent({ ca: caBundle }),
        headers: { Authorization: `Bearer ${token.trim()}` },
        method: 'GET',
        timeout: 5_000,
      },
      response => {
        response.resume();

        if (response.statusCode === 200) {
          resolve(true);
          return;
        }

        if (response.statusCode === 404) {
          resolve(false);
          return;
        }

        reject(new Error(`Kubernetes API returned ${response.statusCode ?? 'an unknown status'}.`));
      },
    );

    client.on('error', reject);
    client.on('timeout', () => client.destroy(new Error('Kubernetes API request timed out.')));
    client.end();
  });
}

// ── NaaS namespace types & helpers ───────────────────────────────────────────

export interface NaaSNamespaceMetadata {
  projectName: string;
  environment: string;
  businessUnit: string;
  size: string;
  ownerGroup: string;
  developerGroup: string;
  viewerGroup: string;
  // ArgoCD Application details — present only when an app was wired up via NaaS.
  argoAppName: string;
  argoRepoUrl: string;
  argoTargetRevision: string;
  argoPath: string;
  argoSourceType: string;
}

function namespaceToMetadata(
  labels: Record<string, string>,
  annotations: Record<string, string>,
): NaaSNamespaceMetadata {
  return {
    projectName: labels['project'] ?? '',
    environment: labels['environment'] ?? '',
    businessUnit: labels['business-unit'] ?? '',
    size: labels['naas.fusion.ibm.com/size'] ?? '',
    ownerGroup: labels['naas.fusion.ibm.com/owner-group'] ?? '',
    developerGroup: labels['naas.fusion.ibm.com/developer-group'] ?? '',
    viewerGroup: labels['naas.fusion.ibm.com/viewer-group'] ?? '',
    argoAppName: annotations['naas.fusion.ibm.com/argo-app-name'] ?? '',
    argoRepoUrl: annotations['naas.fusion.ibm.com/argo-repo-url'] ?? '',
    argoTargetRevision: annotations['naas.fusion.ibm.com/argo-target-revision'] ?? '',
    argoPath: annotations['naas.fusion.ibm.com/argo-path'] ?? '',
    argoSourceType: annotations['naas.fusion.ibm.com/argo-source-type'] ?? '',
  };
}

async function k8sCredentials(): Promise<{
  token: string;
  caBundle: Buffer | Buffer[];
}> {
  const [token, ca, serviceCa] = await Promise.all([
    readFile(SERVICE_ACCOUNT_TOKEN_PATH, 'utf8'),
    readFile(SERVICE_ACCOUNT_CA_PATH),
    readFile(OPENSHIFT_SERVICE_CA_PATH).catch(() => null),
  ]);
  return { token, caBundle: serviceCa ? [ca, serviceCa] : ca };
}

/**
 * Returns all namespaces bearing the label
 * `naas.fusion.ibm.com/provisioned-by=namespace-as-a-service`, with their
 * NaaS metadata recovered from the namespace labels.
 */
export async function listNaaSNamespaces(): Promise<NaaSNamespaceMetadata[]> {
  const { token, caBundle } = await k8sCredentials();
  const labelSelector = encodeURIComponent(
    'naas.fusion.ibm.com/provisioned-by=namespace-as-a-service',
  );

  return new Promise((resolve, reject) => {
    const client = request(
      `${KUBERNETES_API_URL}/api/v1/namespaces?labelSelector=${labelSelector}`,
      {
        agent: new Agent({ ca: caBundle }),
        headers: { Authorization: `Bearer ${token.trim()}` },
        method: 'GET',
        timeout: 5_000,
      },
      response => {
        const chunks: Buffer[] = [];
        response.on('data', (chunk: Buffer) => chunks.push(chunk));
        response.on('end', () => {
          if (response.statusCode !== 200) {
            reject(
              new Error(
                `Kubernetes API returned ${response.statusCode ?? 'an unknown status'}.`,
              ),
            );
            return;
          }
          try {
            const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
            const namespaces: NaaSNamespaceMetadata[] = (body.items ?? [])
              .map((item: { metadata: { labels: Record<string, string>; annotations?: Record<string, string> } }) =>
                namespaceToMetadata(item.metadata.labels ?? {}, item.metadata.annotations ?? {}),
              )
              .filter(
                (ns: NaaSNamespaceMetadata) => ns.projectName && ns.environment,
              );
            resolve(namespaces);
          } catch {
            reject(
              new Error(
                'Failed to parse namespaces response from Kubernetes API.',
              ),
            );
          }
        });
      },
    );

    client.on('error', reject);
    client.on('timeout', () =>
      client.destroy(new Error('Kubernetes API request timed out.')),
    );
    client.end();
  });
}

/**
 * Fetches NaaS metadata for a single namespace by its full name
 * (`{projectName}-{environment}`). Returns null when the namespace does not
 * exist or was not provisioned by NaaS.
 */
export async function getNaaSNamespace(
  name: string,
): Promise<NaaSNamespaceMetadata | null> {
  const { token, caBundle } = await k8sCredentials();

  return new Promise((resolve, reject) => {
    const client = request(
      `${KUBERNETES_API_URL}/api/v1/namespaces/${encodeURIComponent(name)}`,
      {
        agent: new Agent({ ca: caBundle }),
        headers: { Authorization: `Bearer ${token.trim()}` },
        method: 'GET',
        timeout: 5_000,
      },
      response => {
        const chunks: Buffer[] = [];
        response.on('data', (chunk: Buffer) => chunks.push(chunk));
        response.on('end', () => {
          if (response.statusCode === 404) {
            resolve(null);
            return;
          }
          if (response.statusCode !== 200) {
            reject(
              new Error(
                `Kubernetes API returned ${response.statusCode ?? 'an unknown status'}.`,
              ),
            );
            return;
          }
          try {
            const item = JSON.parse(Buffer.concat(chunks).toString('utf8'));
            const labels: Record<string, string> =
              item.metadata?.labels ?? {};

            if (
              labels['naas.fusion.ibm.com/provisioned-by'] !==
              'namespace-as-a-service'
            ) {
              resolve(null);
              return;
            }

            const annotations: Record<string, string> =
              item.metadata?.annotations ?? {};
            resolve(namespaceToMetadata(labels, annotations));
          } catch {
            reject(
              new Error(
                'Failed to parse namespace response from Kubernetes API.',
              ),
            );
          }
        });
      },
    );

    client.on('error', reject);
    client.on('timeout', () =>
      client.destroy(new Error('Kubernetes API request timed out.')),
    );
    client.end();
  });
}

export async function listGroups(): Promise<string[]> {
  const [token, ca, serviceCa] = await Promise.all([
    readFile(SERVICE_ACCOUNT_TOKEN_PATH, 'utf8'),
    readFile(SERVICE_ACCOUNT_CA_PATH),
    readFile(OPENSHIFT_SERVICE_CA_PATH).catch(() => null),
  ]);

  const caBundle = serviceCa ? [ca, serviceCa] : ca;

  return new Promise((resolve, reject) => {
    const client = request(
      `${KUBERNETES_API_URL}/apis/user.openshift.io/v1/groups`,
      {
        agent: new Agent({ ca: caBundle }),
        headers: { Authorization: `Bearer ${token.trim()}` },
        method: 'GET',
        timeout: 5_000,
      },
      response => {
        const chunks: Buffer[] = [];
        response.on('data', (chunk: Buffer) => chunks.push(chunk));
        response.on('end', () => {
          if (response.statusCode !== 200) {
            reject(new Error(`Kubernetes API returned ${response.statusCode ?? 'an unknown status'}.`));
            return;
          }
          try {
            const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
            const names: string[] = (body.items ?? []).map((item: { metadata: { name: string } }) => item.metadata.name);
            resolve(names.sort());
          } catch (e) {
            reject(new Error('Failed to parse groups response from Kubernetes API.'));
          }
        });
      },
    );

    client.on('error', reject);
    client.on('timeout', () => client.destroy(new Error('Kubernetes API request timed out.')));
    client.end();
  });
}
