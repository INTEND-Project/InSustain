{{/*
Expand the name of the chart.
*/}}
{{- define "postgresql.fullname" -}}
{{ include "postgresql.name" . }}
{{- end -}}

{{- define "postgresql.name" -}}
{{ .Chart.Name }}
{{- end -}}
