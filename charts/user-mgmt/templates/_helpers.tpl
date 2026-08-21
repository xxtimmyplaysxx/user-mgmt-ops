{{- define "user-mgmt.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "user-mgmt.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name (include "user-mgmt.name" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "user-mgmt.labels" -}}
app.kubernetes.io/name: {{ include "user-mgmt.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: user-mgmt
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end }}

{{- define "user-mgmt.selectorLabels" -}}
app.kubernetes.io/name: {{ include "user-mgmt.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "user-mgmt.secretName" -}}
{{- default (printf "%s-secret" (include "user-mgmt.fullname" .)) .Values.secret.existingSecret }}
{{- end }}
