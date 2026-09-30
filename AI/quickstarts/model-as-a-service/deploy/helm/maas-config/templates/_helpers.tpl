{{/*
Expand the name of the chart.
*/}}
{{- define "maas-config.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "maas-config.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels applied to all resources.
*/}}
{{- define "maas-config.labels" -}}
helm.sh/chart: {{ include "maas-config.chart" . }}
app.kubernetes.io/name: {{ include "maas-config.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: maas-config
{{- with .Values.labels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Common annotations applied to all resources.
*/}}
{{- define "maas-config.annotations" -}}
{{- with .Values.annotations }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Resolve the MaaS namespace.
*/}}
{{- define "maas-config.maasNamespace" -}}
{{- .Values.maasNamespace | default "models-as-a-service" }}
{{- end }}
