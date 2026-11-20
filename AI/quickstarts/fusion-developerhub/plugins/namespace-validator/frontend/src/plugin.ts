import { scaffolderPlugin } from '@backstage/plugin-scaffolder';
import { createScaffolderFieldExtension } from '@backstage/plugin-scaffolder-react';
import { discoveryApiRef, identityApiRef } from '@backstage/core-plugin-api';
import { NamespaceNameField } from './NamespaceNameField';
import { OcGroupField } from './OcGroupField';
import { NaaSProjectField } from './NaaSProjectField';
import { NaaSDeleteField } from './NaaSDeleteField';
import { ArgoAppField } from './ArgoAppField';

export const NamespaceNameFieldExtension = scaffolderPlugin.provide(
  createScaffolderFieldExtension({
    name: 'NamespaceName',
    component: NamespaceNameField,
    validation: async (value: string, validation, context) => {
      if (!value) return;

      const formData = context.formData as Record<string, any>;
      const env = formData.environment;

      if (!env) {
        // Emit a silent sentinel — the inline field already shows "Select an
        // environment before continuing." via its own localMessage state.
        validation.addError(' ');
        return;
      }

      const discoveryApi = context.apiHolder.get(discoveryApiRef);
      const identityApi = context.apiHolder.get(identityApiRef);

      if (!discoveryApi || !identityApi) return;

      try {
        const namespace = `${value}-${env}`;
        const [baseUrl, credentials] = await Promise.all([
          discoveryApi.getBaseUrl('scaffolder'),
          identityApi.getCredentials(),
        ]);

        const response = await fetch(
          `${baseUrl}/namespaces/${encodeURIComponent(namespace)}`,
          {
            credentials: 'same-origin',
            headers: credentials.token
              ? { Authorization: `Bearer ${credentials.token}` }
              : undefined,
          },
        );

        if (response.ok) {
          const { exists } = await response.json();
          if (exists) {
            // Sentinel only — the inline field already shows the namespace-exists
            // message via its localMessage state. Descriptive strings here would
            // produce a redundant "Project Name <message>" entry in ErrorListTemplate.
            validation.addError(' ');
          }
        }
      } catch {
        // Same pattern: sentinel blocks Next; the field shows its own error message.
        validation.addError(' ');
      }
    },
  })
);

export const OcGroupFieldExtension = scaffolderPlugin.provide(
  createScaffolderFieldExtension({
    name: 'OcGroupField',
    component: OcGroupField,
  })
);

export const NaaSProjectFieldExtension = scaffolderPlugin.provide(
  createScaffolderFieldExtension({
    name: 'NaaSProjectField',
    component: NaaSProjectField,
  })
);

export const ArgoAppFieldExtension = scaffolderPlugin.provide(
  createScaffolderFieldExtension({
    name: 'ArgoAppField',
    component: ArgoAppField,
    // Validation is handled by JSON Schema constraints (minLength / pattern /
    // errorMessage) on the argoAppDetails sub-properties in the template YAML.
    // rjsf/AJV blocks Next natively and the ArgoAppField component surfaces
    // inline per-field errors using rawErrors.length > 0 as a "submitted" flag.
    // No custom validator is registered here so the framework's ErrorListTemplate
    // never renders a spurious "Argo App Details" entry.
  })
);

export const NaaSDeleteFieldExtension = scaffolderPlugin.provide(
  createScaffolderFieldExtension({
    name: 'NaaSDeleteField',
    component: NaaSDeleteField,
    validation: (value: any, validation) => {
      // Emit a silent sentinel to block Next — NaaSDeleteField surfaces all
      // per-field error messages inline so descriptive strings here would only
      // produce a redundant "NaaS Delete Selection <message>" banner in
      // ErrorListTemplate.
      const expected = value?.projectName && value?.environment
        ? `${value.projectName}-${value.environment}`
        : '';
      const invalid =
        !value?.projectName ||
        !value?.environment ||
        !value?.confirmDelete ||
        value.confirmDelete !== expected;
      if (invalid) validation.addError(' ');
    },
  })
);
