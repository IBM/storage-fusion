{{/*
Expand the name of the chart.
*/}}
{{- define "maas-model-service.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "maas-model-service.fullname" -}}
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
{{- define "maas-model-service.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "maas-model-service.labels" -}}
helm.sh/chart: {{ include "maas-model-service.chart" . }}
{{ include "maas-model-service.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: model-service
maas.redhat.com/model: {{ .Values.model.name }}
{{- with .Values.labels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "maas-model-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "maas-model-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
maas.redhat.com/model: {{ .Values.model.name }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "maas-model-service.annotations" -}}
{{- with .Values.annotations }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Get the model name
*/}}
{{- define "maas-model-service.modelName" -}}
{{- .Values.model.name }}
{{- end }}

{{/*
Get the model namespace
*/}}
{{- define "maas-model-service.namespace" -}}
{{- .Values.model.namespace }}
{{- end }}

{{/*
Get the gateway reference
*/}}
{{- define "maas-model-service.gatewayRef" -}}
{{- printf "%s/%s" .Values.gateway.namespace .Values.gateway.name }}
{{- end }}

{{/*
Generate tier group names for rate limiting
*/}}
{{- define "maas-model-service.tierGroupName" -}}
{{- printf "maas-tier-%s" . }}
{{- end }}

{{/*
Get inference engine image
*/}}
{{- define "maas-model-service.image" -}}
{{- .Values.inference.image }}
{{- end }}

{{/*
Generate service name
*/}}
{{- define "maas-model-service.serviceName" -}}
{{- printf "%s-service" .Values.model.name }}
{{- end }}

{{/*
Generate ServingRuntime name
*/}}
{{- define "maas-model-service.servingRuntimeName" -}}
{{- if .Values.servingRuntime.runtimeName }}
{{- .Values.servingRuntime.runtimeName }}
{{- else }}
{{- printf "%s-runtime" .Values.model.name }}
{{- end }}
{{- end }}