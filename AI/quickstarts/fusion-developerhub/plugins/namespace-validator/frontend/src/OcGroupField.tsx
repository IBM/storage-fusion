import React, { useEffect, useState } from 'react';
import { discoveryApiRef, identityApiRef, useApi } from '@backstage/core-plugin-api';
import type { FieldProps } from '@rjsf/utils';
import TextField from '@material-ui/core/TextField';
import Autocomplete from '@material-ui/lab/Autocomplete';
import CircularProgress from '@material-ui/core/CircularProgress';

const REQUEST_TIMEOUT_MS = 10_000;

export function OcGroupField(props: FieldProps<string>) {
  const { formData = '', idSchema, onChange, rawErrors = [], required, schema } = props;
  const discoveryApi = useApi(discoveryApiRef);
  const identityApi = useApi(identityApiRef);

  const [groups, setGroups] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [fetchError, setFetchError] = useState<string | undefined>();

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

        const response = await fetch(`${baseUrl}/groups`, {
          credentials: 'same-origin',
          headers: credentials.token ? { Authorization: `Bearer ${credentials.token}` } : undefined,
          signal: controller.signal,
        });

        if (!response.ok) throw new Error();
        const { groups: fetched } = await response.json();

        if (!cancelled) {
          setGroups(fetched ?? []);
          setFetchError(undefined);
        }
      } catch {
        if (!cancelled) {
          setFetchError('Unable to load groups from cluster.');
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

  const hasError = rawErrors.length > 0;

  return (
    <Autocomplete
      id={idSchema.$id}
      options={groups}
      loading={loading}
      value={formData || null}
      onChange={(_event, newValue) => {
        onChange(newValue ?? '');
      }}
      renderInput={params => (
        <TextField
          {...params}
          label={schema.title}
          required={required}
          error={hasError}
          helperText={
            fetchError ??
            (hasError ? rawErrors[0] : schema.description)
          }
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
