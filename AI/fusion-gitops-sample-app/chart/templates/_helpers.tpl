{{/*
_helpers.tpl — shared template helpers for llmops-chat-app
*/}}

{{/* Expand the name of the chart. */}}
{{- define "llmops.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Common labels */}}
{{- define "llmops.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: llmops-chat-app
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
validated-patterns.io/pattern: llmops-platform
{{- end }}

{{/* Selector labels */}}
{{- define "llmops.selectorLabels" -}}
app.kubernetes.io/name: llmops-chat-app
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Build the env var block for a single CPU model entry.
Called with a dict: task (string) + model (the model map entry from .Values.cpu.models).

Produces three env vars per model:
  MODEL_URL_<TASK>    → KServe predictor Service URL
  MODEL_ID_<TASK>     → vLLM model ID string
  MODEL_TOKEN_<TASK>  → bearer token from the LOCAL llmops-cpu-tokens Secret
                        (token_chat / token_code / token_summarize)

The token is always read from llmops-cpu-tokens in the app namespace.
That secret is populated by either cpu.tokens.externalSecret or cpu.tokens.hardcoded.
A secretKeyRef cannot cross namespaces, so we never reference the origin
secret in deploy-models-cpu directly from the pod.
*/}}
{{- define "llmops.cpuModelEnv" -}}
{{- $task := .task | upper -}}
{{- $taskLower := .task | lower -}}
{{- $m    := .model -}}
- name: MODEL_URL_{{ $task }}
  value: {{ $m.url | quote }}
- name: MODEL_ID_{{ $task }}
  value: {{ $m.id | quote }}
- name: MODEL_TOKEN_{{ $task }}
  valueFrom:
    secretKeyRef:
      name: "llmops-cpu-tokens"
      key: "token_{{ $taskLower }}"
      optional: true
{{- /* MODEL_CAPS_<TASK>: comma-separated capability string, defaults to task name if not set */}}
- name: MODEL_CAPS_{{ $task }}
  value: {{ $m.capabilities | default $taskLower | quote }}
{{- end }}
