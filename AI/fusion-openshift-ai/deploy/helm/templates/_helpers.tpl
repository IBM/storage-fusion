{{- define "fusion-openshift-ai.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "fusion-openshift-ai.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "fusion-openshift-ai.name" . -}}
{{- end -}}
{{- end -}}

{{- define "fusion-openshift-ai.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" -}}
{{- end -}}

{{- define "fusion-openshift-ai.labels" -}}
app.kubernetes.io/name: {{ include "fusion-openshift-ai.name" . | quote }}
helm.sh/chart: {{ include "fusion-openshift-ai.chart" . | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service | quote }}
{{- end -}}