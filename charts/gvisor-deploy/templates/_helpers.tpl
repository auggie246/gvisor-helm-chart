{{/*
Expand the name of the chart.
*/}}
{{- define "gvisor-deploy.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "gvisor-deploy.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Chart name and version label value.
*/}}
{{- define "gvisor-deploy.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Namespace for namespaced resources.
*/}}
{{- define "gvisor-deploy.namespace" -}}
{{- default .Release.Namespace .Values.namespaceOverride -}}
{{- end -}}

{{/*
Common labels.
*/}}
{{- define "gvisor-deploy.labels" -}}
helm.sh/chart: {{ include "gvisor-deploy.chart" . }}
{{ include "gvisor-deploy.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: gvisor-deploy
{{- end -}}

{{/*
Selector labels.
*/}}
{{- define "gvisor-deploy.selectorLabels" -}}
app.kubernetes.io/name: {{ include "gvisor-deploy.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
ServiceAccount name.
*/}}
{{- define "gvisor-deploy.serviceAccountName" -}}
{{- include "gvisor-deploy.fullname" . -}}
{{- end -}}

{{/*
Installer image reference.
*/}}
{{- define "gvisor-deploy.image" -}}
{{- $tag := .Values.image.tag | default "latest" -}}
{{- printf "%s:%s" .Values.image.repository $tag -}}
{{- end -}}
