# roles_matrix.md

Owner: SKILL_EXTRACCION_FUENTES_DIGITALES_LF
Adapter: ADAPTER_WEB_ARTICLE_CAPTURE_LF
Estado: CANDIDATO_READ_ONLY

## Roles permitidos

viewer: READ_ONLY_RESULT
extractor_operator: DRY_RUN, READ_ONLY_RESULT
register_operator: DRY_RUN, READ_ONLY_RESULT, FULL_EXTRACTION_REGISTER_SANDBOX_ONLY, ADDENDUM_ONLY
admin_sandbox: DRY_RUN, READ_ONLY_RESULT, FULL_EXTRACTION_REGISTER_SANDBOX_ONLY, ADDENDUM_ONLY

## Bloqueos globales

produccion: false
n8n: false
homologacion: false
insight_automatico: false
alert_automatico: false
kb_final: false
