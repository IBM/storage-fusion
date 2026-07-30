{{/*
Expand the name of the chart.
*/}}
{{- define "model-registry-gitops.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "model-registry-gitops.fullname" -}}
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
{{- define "model-registry-gitops.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "model-registry-gitops.labels" -}}
helm.sh/chart: {{ include "model-registry-gitops.chart" . }}
{{ include "model-registry-gitops.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "model-registry-gitops.selectorLabels" -}}
app.kubernetes.io/name: {{ include "model-registry-gitops.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "model-registry-gitops.serviceAccountName" -}}
{{- default "model-reconciler" .Values.reconciler.serviceAccountName }}
{{- end }}

{{/*
Model Registry host URL
*/}}
{{- define "model-registry-gitops.registryHost" -}}
{{- printf "%s.%s.svc.cluster.local" .Values.modelRegistry.serviceName .Values.modelRegistry.namespace }}
{{- end }}