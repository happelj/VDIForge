{{/*
Expand the chart name.
*/}}
{{- define "vdiforge.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a release-qualified name.
*/}}
{{- define "vdiforge.fullname" -}}
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

{{- define "vdiforge.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "vdiforge.labels" -}}
helm.sh/chart: {{ include "vdiforge.chart" . }}
app.kubernetes.io/name: {{ include "vdiforge.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/part-of: vdiforge
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.global.labels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "vdiforge.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vdiforge.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: vdiforge
{{- end -}}

{{- define "vdiforge.namespace.system" -}}
{{- required "namespaces.system is required" .Values.namespaces.system -}}
{{- end -}}

{{- define "vdiforge.namespace.desktops" -}}
{{- required "namespaces.desktops is required" .Values.namespaces.desktops -}}
{{- end -}}

{{- define "vdiforge.namespace.identity" -}}
{{- required "namespaces.identity is required" .Values.namespaces.identity -}}
{{- end -}}

{{- define "vdiforge.serviceAccount.apiName" -}}
{{- required "serviceAccounts.api.name is required" .Values.serviceAccounts.api.name -}}
{{- end -}}

{{- define "vdiforge.serviceAccount.provisionerName" -}}
{{- required "serviceAccounts.provisioner.name is required" .Values.serviceAccounts.provisioner.name -}}
{{- end -}}

{{- define "vdiforge.keycloak.name" -}}
{{- required "keycloak.name is required" .Values.keycloak.name -}}
{{- end -}}

{{- define "vdiforge.keycloak.postgresqlName" -}}
{{- required "keycloak.postgresql.name is required" .Values.keycloak.postgresql.name -}}
{{- end -}}

{{- define "vdiforge.keycloak.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vdiforge.keycloak.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: identity
app.kubernetes.io/part-of: vdiforge
{{- end -}}

{{- define "vdiforge.keycloak.labels" -}}
helm.sh/chart: {{ include "vdiforge.chart" . }}
app.kubernetes.io/name: {{ include "vdiforge.keycloak.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/component: identity
app.kubernetes.io/part-of: vdiforge
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.global.labels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "vdiforge.keycloak.postgresqlSelectorLabels" -}}
app.kubernetes.io/name: {{ include "vdiforge.keycloak.postgresqlName" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: identity-database
app.kubernetes.io/part-of: vdiforge
{{- end -}}

{{- define "vdiforge.keycloak.postgresqlLabels" -}}
helm.sh/chart: {{ include "vdiforge.chart" . }}
app.kubernetes.io/name: {{ include "vdiforge.keycloak.postgresqlName" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/component: identity-database
app.kubernetes.io/part-of: vdiforge
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.global.labels }}
{{ toYaml . }}
{{- end }}
{{- end -}}
