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

{{/*
Derive GPU resources block from accelerator.vendor.
Injects the correct nvidia.com/gpu or amd.com/gpu resource key into the
resources block. Users set only cpu/memory under .Values.resources.
Fails at render time if vendor is set to an unsupported value.
*/}}
{{- define "maas-model-service.gpuResources" -}}
{{- $res := deepCopy .Values.resources -}}
{{- $limits := $res.limits | default dict -}}
{{- $requests := $res.requests | default dict -}}
{{- range $key := list "nvidia.com/gpu" "amd.com/gpu" -}}
  {{- if or (hasKey $limits $key) (hasKey $requests $key) -}}
    {{- fail (printf "resources must not contain %s; set accelerator.vendor and accelerator.count instead" $key) -}}
  {{- end -}}
{{- end -}}
{{- if .Values.accelerator.vendor -}}
  {{- if eq .Values.accelerator.vendor "nvidia" -}}
    {{- $_ := set $res.limits "nvidia.com/gpu" (.Values.accelerator.count | toString) -}}
    {{- $_ := set $res.requests "nvidia.com/gpu" (.Values.accelerator.count | toString) -}}
  {{- else if eq .Values.accelerator.vendor "amd" -}}
    {{- $_ := set $res.limits "amd.com/gpu" (.Values.accelerator.count | toString) -}}
    {{- $_ := set $res.requests "amd.com/gpu" (.Values.accelerator.count | toString) -}}
  {{- else -}}
    {{- fail (printf "accelerator.vendor must be 'nvidia' or 'amd', got: '%s'" .Values.accelerator.vendor) -}}
  {{- end -}}
{{- end -}}
{{- toYaml $res -}}
{{- end }}

{{/*
Merge accelerator.tolerations with scheduling.tolerations.
accelerator.tolerations come first (GPU-specific), then scheduling.tolerations.
*/}}
{{- define "maas-model-service.tolerations" -}}
{{- $accTols := .Values.accelerator.tolerations | default list -}}
{{- $schedTols := .Values.scheduling.tolerations | default list -}}
{{- $all := concat $accTols $schedTols -}}
{{- if $all -}}
{{- toYaml $all -}}
{{- end -}}
{{- end }}

{{/*
Merge accelerator.nodeSelector with scheduling.nodeSelector.
*/}}
{{- define "maas-model-service.nodeSelector" -}}
{{- $accNS := .Values.accelerator.nodeSelector | default dict -}}
{{- $schedNS := .Values.scheduling.nodeSelector | default dict -}}
{{- $merged := merge $accNS $schedNS -}}
{{- if $merged -}}
{{- toYaml $merged -}}
{{- end -}}
{{- end }}
