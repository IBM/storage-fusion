{{/*
Expand the name of the chart.
*/}}
{{- define "model-deploy-vllm-cpu.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "model-deploy-vllm-cpu.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "model-deploy-vllm-cpu.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels applied to all resources.
*/}}
{{- define "model-deploy-vllm-cpu.labels" -}}
helm.sh/chart: {{ include "model-deploy-vllm-cpu.chart" . }}
{{ include "model-deploy-vllm-cpu.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: model-deploy-cpu
model.name: {{ .Values.model.name }}
{{- with .Values.labels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "model-deploy-vllm-cpu.selectorLabels" -}}
app.kubernetes.io/name: {{ include "model-deploy-vllm-cpu.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
model.name: {{ .Values.model.name }}
{{- end }}

{{/*
Common annotations applied to all resources.
*/}}
{{- define "model-deploy-vllm-cpu.annotations" -}}
{{- with .Values.annotations }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Resolve the target namespace for model resources.
*/}}
{{- define "model-deploy-vllm-cpu.namespace" -}}
{{- .Values.model.namespace }}
{{- end }}

{{/*
Resolve the model display name, defaulting to the model name.
*/}}
{{- define "model-deploy-vllm-cpu.displayName" -}}
{{- .Values.model.displayName | default .Values.model.name }}
{{- end }}

{{/*
Resolve the S3 connection secret name.
Defaults to "<model.namespace>-connection" — one shared secret per namespace.
*/}}
{{- define "model-deploy-vllm-cpu.connectionSecretName" -}}
{{- .Values.s3.connectionSecretName | default (printf "%s-connection" .Values.model.namespace) }}
{{- end }}

{{/*
Resolve the ServiceAccount name used by the InferenceService storage-initialiser.
Defaults to "<connection-secret-name>-sa".
*/}}
{{- define "model-deploy-vllm-cpu.serviceAccountName" -}}
{{- .Values.s3.serviceAccountName | default (printf "%s-sa" (include "model-deploy-vllm-cpu.connectionSecretName" .)) }}
{{- end }}

{{/*
Resolve the ServingRuntime name.
Defaults to the model name — each model gets its own runtime when deployed
into a shared namespace. Set servingRuntime.name explicitly to reference an
existing shared runtime (e.g. "vllm-cpu-runtime") instead of creating a new one.
*/}}
{{- define "model-deploy-vllm-cpu.servingRuntimeName" -}}
{{- .Values.servingRuntime.name | default .Values.model.name }}
{{- end }}
