import React, { useEffect, useRef, useState } from 'react';
import { discoveryApiRef, identityApiRef, useApi } from '@backstage/core-plugin-api';
import type { FieldProps } from '@rjsf/utils';
import MenuItem from '@material-ui/core/MenuItem';
import TextField from '@material-ui/core/TextField';
import Typography from '@material-ui/core/Typography';

const REQUEST_TIMEOUT_MS = 10_000;

/**
 * The value this field emits — a flat object holding the five ArgoCD
 * application sub-fields. The native `createArgoApp` boolean lives as a
 * sibling field on the same step (using ui:widget: radio, identical to the
 * Request template) and is read from formContext to trigger the fetch.
 *
 * Template usage:
 *   ui:field: ArgoAppField   (on the argoAppDetails property)
 *
 * Reference values downstream:
 *   ${{ parameters.argoAppDetails.applicationName }}
 *   ${{ parameters.argoAppDetails.applicationRepoURL }}
 *   ${{ parameters.argoAppDetails.applicationTargetRevision }}
 *   ${{ parameters.argoAppDetails.applicationPath }}
 *   ${{ parameters.argoAppDetails.applicationSourceType }}
 */
export interface ArgoAppDetailsValue {
  applicationName: string;
  applicationRepoURL: string;
  applicationTargetRevision: string;
  applicationPath: string;
  applicationSourceType: string;
}

const EMPTY: ArgoAppDetailsValue = {
  applicationName: '',
  applicationRepoURL: '',
  applicationTargetRevision: '',
  applicationPath: '',
  applicationSourceType: '',
};

const SOURCE_TYPES = [
  { value: 'Directory', label: 'Directory (raw manifests / Kustomize)' },
  { value: 'Helm',      label: 'Helm chart' },
];

/**
 * Compound scaffolder field for the five ArgoCD application sub-fields in the
 * NaaS Update template.
 *
 * This field does NOT render the Yes/No toggle — that remains a native
 * `createArgoApp` boolean field with `ui:widget: radio` on the same step,
 * identical to the Request template. The native allOf/if/then in the template
 * schema controls visibility and required-ness of this field, so behaviour is
 * consistent with the Request template.
 *
 * When `createArgoApp` becomes true (read from formContext), this field calls
 * GET /naas/namespaces/{projectName}-{environment} and pre-fills the five
 * sub-fields from any stored naas.fusion.ibm.com/argo-* annotations. The user
 * can review and edit the pre-filled values before submitting.
 */
export function ArgoAppField(props: FieldProps<ArgoAppDetailsValue>) {
  const {
    formData = EMPTY,
    formContext,
    idSchema,
    onChange,
    rawErrors = [],
    required,
  } = props;

  const discoveryApi = useApi(discoveryApiRef);
  const identityApi = useApi(identityApiRef);

  const [fetching, setFetching] = useState(false);
  const [fetchError, setFetchError] = useState<string | undefined>();

  // Track the namespace we last fetched so we don't re-fetch on every render.
  const fetchedFor = useRef<string>('');

  // Read toggle and namespace identity from sibling/previous-step form data.
  const allFormData = (formContext?.formData as any) ?? {};
  const createArgoApp: boolean = !!allFormData.createArgoApp;
  const naasSelection = allFormData.naasSelection ?? {};
  const namespaceName =
    naasSelection.projectName && naasSelection.environment
      ? `${naasSelection.projectName}-${naasSelection.environment}`
      : '';

  // ── Fetch existing annotations when the toggle is switched to Yes ──────────
  useEffect(() => {
    if (!createArgoApp) return;
    if (!namespaceName) return;
    if (fetchedFor.current === namespaceName) return;

    let cancelled = false;
    const controller = new AbortController();
    const timeout = window.setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

    setFetching(true);
    setFetchError(undefined);

    (async () => {
      try {
        const [baseUrl, credentials] = await Promise.all([
          discoveryApi.getBaseUrl('scaffolder'),
          identityApi.getCredentials(),
        ]);

        const headers = credentials.token
          ? { Authorization: `Bearer ${credentials.token}` }
          : undefined;

        const res = await fetch(
          `${baseUrl}/naas/namespaces/${encodeURIComponent(namespaceName)}`,
          { credentials: 'same-origin' as const, headers, signal: controller.signal },
        );

        if (!cancelled) {
          if (res.ok) {
            const data = await res.json();
            fetchedFor.current = namespaceName;
            // Pre-fill with the fetched namespace annotations
            onChange({
              applicationName:            data.argoAppName        || '',
              applicationRepoURL:         data.argoRepoUrl        || '',
              applicationTargetRevision:  data.argoTargetRevision || '',
              applicationPath:            data.argoPath           || '',
              applicationSourceType:      data.argoSourceType     || '',
            });
          } else if (res.status !== 404) {
            setFetchError('Unable to load existing ArgoCD details from cluster.');
          }
          // 404 = no prior app — silently leave fields empty.
        }
      } catch {
        if (!cancelled) setFetchError('Unable to load existing ArgoCD details from cluster.');
      } finally {
        window.clearTimeout(timeout);
        if (!cancelled) setFetching(false);
      }
    })();

    return () => { cancelled = true; controller.abort(); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [createArgoApp, namespaceName]);

  function handleChange(field: keyof ArgoAppDetailsValue, value: string) {
    onChange({ ...formData, [field]: value });
  }

  // When the scaffolder fires validation (Next/Review pressed), rawErrors will
  // contain the single sentinel ' ' emitted by the validation function in
  // plugin.ts. Use that as a signal to mark every field as touched so inline
  // per-field errors appear. The sentinel itself is never shown to the user
  // because the framework's FieldErrorTemplate renders it as blank whitespace.
  const submitted = rawErrors.length > 0;

  const [touched, setTouched] = useState<Record<string, boolean>>({});

  const handleBlur = (field: string) => {
    setTouched(prev => ({ ...prev, [field]: true }));
  };

  const getLocalError = (field: keyof ArgoAppDetailsValue): string | undefined => {
    const val = formData[field]?.trim() ?? '';
    if (!val) {
      return (submitted || touched[field]) ? `${field === 'applicationRepoURL' ? 'Repository URL' : field === 'applicationName' ? 'Application Name' : field === 'applicationTargetRevision' ? 'Target Revision' : field === 'applicationPath' ? 'Path' : 'Source Type'} is required.` : undefined;
    }
    if (field === 'applicationRepoURL' && !/^https:\/\/.+$/.test(val)) {
      return 'Must be a valid HTTPS URL (e.g. https://github.com/org/repo).';
    }
    if (field === 'applicationName' && !/^[a-z0-9]([-a-z0-9]*[a-z0-9])?$/.test(val)) {
      return 'Must contain only lowercase alphanumeric characters or hyphens, starting and ending with an alphanumeric character.';
    }
    if (field === 'applicationTargetRevision' && !/^[a-zA-Z0-9_./+-]+$/.test(val)) {
      return 'Must be a valid Git branch, tag, or commit SHA (no whitespace).';
    }
    if (field === 'applicationPath' && !/^(\.|[a-zA-Z0-9_.-]+(\/[a-zA-Z0-9_.-]+)*\/?)$/.test(val)) {
      return "Must be '.' for repo root or a valid relative directory path (e.g. deploy, charts/my-app).";
    }
    return undefined;
  };

  const repoURLError    = getLocalError('applicationRepoURL');
  const appNameError    = getLocalError('applicationName');
  const revisionError   = getLocalError('applicationTargetRevision');
  const pathError       = getLocalError('applicationPath');
  const sourceTypeError = getLocalError('applicationSourceType');

  const showRepoURLError    = (submitted || touched.applicationRepoURL)    && Boolean(repoURLError);
  const showAppNameError    = (submitted || touched.applicationName)        && Boolean(appNameError);
  const showRevisionError   = (submitted || touched.applicationTargetRevision) && Boolean(revisionError);
  const showPathError       = (submitted || touched.applicationPath)        && Boolean(pathError);
  const showSourceTypeError = (submitted || touched.applicationSourceType)  && Boolean(sourceTypeError);

  return (
    <>
      {fetchError && (
        <Typography variant="body2" color="error" style={{ marginTop: 8 }}>
          {fetchError}
        </Typography>
      )}

      <TextField
        id={`${idSchema.$id}-repoURL`}
        label="Repository URL"
        value={formData.applicationRepoURL ?? ''}
        onChange={e => handleChange('applicationRepoURL', e.target.value)}
        onBlur={() => handleBlur('applicationRepoURL')}
        required={required}
        disabled={fetching}
        error={showRepoURLError}
        helperText={
          fetching
            ? 'Loading existing ArgoCD details…'
            : showRepoURLError
            ? repoURLError
            : 'HTTPS URL of the application repository (e.g. https://github.com/org/repo)'
        }
        InputLabelProps={{ shrink: true }}
        margin="normal"
        fullWidth
      />

      <TextField
        id={`${idSchema.$id}-appName`}
        label="Application Name"
        value={formData.applicationName ?? ''}
        onChange={e => handleChange('applicationName', e.target.value)}
        onBlur={() => handleBlur('applicationName')}
        required={required}
        disabled={fetching}
        error={showAppNameError}
        helperText={
          showAppNameError
            ? appNameError
            : 'Lowercase, alphanumeric, hyphens only — used as the ArgoCD Application name'
        }
        InputLabelProps={{ shrink: true }}
        margin="normal"
        fullWidth
      />

      <TextField
        id={`${idSchema.$id}-revision`}
        label="Target Revision"
        value={formData.applicationTargetRevision ?? ''}
        onChange={e => handleChange('applicationTargetRevision', e.target.value)}
        onBlur={() => handleBlur('applicationTargetRevision')}
        required={required}
        disabled={fetching}
        error={showRevisionError}
        helperText={
          showRevisionError
            ? revisionError
            : 'Branch, tag, or commit SHA to track (e.g. main, v1.2.0)'
        }
        InputLabelProps={{ shrink: true }}
        margin="normal"
        fullWidth
      />

      <TextField
        id={`${idSchema.$id}-path`}
        label="Path"
        value={formData.applicationPath ?? ''}
        onChange={e => handleChange('applicationPath', e.target.value)}
        onBlur={() => handleBlur('applicationPath')}
        required={required}
        disabled={fetching}
        error={showPathError}
        helperText={
          showPathError
            ? pathError
            : 'Repo-relative path to manifests or Helm chart. Use . for root.'
        }
        InputLabelProps={{ shrink: true }}
        margin="normal"
        fullWidth
      />

      <TextField
        id={`${idSchema.$id}-sourceType`}
        select
        label="Source Type"
        value={formData.applicationSourceType ?? ''}
        onChange={e => handleChange('applicationSourceType', e.target.value)}
        onBlur={() => handleBlur('applicationSourceType')}
        required={required}
        disabled={fetching}
        error={showSourceTypeError}
        helperText={
          showSourceTypeError
            ? sourceTypeError
            : 'How ArgoCD should interpret the path contents'
        }
        InputLabelProps={{ shrink: true }}
        margin="normal"
        fullWidth
      >
        {SOURCE_TYPES.map(opt => (
          <MenuItem key={opt.value} value={opt.value}>{opt.label}</MenuItem>
        ))}
      </TextField>
    </>
  );
}
