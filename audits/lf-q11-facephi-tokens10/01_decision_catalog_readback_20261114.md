# LF — decisión documental Q11 FACEPHI y 10 tokens B2B (2026-11-14, 04:52 Lima)
Estado: DECISIÓN DOCUMENTAL DEL DUEÑO, identidad no certificada; cambio propuesto por ruta gobernada ACT-0001 → ACTUALIZACION_DB_LF → PR → ready-to-merge → LF Migration Merge Train.
EKB operativa leída: INPUT GOVERNANCE LF — INSTRUCCIONES OPERATIVAS V1.4. Fuentes de autoridad: SELECT Supabase + repositorio exacto, no documentos antiguos.

## Descubrimiento
Los 10 tokens a los que corresponde el único conjunto de diez candidatos en el catálogo son **spacing_tokens de LF_DS_V1**. Todos tienen token_name registrado actualmente, por lo que su nombre se decide como **PRESERVAR el nombre ya vigente en catálogo como identidad candidata** y no crear alias/duplicados. Ni valor_px ni estado CANDIDATO se promueven. Invariante exacto 10/10 en migración.

| spacing_token_id | Nombre elegido (existente, preservado) | Patrón de nomenclatura LF existente |
|---:|---|---|
| 38 | `b2b_filter_drawer_width` | prefijo dominio + objeto + medida; `home_hero_card_width` |
| 37 | `b2b_modal_max_width` | objeto + límite de medida; `desktop_content_max_width` |
| 32 | `b2b_page_padding_desktop` | objeto + propiedad + breakpoint; `home_header_desktop_height` |
| 34 | `b2b_page_padding_mobile` | objeto + propiedad + breakpoint; `home_header_desktop_height` |
| 33 | `b2b_page_padding_tablet` | objeto + propiedad + breakpoint; `home_header_desktop_height` |
| 30 | `b2b_sidebar_width_collapsed` | objeto + propiedad + estado; `green_action_disabled` |
| 29 | `b2b_sidebar_width_expanded` | objeto + propiedad + estado; `green_action_hover` |
| 36 | `b2b_table_row_height` | objeto + parte + medida; `home_hero_card_height` |
| 31 | `b2b_topbar_height` | objeto + medida; `home_header_desktop_height` |
| 35 | `b2b_touch_target_min` | objeto + límite inferior; `desktop_content_max_width` |

## Proveedor FACEPHI — Q11
- Proveedor elegido: `FACEPHI`, tipo `IDENTITY_VERIFICATION_IDV_NOT_LOGIN_IDP`; nunca sustituye OIDC/JWT, Google Workspace ni Brevo.
- Estado inicial `enabled=false`, `integration_status=NOT_IMPLEMENTED_NO_EXTERNAL_CALLS`, sin credenciales ni SDK, ni rutas nuevas, ni llamadas externas; `SEC-LF-IDV-FACEPHI-OPTIONAL` central candidate.
- Se evalúa activar solo cuando una empresa B2B declare requerir IDV para ir a producción, **con decisión gobernada posterior, seguridad y QA**. La decisión de hoy no enciende el proveedor.
- `SEC-B2B-MFA-RECOVERY` y `B2B-RULE-AUTH-020`: rama FACEPHI condicionada a `enabled=true`; soporte/DNI manual permanece una rama separada y gobernada. Login normal/MFA no depende de FACEPHI.
- `REG_IDV_PROGRESSIVE_001` (CANDIDATO), `REG_CLIENT_RECOVERY_IDV_STEPUP_001`, `REG_CLIENT_RECOVERY_IDV_OUTCOME_001`, `REG_CLIENT_RECOVERY_REBIND_ATOMIC_001` (VIGENTE) referencian la política única y bloquean **solo el camino IDV** cuando disabled. NO inventar VERIFIED, no reasignar cuentas, no bypass; conservar OTP anterior si autorizado.
- La migración NO implementa enforcement técnico de runtime; se requieren verificaciones/QA antes de usar IDV. Las reglas VIGENTE alteradas se protegen con preimagen exacta y revisión de efectos.
- Procedencia documental: `DOC-OWNER-20261114-0452-IDV-FACEPHI`, `identity_verified=false`; `parameter_provenance` LF_PROVISIONAL_DEFAULT para no reclamar firma criptográfica del dueño.
- 2 EKB preventivas nuevas, sin gate adicional; 10 filas de tokens verificadas pero **no modificadas**.
- Todos los efectos DML solo se ejecutan si el PR atraviesa la ruta oficial; laboratorio PG17.6/18.7 con ROLLBACK y readback.

## Pruebas / bloqueos
El paso de migración exige SHA original por fila para 5 reglas y 2 políticas, conserva estado de reglas, exige 10 tokens ya registrados y política FACEPHI ausente; inserta 1 política CANDIDATO + 2 EKB. No permitir merge si la rama ha derivado, una verificación CI está roja, no hay autoridad, o un consumidor de reglas VIGENTE falla.
