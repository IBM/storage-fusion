import React, { useEffect, useMemo, useState } from 'react';
import { discoveryApiRef, identityApiRef, useApi } from '@backstage/core-plugin-api';
import type { FieldProps } from '@rjsf/utils';
import TextField from '@material-ui/core/TextField';
import Autocomplete from '@material-ui/lab/Autocomplete';
import CircularProgress from '@material-ui/core/CircularProgress';
const REQUEST_TIMEOUT_MS = 10_000;

interface NaaSNamespaceMetadata {
  projectName: string;
  environment: string;
  businessUnit: string;
  size: string;
  ownerGroup: string;
  developerGroup: string;
  viewerGroup: string;
}

/**
 * The value this field emits — project/environment identity plus the typed
 * confirmation string. The template references sub-keys via
 * `${{ parameters.naasDeleteSelection.projectName }}` etc.
 *
 * `confirmDelete` is intentionally excluded from the review page via
 * `ui:backstage: review: show: false` in the template.
 */
export interface NaaSDeleteSelectionValue {
  projectName: string;
  environment: string;
  confirmDelete: string;
}

const EMPTY: NaaSDeleteSelectionValue = {
  projectName: '',
  environment: '',
  confirmDelete: '',
};

/**
 * Compound scaffolder field for the NaaS Delete template.
 *
 * Renders cascading dropdowns for project and environment — filtered to only
 * namespaces that were provisioned through NaaS — followed by a confirmation
 * text input that must exactly match `{projectName}-{environment}` before the
 * step can proceed.
 *
 * Template usage:
 *   ui:field: NaaSDeleteField
 *
 * Reference values downstream:
 *   ${{ parameters.naasDeleteSelection.projectName }}
 *   ${{ parameters.naasDeleteSelection.environment }}
 */
export function NaaSDeleteField(props: FieldProps<NaaSDeleteSelectionValue>) {
  const {
    formData = EMPTY,
    idSchema,
    onChange,
    rawErrors = [],
    required,
  } = props;

  const discoveryApi = useApi(discoveryApiRef);
  const identityApi = useApi(identityApiRef);

  const [namespaces, setNamespaces] = useState<NaaSNamespaceMetadata[]>([]);
  const [loading, setLoading] = useState(true);
  const [fetchError, setFetchError] = useState<string | undefined>();

  // ── Fetch NaaS-provisioned namespaces once on mount ──────────────────────
  useEffect(() => {
    let cancelled = false;
    const controller = new AbortController();
    const timeout = window.setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

    (async () => {
      try {
        const [baseUrl, credentials] = await Promise.all([
          discoveryApi.getBaseUrl('scaffolder'),
          identityApi.getCredentials(),
        ]);

        const headers = credentials.token
          ? { Authorization: `Bearer ${credentials.token}` }
          : undefined;

        const res = await fetch(`${baseUrl}/naas/namespaces`, {
          credentials: 'same-origin' as const,
          headers,
          signal: controller.signal,
        });

        if (!cancelled) {
          if (res.ok) {
            const { namespaces: fetched } = await res.json();
            setNamespaces(fetched ?? []);
          } else {
            setFetchError('Unable to load NaaS projects from cluster.');
          }
        }
      } catch {
        if (!cancelled) {
          setFetchError('Unable to load NaaS projects from cluster.');
        }
      } finally {
        window.clearTimeout(timeout);
        if (!cancelled) setLoading(false);
      }
    })();

    return () => {
      cancelled = true;
      controller.abort();
    };
  }, [discoveryApi, identityApi]);

  // ── Derived option lists ─────────────────────────────────────────────────
  const projectNames = useMemo(
    () => Array.from(new Set(namespaces.map(ns => ns.projectName))).sort(),
    [namespaces],
  );

  const environmentsForProject = useMemo(() => {
    if (!formData.projectName) return [];
    return namespaces
      .filter(ns => ns.projectName === formData.projectName)
      .map(ns => ns.environment)
      .sort();
  }, [namespaces, formData.projectName]);

  // ── Handlers ─────────────────────────────────────────────────────────────
  function handleProjectChange(projectName: string | null) {
    onChange({ ...EMPTY, projectName: projectName ?? '' });
  }

  function handleEnvironmentChange(environment: string | null) {
    onChange({
      projectName: formData.projectName,
      environment: environment ?? '',
      confirmDelete: '',
    });
  }

  function handleConfirmChange(value: string) {
    onChange({ ...formData, confirmDelete: value });
  }

  // ── Derived state ────────────────────────────────────────────────────────
  const namespaceSelected = !!(formData.projectName && formData.environment);
  const expectedNamespace = namespaceSelected
    ? `${formData.projectName}-${formData.environment}`
    : '';
  const confirmMismatch =
    namespaceSelected &&
    formData.confirmDelete.length > 0 &&
    formData.confirmDelete !== expectedNamespace;

  // rawErrors.length > 0 means Next was pressed — use as a "submitted" signal
  // to show required-field errors, but don't let stale rawErrors keep the
  // confirm field red once the user has started correcting their input.
  const submitted = rawErrors.length > 0;
  const [confirmTouched, setConfirmTouched] = useState(false);

  const loadingAdornment = (endAdornment: React.ReactNode) => (
    <>
      {loading ? <CircularProgress size={16} /> : null}
      {endAdornment}
    </>
  );

  return (
    <>
      {/* ── Project Name ── */}
      <Autocomplete
        id={`${idSchema.$id}-project`}
        options={projectNames}
        loading={loading}
        value={formData.projectName || null}
        onChange={(_e, value) => handleProjectChange(value)}
        renderInput={params => (
          <TextField
            {...params}
            label="Project Name"
            required={required}
            error={submitted && !formData.projectName}
            helperText={
              fetchError ??
              (submitted && !formData.projectName
                ? 'Project Name is required'
                : 'Select the NaaS-provisioned project to delete')
            }
            margin="normal"
            InputProps={{
              ...params.InputProps,
              endAdornment: loadingAdornment(params.InputProps.endAdornment),
            }}
          />
        )}
      />

      {/* ── Environment — filtered to environments that exist for the project ── */}
      <Autocomplete
        id={`${idSchema.$id}-environment`}
        options={environmentsForProject}
        disabled={!formData.projectName}
        value={formData.environment || null}
        onChange={(_e, value) => handleEnvironmentChange(value)}
        getOptionLabel={opt => opt.charAt(0).toUpperCase() + opt.slice(1)}
        renderInput={params => (
          <TextField
            {...params}
            label="Environment"
            required={required}
            error={submitted && !!formData.projectName && !formData.environment}
            helperText={
              !formData.projectName
                ? 'Select a project first'
                : submitted && !formData.environment
                ? 'Environment is required'
                : 'Only environments provisioned for this project are shown'
            }
            margin="normal"
          />
        )}
      />

      {/* ── Confirm Deletion — shown once project + environment are selected ── */}
      {namespaceSelected && (
        <>
          <TextField
            id={`${idSchema.$id}-confirmDelete`}
            label="Type namespace name to confirm"
            value={formData.confirmDelete}
            onChange={e => handleConfirmChange(e.target.value)}
            onBlur={() => setConfirmTouched(true)}
            required={required}
            error={confirmMismatch || ((submitted || confirmTouched) && !formData.confirmDelete)}
            helperText={
              confirmMismatch
                ? `Must match exactly: ${expectedNamespace}`
                : (submitted || confirmTouched) && !formData.confirmDelete
                ? 'Confirmation is required'
                : `Type "${expectedNamespace}" to confirm you want to permanently delete this namespace`
            }
            margin="normal"
            fullWidth
            placeholder={expectedNamespace}
          />
        </>
      )}
    </>
  );
}
