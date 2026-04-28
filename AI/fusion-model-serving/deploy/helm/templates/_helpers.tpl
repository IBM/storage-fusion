{{- define "fusion-model-serving.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "fusion-model-serving.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- .Values.model.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "fusion-model-serving.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" -}}
{{- end -}}

{{- define "fusion-model-serving.commonLabels" -}}
app.kubernetes.io/name: {{ .Values.labels.appName | quote }}
validated-patterns.io/pattern: {{ .Values.labels.pattern | quote }}
helm.sh/chart: {{ include "fusion-model-serving.chart" . | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service | quote }}
{{- end -}}