{{/*
Expand the name of the chart.
*/}}
{{- define "backend.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "backend.fullname" -}}
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
{{- define "backend.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "backend.labels" -}}
helm.sh/chart: {{ include "backend.chart" . }}
{{ include "backend.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "backend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "backend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "backend.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "backend.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the name of the rbac account to use
*/}}
{{- define "backend.clusterrolename" -}}
{{- if .Values.rbac.create }}
{{- default (include "backend.fullname" .) .Values.rbac.name }}
{{- else }}
{{- default "default" .Values.rbac.name }}
{{- end }}
{{- end }}

{{/*
Validate an optional immutable image digest. Empty means "use the tag form";
anything else must be exactly sha256:<64 lowercase hex> (no whitespace or
newlines), otherwise the render fails rather than emit an unpinned image.
*/}}
{{- define "backend.imageDigest" -}}
{{- $digest := .Values.image.digest | default "" -}}
{{- if and $digest (not (regexMatch "\\Asha256:[0-9a-f]{64}\\z" $digest)) -}}
{{- fail (printf "backend.image.digest must be sha256:<64 lowercase hex>, got %q" $digest) -}}
{{- end -}}
{{- $digest -}}
{{- end -}}

{{- define "mychart.fullImage" -}}
{{- $repo := .Values.global.image.repository | default "localhost:5000" -}}
{{- $prefix := .Values.global.image.prefix | default "intend/insustain-"}}
{{- $tag := (.Values.global.image.tag | default .Values.image.tag | default $.Chart.AppVersion) -}}
{{- $digest := include "backend.imageDigest" . -}}
{{- if $digest -}}
{{- printf "%s/%sbackend@%s" $repo $prefix $digest -}}
{{- else -}}
{{- printf "%s/%sbackend:%s" $repo $prefix $tag -}}
{{- end -}}
{{- end -}}

