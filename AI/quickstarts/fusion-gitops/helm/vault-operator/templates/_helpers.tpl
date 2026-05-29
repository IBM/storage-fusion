{{/*
Expand the name of the chart.
*/}}
{{- define "vault-operator.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "vault-operator.fullname" -}}
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
{{- define "vault-operator.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "vault-operator.labels" -}}
helm.sh/chart: {{ include "vault-operator.chart" . }}
{{ include "vault-operator.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "vault-operator.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vault-operator.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Vault instance labels
*/}}
{{- define "vault.labels" -}}
app.kubernetes.io/name: vault
app.kubernetes.io/instance: {{ .Values.vault.name }}
app.kubernetes.io/component: vault
app.kubernetes.io/managed-by: vault-operator
{{- end }}

{{/*
Vault selector labels
*/}}
{{- define "vault.selectorLabels" -}}
app.kubernetes.io/name: vault
app.kubernetes.io/instance: {{ .Values.vault.name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "vault-operator.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "vault-operator.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Vault namespace
*/}}
{{- define "vault.namespace" -}}
{{- .Values.global.namespace | default "vault" }}
{{- end }}

{{/*
Operator namespace
*/}}
{{- define "operator.namespace" -}}
{{- .Values.operator.namespace | default "vault-operator" }}
{{- end }}

{{/*
Vault server address
*/}}
{{- define "vault.address" -}}
{{- printf "http://%s.%s.svc.cluster.local:%d" .Values.vault.name (include "vault.namespace" .) (.Values.vault.service.port | int) }}
{{- end }}