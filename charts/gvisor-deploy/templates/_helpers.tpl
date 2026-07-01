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

{{/*
Dispatcher (kubectl) image reference for the job-mode dispatcher.
*/}}
{{- define "gvisor-deploy.kubectlImage" -}}
{{- printf "%s:%s" .Values.job.kubectlImage.repository .Values.job.kubectlImage.tag -}}
{{- end -}}

{{/*
ServiceAccount name for the job-mode dispatcher. Separate from the main
ServiceAccount: the dispatcher is a pure API client (list/patch nodes, manage
Jobs) and must NOT carry the privileged host-mutation rights of the installer.
*/}}
{{- define "gvisor-deploy.dispatcherServiceAccountName" -}}
{{- printf "%s-dispatcher" (include "gvisor-deploy.fullname" .) -}}
{{- end -}}

{{/*
Build a Kubernetes label-selector STRING (the form accepted by the apiserver
and `kubectl --selector`) from an equality map plus a list of match-expression
requirements. This is handed to the dispatcher --node-selector, which resolves
the actual target nodes LIVE at run time (so node membership is never frozen
into the Helm release).

Arguments (dict):
  eq    - equality label map           -> "k=v"
  exprs - list of {key, operator, values}:
            Exists       -> "key"
            DoesNotExist -> "!key"
            In           -> "key in (v1,v2)"
            NotIn        -> "key notin (v1,v2)"

Returns the comma-joined selector string (possibly empty, meaning "all nodes").
*/}}
{{- define "gvisor-deploy.nodeLabelSelector" -}}
{{- $parts := list -}}
{{- range $k, $v := (.eq | default dict) -}}
{{- $parts = append $parts (printf "%s=%s" $k $v) -}}
{{- end -}}
{{- range $expr := (.exprs | default list) -}}
{{- $op := $expr.operator -}}
{{- if eq $op "Exists" -}}
{{- $parts = append $parts $expr.key -}}
{{- else if eq $op "DoesNotExist" -}}
{{- $parts = append $parts (printf "!%s" $expr.key) -}}
{{- else if eq $op "In" -}}
{{- $parts = append $parts (printf "%s in (%s)" $expr.key (join "," ($expr.values | default list))) -}}
{{- else if eq $op "NotIn" -}}
{{- $parts = append $parts (printf "%s notin (%s)" $expr.key (join "," ($expr.values | default list))) -}}
{{- else -}}
{{- fail (printf "nodeSelectorExpressions: unsupported operator %q for key %q (use In, NotIn, Exists, DoesNotExist)" $op $expr.key) -}}
{{- end -}}
{{- end -}}
{{- join "," $parts -}}
{{- end -}}

{{/*
Common environment variables for any pod that runs the install script
(DaemonSet or per-node install Job). Emitted at column 0; callers must indent
with `nindent` to the right depth.
*/}}
{{- define "gvisor-deploy.installEnv" -}}
- name: BASE_URL
  value: {{ .Values.binaries.baseUrl | quote }}
- name: BIN_PATH
  value: {{ .Values.binaries.path | quote }}
- name: RUNSC_FILE
  value: {{ .Values.binaries.runsc.fileName | quote }}
- name: RUNSC_SHA
  value: {{ .Values.binaries.runsc.sha512FileName | quote }}
- name: SHIM_FILE
  value: {{ .Values.binaries.shim.fileName | quote }}
- name: SHIM_SHA
  value: {{ .Values.binaries.shim.sha512FileName | quote }}
- name: VERIFY_CHECKSUM
  value: {{ .Values.binaries.verifyChecksum | quote }}
- name: BIN_DIR
  value: {{ .Values.install.binDir | quote }}
- name: CONFIG_PATH
  value: {{ .Values.containerd.configPath | quote }}
- name: BACKUP_SUFFIX
  value: {{ .Values.containerd.backupSuffix | quote }}
- name: RESTART_CONTAINERD
  value: {{ .Values.containerd.restartContainerd | quote }}
- name: RUNTIME_NAME
  value: {{ .Values.containerd.runtimeName | quote }}
{{- if .Values.caBundle.enabled }}
- name: CA_CERT_FILE
  value: {{ printf "%s/%s" (trimSuffix "/" .Values.caBundle.mountPath) .Values.caBundle.key | quote }}
{{- end }}
{{- if .Values.downloadSecret.enabled }}
- name: NEXUS_USERNAME
  valueFrom:
    secretKeyRef:
      name: {{ .Values.downloadSecret.name | quote }}
      key: {{ .Values.downloadSecret.usernameKey | quote }}
- name: NEXUS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.downloadSecret.name | quote }}
      key: {{ .Values.downloadSecret.passwordKey | quote }}
{{- end }}
{{- end -}}

{{/*
Common volumeMounts for any pod that runs the install script.
Emitted at column 0; indent with `nindent` at the call site.
*/}}
{{- define "gvisor-deploy.installVolumeMounts" -}}
- name: host-root
  mountPath: /host
- name: install-scripts
  mountPath: /scripts
{{- if .Values.caBundle.enabled }}
- name: ca-bundle
  mountPath: {{ .Values.caBundle.mountPath | quote }}
  readOnly: true
{{- end }}
{{- end -}}

{{/*
Common volumes backing the install volumeMounts.
Emitted at column 0; indent with `nindent` at the call site.
*/}}
{{- define "gvisor-deploy.installVolumes" -}}
- name: host-root
  hostPath:
    path: /
- name: install-scripts
  configMap:
    name: {{ include "gvisor-deploy.fullname" . }}-install
{{- if .Values.caBundle.enabled }}
- name: ca-bundle
  secret:
    secretName: {{ .Values.caBundle.name | quote }}
    items:
      - key: {{ .Values.caBundle.key | quote }}
        path: {{ .Values.caBundle.key | quote }}
{{- end }}
{{- end -}}

{{/*
Common environment variables for any pod that runs the cleanup script.
Emitted at column 0; indent with `nindent` at the call site.
*/}}
{{- define "gvisor-deploy.cleanupEnv" -}}
- name: BIN_DIR
  value: {{ .Values.install.binDir | quote }}
- name: CONFIG_PATH
  value: {{ .Values.containerd.configPath | quote }}
- name: BACKUP_SUFFIX
  value: {{ .Values.containerd.backupSuffix | quote }}
- name: RUNTIME_NAME
  value: {{ .Values.containerd.runtimeName | quote }}
- name: RUNSC_FILENAME
  value: {{ .Values.binaries.runsc.fileName | quote }}
- name: SHIM_FILENAME
  value: {{ .Values.binaries.shim.fileName | quote }}
{{- end -}}

{{/*
Common volumeMounts for any pod that runs the cleanup script.
Emitted at column 0; indent with `nindent` at the call site.
*/}}
{{- define "gvisor-deploy.cleanupVolumeMounts" -}}
- name: host-root
  mountPath: /host
- name: cleanup-scripts
  mountPath: /scripts
{{- end -}}

{{/*
Common volumes backing the cleanup volumeMounts.
Emitted at column 0; indent with `nindent` at the call site.
*/}}
{{- define "gvisor-deploy.cleanupVolumes" -}}
- name: host-root
  hostPath:
    path: /
- name: cleanup-scripts
  configMap:
    name: {{ include "gvisor-deploy.fullname" . }}-cleanup
    defaultMode: 0755
{{- end -}}

{{/*
Per-node staged Job manifest (deploymentMode: job), embedded verbatim into the
job-templates ConfigMap. The dispatcher clones this once per target node,
injecting metadata.name (__JOB_NAME__), metadata.namespace (__NAMESPACE__) and
spec.template.spec.nodeName (__NODE_NAME__) via sed, so the template itself
carries NO node identity and NO Helm hook annotations.

Arguments (dict):
  root  - top-level context (.)
  stage - "install" | "cleanup"

Emitted at column 0 (a standalone Job document); embed with `indent` at the
call site under a ConfigMap data key.
*/}}
{{- define "gvisor-deploy.perNodeJob" -}}
{{- $root := .root -}}
{{- $stage := .stage -}}
apiVersion: batch/v1
kind: Job
metadata:
  name: __JOB_NAME__
  namespace: __NAMESPACE__
  labels:
    app.kubernetes.io/name: {{ include "gvisor-deploy.name" $root }}
    app.kubernetes.io/instance: {{ $root.Release.Name }}
    gvisor-deploy/stage: {{ $stage }}
spec:
  backoffLimit: {{ $root.Values.job.backoffLimit }}
  ttlSecondsAfterFinished: {{ $root.Values.job.ttlSecondsAfterFinished }}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: {{ include "gvisor-deploy.name" $root }}
        app.kubernetes.io/instance: {{ $root.Release.Name }}
        gvisor-deploy/stage: {{ $stage }}
    spec:
      nodeName: __NODE_NAME__
      serviceAccountName: {{ include "gvisor-deploy.serviceAccountName" $root }}
      hostPID: true
      restartPolicy: Never
{{- with $root.Values.imagePullSecrets }}
      imagePullSecrets:
{{- toYaml . | nindent 8 }}
{{- end }}
{{- with $root.Values.tolerations }}
      tolerations:
{{- toYaml . | nindent 8 }}
{{- end }}
{{- with $root.Values.priorityClassName }}
      priorityClassName: {{ . }}
{{- end }}
      containers:
        - name: {{ $stage }}
          image: {{ include "gvisor-deploy.image" $root }}
          imagePullPolicy: {{ $root.Values.image.pullPolicy }}
{{- if eq $stage "install" }}
          command: ["/bin/sh", "/scripts/install.sh"]
{{- else }}
          command: ["/bin/sh", "/scripts/cleanup.sh"]
{{- end }}
          securityContext:
            privileged: true
            runAsUser: 0
          env:
{{- if eq $stage "install" }}
            - name: EXIT_AFTER_INSTALL
              value: "true"
            - name: NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
{{- include "gvisor-deploy.installEnv" $root | nindent 12 }}
{{- else }}
{{- include "gvisor-deploy.cleanupEnv" $root | nindent 12 }}
{{- end }}
{{- with $root.Values.resources }}
          resources:
{{- toYaml . | nindent 12 }}
{{- end }}
          volumeMounts:
{{- if eq $stage "install" }}
{{- include "gvisor-deploy.installVolumeMounts" $root | nindent 12 }}
{{- else }}
{{- include "gvisor-deploy.cleanupVolumeMounts" $root | nindent 12 }}
{{- end }}
      volumes:
{{- if eq $stage "install" }}
{{- include "gvisor-deploy.installVolumes" $root | nindent 8 }}
{{- else }}
{{- include "gvisor-deploy.cleanupVolumes" $root | nindent 8 }}
{{- end }}
{{- end -}}
