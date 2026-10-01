import React, { useEffect, useRef, useState } from 'react';
import { discoveryApiRef, identityApiRef, useApi } from '@backstage/core-plugin-api';
import type { FieldProps } from '@rjsf/utils';
import TextField from '@material-ui/core/TextField';
import CircularProgress from '@material-ui/core/CircularProgress';
import InputAdornment from '@material-ui/core/InputAdornment';

const PROJECT_NAME_PATTERN = /^[a-z0-9]([-a-z0-9]*[a-z0-9])?$/;
const CHECK_DELAY_MS = 500;
const REQUEST_TIMEOUT_MS = 6_000;

export function NamespaceNameField(props: FieldProps<string>) {
  const { formData = '', idSchema, onChange, required, schema, uiSchema, rawErrors = [] } = props;
  const discoveryApi = useApi(discoveryApiRef);
  const identityApi = useApi(identityApiRef);

  const uiOptions = uiSchema?.['ui:options'] as Record<string, unknown> | undefined;
  const environmentField = (uiOptions?.['environmentField'] as string) || 'environment';
  const formContext = props.formContext as { formData?: Record<string, unknown> } | undefined;
  const environmentValue = formContext?.formData?.[environmentField] as string | undefined;

  const [status, setStatus] = useState<'idle' | 'checking' | 'available' | 'exists' | 'error'>('idle');
  const [localMessage, setLocalMessage] = useState<string | undefined>();
  const requestId = useRef(0);

  useEffect(() => {
    const namespace = environmentValue ? `${formData}-${environmentValue}` : '';
    const currentRequestId = ++requestId.current;

    if (!formData) {
      setStatus('idle');
      setLocalMessage(undefined);
      return;
    }

    if (!PROJECT_NAME_PATTERN.test(formData)) {
      setStatus('error');
      setLocalMessage('Invalid project name format. Use lowercase, alphanumeric, and hyphens.');
      return;
    }

    if (!environmentValue) {
      setStatus('idle');
      setLocalMessage('Select an environment before continuing.');
      return;
    }

    setStatus('checking');
    setLocalMessage('Checking namespace availability...');

    const timer = window.setTimeout(async () => {
      const controller = new AbortController();
      const timeout = window.setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

      try {
        const [baseUrl, credentials] = await Promise.all([
          discoveryApi.getBaseUrl('scaffolder'),
          identityApi.getCredentials(),
        ]);
        
        const response = await fetch(`${baseUrl}/namespaces/${encodeURIComponent(namespace)}`, {
          credentials: 'same-origin',
          headers: credentials.token ? { Authorization: `Bearer ${credentials.token}` } : undefined,
          signal: controller.signal,
        });

        if (!response.ok) throw new Error();
        if (currentRequestId !== requestId.current) return;

        const { exists } = await response.json();

        if (exists) {
          setStatus('exists');
          setLocalMessage(`Namespace "${namespace}" already exists.`);
        } else {
          setStatus('available');
          setLocalMessage('Namespace is available.');
        }
      } catch {
        if (currentRequestId !== requestId.current) return;
        setStatus('error');
        setLocalMessage('Unable to validate namespace availability.');
      } finally {
        window.clearTimeout(timeout);
      }
    }, CHECK_DELAY_MS);

    return () => {
      window.clearTimeout(timer);
      requestId.current++;
    };
  }, [discoveryApi, environmentValue, formData, identityApi]);

  const hasLocalError = status === 'exists' || status === 'error';
  // Only surface the framework's rawErrors signal when the field is also locally
  // invalid (empty or failed check). This prevents the field staying red after
  // the user edits away from an existing namespace name while rawErrors is still
  // populated from a previous Next-click.
  const displayError = hasLocalError || (rawErrors.length > 0 && !formData);

  // localMessage always takes priority — the validator now emits a silent
  // sentinel (' ') so rawErrors[0] would be blank whitespace, not useful text.
  let helperText = schema.description;
  if (localMessage) helperText = localMessage;

  return (
    <TextField
      id={idSchema.$id}
      label={schema.title ?? 'Project Name'}
      onChange={e => onChange(e.target.value)}
      required={required}
      value={formData}
      error={displayError}
      helperText={helperText}
      autoFocus={Boolean(uiSchema?.['ui:autofocus'])}
      fullWidth
      margin="normal"
      InputProps={{
        endAdornment: status === 'checking' ? (
          <InputAdornment position="end">
            <CircularProgress size={16} />
          </InputAdornment>
        ) : null,
      }}
    />
  );
}
