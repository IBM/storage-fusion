import React, { useEffect, useMemo, useState } from 'react';
import { discoveryApiRef, identityApiRef, useApi } from '@backstage/core-plugin-api';
import type { FieldProps } from '@rjsf/utils';
import TextField from '@material-ui/core/TextField';
import Autocomplete from '@material-ui/lab/Autocomplete';
import CircularProgress from '@material-ui/core/CircularProgress';
import MenuItem from '@material-ui/core/MenuItem';
import Typography from '@material-ui/core/Typography';

const REQUEST_TIMEOUT_MS = 10_000;

/**
 * Pure-render autocomplete for an OpenShift group field.
 * Groups are fetched once by the parent and passed in — no per-instance fetch.
 */
function GroupAutocomplete({
  id,
  label,
  value,
  onChange,
  required,
  helperText,
  error,
  groups,
  loading,
  groupsError,
}: {
  id: string;
  label: string;
  value: string;
  onChange: (v: string) => void;
  required?: boolean;
  helperText?: string;
  error?: boolean;
  groups: string[];
  loading: boolean;
  groupsError?: string;
}) {
  return (
    <Autocomplete
      id={id}
      options={groups}
      loading={loading}
      value={value || null}
      onChange={(_e, v) => onChange(v ?? '')}
      renderInput={params => (
        <TextField
          {...params}
          label={label}
          required={required}
          error={error}
          helperText={groupsError ?? helperText}
          margin="normal"
          InputProps={{
            ...params.InputProps,
            endAdornment: (
              <>
                {loading ? <CircularProgress size={16} /> : null}
                {params.InputProps.endAdornment}
              </>
            ),
          }}
        />
      )}
    />
  );
}

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
 * The value this field emits — a flat object containing the selected
 * project/environment plus all pre-populated metadata. The template
 * references each key directly via `${{ parameters.naasSelection.projectName }}`.
 */
export interface NaaSSelectionValue {
  projectName: string;
  environment: string;
  businessUnit: string;
  size: string;
  ownerGroup: string;
  developerGroup: string;
  viewerGroup: string;
}

const EMPTY: NaaSSelectionValue = {
  projectName: '',
  environment: '',
  businessUnit: '',
  size: '',
  ownerGroup: '',
  developerGroup: '',
  viewerGroup: '',
};

const BUSINESS_UNITS = [
  { value: 'engineering', label: 'Engineering' },
  { value: 'marketing',   label: 'Marketing'   },
  { value: 'finance',     label: 'Finance'      },
  { value: 'retail',      label: 'Retail'       },
];

const SIZE_TIERS = [
  { value: 'small',  label: 'Small  (4 CPU · 8 Gi RAM)'   },
  { value: 'medium', label: 'Medium (8 CPU · 16 Gi RAM)'  },
  { value: 'large',  label: 'Large  (16 CPU · 32 Gi RAM)' },
];

/**
 * Compound scaffolder field for the NaaS Update template.
 *
 * Renders cascading dropdowns for project and environment (filtered to only
 * the environments that exist for the selected project), then pre-populates
 * all remaining fields — businessUnit, size, ownerGroup, developerGroup,
 * viewerGroup — from the existing namespace labels so the user can review
 * and update them in a single step.
 *
 * The field emits a single flat object so all values flow through one
 * `onChange` call without needing to write to sibling fields.
 *
 * Template usage:
 *   ui:field: NaaSProjectField
 *
 * Reference values downstream:
 *   ${{ parameters.naasSelection.projectName }}
 *   ${{ parameters.naasSelection.environment }}
 *   ${{ parameters.naasSelection.businessUnit }}
 *   ${{ parameters.naasSelection.size }}
 *   ${{ parameters.naasSelection.ownerGroup }}
 *   ${{ parameters.naasSelection.developerGroup }}
 *   ${{ parameters.naasSelection.viewerGroup }}
 */
export function NaaSProjectField(props: FieldProps<NaaSSelectionValue>) {
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
  const [groups, setGroups] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [fetchError, setFetchError] = useState<string | undefined>();
  const [groupsError, setGroupsError] = useState<string | undefined>();

  // ── Fetch namespaces and groups in parallel once on mount ────────────────
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
        const fetchOpts = { credentials: 'same-origin' as const, headers, signal: controller.signal };

        const [nsRes, grpRes] = await Promise.all([
          fetch(`${baseUrl}/naas/namespaces`, fetchOpts),
          fetch(`${baseUrl}/groups`, fetchOpts),
        ]);

        if (!cancelled) {
          if (nsRes.ok) {
            const { namespaces: fetched } = await nsRes.json();
            setNamespaces(fetched ?? []);
          } else {
            setFetchError('Unable to load NaaS projects from cluster.');
          }

          if (grpRes.ok) {
            const { groups: fetched } = await grpRes.json();
            setGroups(fetched ?? []);
          } else {
            setGroupsError('Unable to load groups from cluster.');
          }
        }
      } catch {
        if (!cancelled) {
          setFetchError('Unable to load NaaS projects from cluster.');
          setGroupsError('Unable to load groups from cluster.');
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

  // Whether the cascading selectors have been fully resolved
  const namespaceSelected = !!(formData.projectName && formData.environment);

  // ── Handlers ─────────────────────────────────────────────────────────────
  function handleProjectChange(projectName: string | null) {
    // Reset all fields when project changes.
    onChange({ ...EMPTY, projectName: projectName ?? '' });
  }

  function handleEnvironmentChange(environment: string | null) {
    const env = environment ?? '';
    const match = namespaces.find(
      ns => ns.projectName === formData.projectName && ns.environment === env,
    );

    // Pre-populate all fields from the matched namespace record.
    onChange({
      projectName: formData.projectName,
      environment: env,
      businessUnit: match?.businessUnit ?? '',
      size:          match?.size          ?? '',
      ownerGroup:    match?.ownerGroup    ?? '',
      developerGroup: match?.developerGroup ?? '',
      viewerGroup:   match?.viewerGroup   ?? '',
    });
  }

  function handleFieldChange(field: keyof NaaSSelectionValue, value: string) {
    onChange({ ...formData, [field]: value });
  }

  const hasError = rawErrors.length > 0;

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
            error={hasError && !formData.projectName}
            helperText={
              fetchError ??
              (hasError && !formData.projectName
                ? 'Project Name is required'
                : 'Select the NaaS-provisioned project to update')
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
            error={hasError && !!formData.projectName && !formData.environment}
            helperText={
              !formData.projectName
                ? 'Select a project first'
                : hasError && !formData.environment
                ? 'Environment is required'
                : 'Only environments provisioned for this project are shown'
            }
            margin="normal"
          />
        )}
      />

      {/* ── Pre-populated editable fields — shown once a namespace is selected ── */}
      {namespaceSelected && (
        <>
          <Typography variant="subtitle2" style={{ marginTop: 16, marginBottom: 4 }}>
            Namespace Details
          </Typography>

          {/* Business Unit */}
          <TextField
            id={`${idSchema.$id}-businessUnit`}
            select
            label="Business Unit / Cost Center"
            value={formData.businessUnit}
            onChange={e => handleFieldChange('businessUnit', e.target.value)}
            required={required}
            error={hasError && !formData.businessUnit}
            helperText={
              hasError && !formData.businessUnit
                ? 'Business Unit is required'
                : 'Used for chargeback and resource tracking labels'
            }
            margin="normal"
            fullWidth
          >
            {BUSINESS_UNITS.map(opt => (
              <MenuItem key={opt.value} value={opt.value}>{opt.label}</MenuItem>
            ))}
          </TextField>

          <Typography variant="subtitle2" style={{ marginTop: 16, marginBottom: 4 }}>
            Resource Sizing
          </Typography>

          {/* Size */}
          <TextField
            id={`${idSchema.$id}-size`}
            select
            label="Namespace Size Tier"
            value={formData.size}
            onChange={e => handleFieldChange('size', e.target.value)}
            required={required}
            error={hasError && !formData.size}
            helperText={
              hasError && !formData.size
                ? 'Size is required'
                : 'Pre-configured resource quota allocations'
            }
            margin="normal"
            fullWidth
          >
            {SIZE_TIERS.map(opt => (
              <MenuItem key={opt.value} value={opt.value}>{opt.label}</MenuItem>
            ))}
          </TextField>

          <Typography variant="subtitle2" style={{ marginTop: 16, marginBottom: 4 }}>
            Access Control
          </Typography>

          {/* Owner Group */}
          <GroupAutocomplete
            id={`${idSchema.$id}-ownerGroup`}
            label="Owner Group"
            value={formData.ownerGroup}
            onChange={v => handleFieldChange('ownerGroup', v)}
            required={required}
            error={hasError && !formData.ownerGroup}
            helperText={
              hasError && !formData.ownerGroup
                ? 'Owner Group is required'
                : 'OpenShift group granted namespace-admin rights'
            }
            groups={groups}
            loading={loading}
            groupsError={groupsError}
          />

          {/* Developer Group */}
          <GroupAutocomplete
            id={`${idSchema.$id}-developerGroup`}
            label="Developer Group (optional)"
            value={formData.developerGroup}
            onChange={v => handleFieldChange('developerGroup', v)}
            helperText="OpenShift group granted namespace-developer rights. Leave blank if not required."
            groups={groups}
            loading={loading}
            groupsError={groupsError}
          />

          {/* Viewer Group */}
          <GroupAutocomplete
            id={`${idSchema.$id}-viewerGroup`}
            label="Viewer Group (optional)"
            value={formData.viewerGroup}
            onChange={v => handleFieldChange('viewerGroup', v)}
            helperText="OpenShift group granted namespace-viewer (read-only) rights. Leave blank if not required."
            groups={groups}
            loading={loading}
            groupsError={groupsError}
          />
        </>
      )}
    </>
  );
}
