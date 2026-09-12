# web_article_capture — Adapter hijo

Owner: SKILL_EXTRACCION_FUENTES_DIGITALES_LF
Adapter: ADAPTER_WEB_ARTICLE_CAPTURE_LF
Estado: CANDIDATO_READ_ONLY

## Orden de lectura

- ADAPTER.md
- RUNBOOK.md
- permissions/roles_matrix.md
- schemas/db_field_mapping.yaml
- schemas/extraction_fields.schema.yaml
- fixtures/antiduplicate_hashes.yaml
- db/ddl_extension.sql
- db/log_config.sql
- examples/good_reevalua.yaml
- examples/bad_kambista.yaml

## Interacción

- command_contract.yaml llama a este adapter.
- roles_matrix.md controla permisos.
- schemas definen campos y mapeo.
- fixtures soportan anti-duplicado.
- examples soportan pruebas documentales.
- db contiene referencias controladas no ejecutables automáticamente.

## Límites

No producción. No VALIDATED. No homologación. No insight. No alert. No n8n.
