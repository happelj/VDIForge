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

{{- define "vdiforge.namespace.remoteAccess" -}}
{{- required "namespaces.remoteAccess is required" .Values.namespaces.remoteAccess -}}
{{- end -}}

{{- define "vdiforge.serviceAccount.apiName" -}}
{{- required "serviceAccounts.api.name is required" .Values.serviceAccounts.api.name -}}
{{- end -}}

{{- define "vdiforge.serviceAccount.frontendName" -}}
{{- required "serviceAccounts.frontend.name is required" .Values.serviceAccounts.frontend.name -}}
{{- end -}}

{{- define "vdiforge.serviceAccount.provisionerName" -}}
{{- required "serviceAccounts.provisioner.name is required" .Values.serviceAccounts.provisioner.name -}}
{{- end -}}

{{- define "vdiforge.serviceAccount.databaseName" -}}
{{- required "serviceAccounts.database.name is required" .Values.serviceAccounts.database.name -}}
{{- end -}}

{{- define "vdiforge.api.name" -}}
{{- default "vdiforge-api" .Values.api.service.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "vdiforge.api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vdiforge.api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: api
app.kubernetes.io/part-of: vdiforge
{{- end -}}

{{- define "vdiforge.api.labels" -}}
helm.sh/chart: {{ include "vdiforge.chart" . }}
app.kubernetes.io/name: {{ include "vdiforge.api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/component: api
app.kubernetes.io/part-of: vdiforge
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.global.labels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "vdiforge.frontend.name" -}}
{{- required "frontend.name is required" .Values.frontend.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "vdiforge.frontend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vdiforge.frontend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: frontend
app.kubernetes.io/part-of: vdiforge
{{- end -}}

{{- define "vdiforge.frontend.labels" -}}
helm.sh/chart: {{ include "vdiforge.chart" . }}
app.kubernetes.io/name: {{ include "vdiforge.frontend.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/component: frontend
app.kubernetes.io/part-of: vdiforge
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.global.labels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "vdiforge.provisioner.name" -}}
{{- default "vdiforge-provisioner" .Values.provisioner.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "vdiforge.provisioner.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vdiforge.provisioner.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: provisioner
app.kubernetes.io/part-of: vdiforge
{{- end -}}

{{- define "vdiforge.provisioner.labels" -}}
helm.sh/chart: {{ include "vdiforge.chart" . }}
app.kubernetes.io/name: {{ include "vdiforge.provisioner.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/component: provisioner
app.kubernetes.io/part-of: vdiforge
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.global.labels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "vdiforge.appDatabase.name" -}}
{{- required "applicationDatabase.name is required" .Values.applicationDatabase.name -}}
{{- end -}}

{{- define "vdiforge.appDatabase.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vdiforge.appDatabase.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: app-database
app.kubernetes.io/part-of: vdiforge
{{- end -}}

{{- define "vdiforge.appDatabase.labels" -}}
helm.sh/chart: {{ include "vdiforge.chart" . }}
app.kubernetes.io/name: {{ include "vdiforge.appDatabase.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/component: app-database
app.kubernetes.io/part-of: vdiforge
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.global.labels }}
{{ toYaml . }}
{{- end }}
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

{{- define "vdiforge.keycloak.postgresqlVolumeClaimTemplateLabels" -}}
{{- if .Values.keycloak.postgresql.volumeClaimTemplateLabels }}
{{ toYaml .Values.keycloak.postgresql.volumeClaimTemplateLabels }}
{{- else }}
{{ include "vdiforge.keycloak.postgresqlLabels" . }}
{{- end }}
{{- end -}}

{{- define "vdiforge.guacamole.name" -}}
{{- required "guacamole.name is required" .Values.guacamole.name -}}
{{- end -}}

{{- define "vdiforge.guacamole.guacdName" -}}
{{- required "guacamole.guacd.name is required" .Values.guacamole.guacd.name -}}
{{- end -}}

{{- define "vdiforge.guacamole.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vdiforge.guacamole.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: remote-access
app.kubernetes.io/part-of: vdiforge
{{- end -}}

{{- define "vdiforge.guacamole.labels" -}}
helm.sh/chart: {{ include "vdiforge.chart" . }}
app.kubernetes.io/name: {{ include "vdiforge.guacamole.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/component: remote-access
app.kubernetes.io/part-of: vdiforge
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.global.labels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "vdiforge.guacamole.guacdSelectorLabels" -}}
app.kubernetes.io/name: {{ include "vdiforge.guacamole.guacdName" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: guacd
app.kubernetes.io/part-of: vdiforge
{{- end -}}

{{- define "vdiforge.guacamole.guacdLabels" -}}
helm.sh/chart: {{ include "vdiforge.chart" . }}
app.kubernetes.io/name: {{ include "vdiforge.guacamole.guacdName" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/component: guacd
app.kubernetes.io/part-of: vdiforge
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.global.labels }}
{{ toYaml . }}
{{- end }}
{{- end -}}
