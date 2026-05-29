{{/*
Expand the name of the chart.
*/}}
{{- define "fusion-gitops.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "fusion-gitops.fullname" -}}
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
{{- define "fusion-gitops.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "fusion-gitops.labels" -}}
helm.sh/chart: {{ include "fusion-gitops.chart" . }}
{{ include "fusion-gitops.selectorLabels" . }}
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
{{- define "fusion-gitops.selectorLabels" -}}
app.kubernetes.io/name: {{ include "fusion-gitops.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Operator namespace
*/}}
{{- define "fusion-gitops.operatorNamespace" -}}
{{- .Values.operator.namespace | default "openshift-gitops-operator" }}
{{- end }}

{{/*
ArgoCD namespace
*/}}
{{- define "fusion-gitops.argoCDNamespace" -}}
{{- .Values.argocd.namespace | default "openshift-gitops" }}
{{- end }}

{{/*
ArgoCD instance name
*/}}
{{- define "fusion-gitops.argoCDName" -}}
{{- .Values.argocd.name | default "argocd-fusion" }}
{{- end }}

{{/*
Storage class for block storage
*/}}
{{- define "fusion-gitops.storageClassBlock" -}}
{{- .Values.storage.blockStorageClass | default "fusion-hci-block" }}
{{- end }}

{{/*
Storage class for file storage
*/}}
{{- define "fusion-gitops.storageClassFile" -}}
{{- .Values.storage.fileStorageClass | default "fusion-hci-file" }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "fusion-gitops.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "fusion-gitops.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return true if storage classes should be created
*/}}
{{- define "fusion-gitops.createStorageClasses" -}}
{{- if .Values.storage.createStorageClasses }}
{{- true }}
{{- end }}
{{- end }}

{{/*
Return true if operator should be installed
*/}}
{{- define "fusion-gitops.installOperator" -}}
{{- if .Values.operator.install }}
{{- true }}
{{- end }}
{{- end }}

{{/*
Return true if ArgoCD instance should be created
*/}}
{{- define "fusion-gitops.createArgoCDInstance" -}}
{{- if .Values.argocd.enabled }}
{{- true }}
{{- end }}
{{- end }}

{{/*
Return true if monitoring should be enabled
*/}}
{{- define "fusion-gitops.enableMonitoring" -}}
{{- if .Values.monitoring.enabled }}
{{- true }}
{{- end }}
{{- end }}

{{/*
Return true if network policies should be created
*/}}
{{- define "fusion-gitops.createNetworkPolicies" -}}
{{- if .Values.networkPolicy.enabled }}
{{- true }}
{{- end }}
{{- end }}

{{/*
Return the appropriate apiVersion for Subscription
*/}}
{{- define "fusion-gitops.subscription.apiVersion" -}}
{{- if .Capabilities.APIVersions.Has "operators.coreos.com/v1alpha1" -}}
operators.coreos.com/v1alpha1
{{- else -}}
operators.coreos.com/v1alpha1
{{- end -}}
{{- end -}}

{{/*
Return the appropriate apiVersion for ArgoCD
*/}}
{{- define "fusion-gitops.argocd.apiVersion" -}}
{{- if .Capabilities.APIVersions.Has "argoproj.io/v1beta1" -}}
argoproj.io/v1beta1
{{- else if .Capabilities.APIVersions.Has "argoproj.io/v1alpha1" -}}
argoproj.io/v1alpha1
{{- else -}}
argoproj.io/v1beta1
{{- end -}}
{{- end -}}

{{/*
Return the appropriate apiVersion for Route (OpenShift)
*/}}
{{- define "fusion-gitops.route.apiVersion" -}}
{{- if .Capabilities.APIVersions.Has "route.openshift.io/v1" -}}
route.openshift.io/v1
{{- else -}}
route.openshift.io/v1
{{- end -}}
{{- end -}}

{{/*
Check if running on OpenShift
*/}}
{{- define "fusion-gitops.isOpenShift" -}}
{{- if .Capabilities.APIVersions.Has "route.openshift.io/v1" -}}
{{- true -}}
{{- end -}}
{{- end -}}

{{/*
Generate storage parameters for Fusion HCI
*/}}
{{- define "fusion-gitops.storageParameters" -}}
{{- $params := dict }}
{{- if .replicationFactor }}
{{- $_ := set $params "replicationFactor" (.replicationFactor | toString) }}
{{- end }}
{{- if .performanceTier }}
{{- $_ := set $params "performanceTier" .performanceTier }}
{{- end }}
{{- if .dataProtection }}
{{- $_ := set $params "dataProtection" .dataProtection }}
{{- end }}
{{- if .compression }}
{{- $_ := set $params "compression" .compression }}
{{- end }}
{{- if .deduplication }}
{{- $_ := set $params "deduplication" .deduplication }}
{{- end }}
{{- if .encryption }}
{{- $_ := set $params "encryption" .encryption }}
{{- end }}
{{- toYaml $params }}
{{- end }}

{{/*
Generate resource requests and limits
*/}}
{{- define "fusion-gitops.resources" -}}
{{- if .requests }}
requests:
  {{- if .requests.cpu }}
  cpu: {{ .requests.cpu }}
  {{- end }}
  {{- if .requests.memory }}
  memory: {{ .requests.memory }}
  {{- end }}
{{- end }}
{{- if .limits }}
limits:
  {{- if .limits.cpu }}
  cpu: {{ .limits.cpu }}
  {{- end }}
  {{- if .limits.memory }}
  memory: {{ .limits.memory }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Validate required values
*/}}
{{- define "fusion-gitops.validateValues" -}}
{{- if and .Values.argocd.enabled (not .Values.operator.install) }}
{{- fail "ArgoCD instance requires operator to be installed. Set operator.install=true or argocd.enabled=false" }}
{{- end }}
{{- if and .Values.storage.createPVCs (not .Values.storage.createStorageClasses) }}
{{- fail "PVCs require storage classes. Set storage.createStorageClasses=true or storage.createPVCs=false" }}
{{- end }}
{{- end }}