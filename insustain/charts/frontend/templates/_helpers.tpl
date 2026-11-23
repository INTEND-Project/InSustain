{{/*
Expand the name of the chart.
*/}}
{{- define "frontend.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "frontend.fullname" -}}
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
{{- define "frontend.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "frontend.labels" -}}
helm.sh/chart: {{ include "frontend.chart" . }}
{{ include "frontend.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "frontend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "frontend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "frontend.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "frontend.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Validate an optional immutable image digest. Empty means "use the tag form";
anything else must be exactly sha256:<64 lowercase hex> (no whitespace or
newlines), otherwise the render fails rather than emit an unpinned image.
*/}}
{{- define "frontend.imageDigest" -}}
{{- $digest := .Values.image.digest | default "" -}}
{{- if and $digest (not (regexMatch "\\Asha256:[0-9a-f]{64}\\z" $digest)) -}}
{{- fail (printf "frontend.image.digest must be sha256:<64 lowercase hex>, got %q" $digest) -}}
{{- end -}}
{{- $digest -}}
{{- end -}}

{{- define "frontend.fullImage" -}}
{{- $repo := .Values.global.image.repository | default "localhost:5000" -}}
{{- $prefix := .Values.global.image.prefix | default "intend/insustain-"}}
{{- $tag := (.Values.global.image.tag | default .Values.image.tag | default $.Chart.AppVersion) -}}
{{- $digest := include "frontend.imageDigest" . -}}
{{- if $digest -}}
{{- printf "%s/%sfrontend@%s" $repo $prefix $digest -}}
{{- else -}}
{{- printf "%s/%sfrontend:%s" $repo $prefix $tag -}}
{{- end -}}
{{- end -}}
