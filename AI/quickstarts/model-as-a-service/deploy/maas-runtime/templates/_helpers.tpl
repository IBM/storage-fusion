{{/*
Expand the name of the chart.
*/}}
{{- define "maas-runtime.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "maas-runtime.fullname" -}}
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
{{- define "maas-runtime.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "maas-runtime.labels" -}}
helm.sh/chart: {{ include "maas-runtime.chart" . }}
{{ include "maas-runtime.selectorLabels" . }}
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
{{- define "maas-runtime.selectorLabels" -}}
app.kubernetes.io/name: {{ include "maas-runtime.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Get the wildcard domain
*/}}
{{- define "maas-runtime.wildcardDomain" -}}
{{- .Values.global.wildcardDomain }}
{{- end }}

{{/*
Get the models namespace
*/}}
{{- define "maas-runtime.modelsNamespace" -}}
{{- .Values.global.modelsNamespace }}
{{- end }}

{{/*
Get the gateway name
*/}}
{{- define "maas-runtime.gatewayName" -}}
{{- .Values.gateway.name }}
{{- end }}

{{/*
Get the gateway namespace
*/}}
{{- define "maas-runtime.gatewayNamespace" -}}
{{- .Values.gateway.namespace }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "maas-runtime.annotations" -}}
{{- with .Values.commonAnnotations }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Generate tier group names
*/}}
{{- define "maas-runtime.tierGroupName" -}}
{{- printf "maas-tier-%s" . }}
{{- end }}