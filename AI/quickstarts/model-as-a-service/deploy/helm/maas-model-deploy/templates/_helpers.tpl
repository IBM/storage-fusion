{{/*
Expand the name of the chart.
*/}}
{{- define "maas-model-deploy.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "maas-model-deploy.fullname" -}}
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
{{- define "maas-model-deploy.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels applied to all resources.
*/}}
{{- define "maas-model-deploy.labels" -}}
helm.sh/chart: {{ include "maas-model-deploy.chart" . }}
{{ include "maas-model-deploy.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: model-deploy
maas.redhat.com/model: {{ .Values.model.name }}
{{- with .Values.labels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "maas-model-deploy.selectorLabels" -}}
app.kubernetes.io/name: {{ include "maas-model-deploy.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
maas.redhat.com/model: {{ .Values.model.name }}
{{- end }}

{{/*
Common annotations applied to all resources.
*/}}
{{- define "maas-model-deploy.annotations" -}}
{{- with .Values.annotations }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Resolve the target namespace for model resources.
*/}}
{{- define "maas-model-deploy.namespace" -}}
{{- .Values.model.namespace }}
{{- end }}

{{/*
Resolve the model display name, defaulting to the model name.
*/}}
{{- define "maas-model-deploy.displayName" -}}
{{- .Values.model.displayName | default .Values.model.name }}
{{- end }}

{{/*
Resolve the S3 connection secret name.
Defaults to "<model.namespace>-connection" — one shared secret per namespace.
*/}}
{{- define "maas-model-deploy.connectionSecretName" -}}
{{- .Values.s3.connectionSecretName | default (printf "%s-connection" .Values.model.namespace) }}
{{- end }}

{{/*
Resolve the ServiceAccount name used by the LLMInferenceService.
Defaults to "<connection-secret-name>-sa".
*/}}
{{- define "maas-model-deploy.serviceAccountName" -}}
{{- .Values.s3.serviceAccountName | default (printf "%s-sa" (include "maas-model-deploy.connectionSecretName" .)) }}
{{- end }}
