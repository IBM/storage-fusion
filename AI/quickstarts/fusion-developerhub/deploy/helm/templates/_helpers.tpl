{{/*
Expand the name of the chart.
*/}}
{{- define "fusion-developer-hub.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "fusion-developer-hub.fullname" -}}
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
{{- define "fusion-developer-hub.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "fusion-developer-hub.labels" -}}
helm.sh/chart: {{ include "fusion-developer-hub.chart" . }}
{{ include "fusion-developer-hub.selectorLabels" . }}
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
{{- define "fusion-developer-hub.selectorLabels" -}}
app.kubernetes.io/name: {{ include "fusion-developer-hub.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Get the wildcard domain.
Single source of truth: global.wildcardDomain in values.yaml.
Run:  oc get ingress.config.openshift.io cluster -o jsonpath='{.spec.domain}'
*/}}
{{- define "fusion-developer-hub.wildcardDomain" -}}
{{- .Values.global.wildcardDomain }}
{{- end }}

{{/*
Get the namespace for Developer Hub resources.
Uses .Release.Namespace by default, overridable via developerHub.namespace.
*/}}
{{- define "fusion-developer-hub.namespace" -}}
{{- default .Release.Namespace .Values.developerHub.namespace }}
{{- end }}

{{/*
Auto-derive the RHDH base URL.
Pattern: https://backstage-<instanceName>-<namespace>.<wildcardDomain>
Respects developerHub.config.hostname if explicitly set (custom FQDN case).
Never hardcode this value — it is always computed from wildcardDomain + instanceName + namespace.
*/}}
{{- define "fusion-developer-hub.rhdhBaseUrl" -}}
{{- if .Values.developerHub.config.hostname }}
{{- printf "https://%s" .Values.developerHub.config.hostname }}
{{- else }}
{{- printf "https://backstage-%s-%s.%s"
      (.Values.developerHub.instanceName | default "developer-hub")
      (include "fusion-developer-hub.namespace" .)
      (include "fusion-developer-hub.wildcardDomain" .) }}
{{- end }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "fusion-developer-hub.annotations" -}}
meta.helm.sh/release-name: {{ .Release.Name }}
meta.helm.sh/release-namespace: {{ .Release.Namespace }}
{{- with .Values.commonAnnotations }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Service Account name for RHOAI connector
*/}}
{{- define "fusion-developer-hub.serviceAccountName" -}}
{{- if .Values.developerHub.serviceAccount.create }}
{{- default (printf "%s-rhoai" (include "fusion-developer-hub.fullname" .)) .Values.developerHub.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.developerHub.serviceAccount.name }}
{{- end }}
{{- end }}

# Made with Bob