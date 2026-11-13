# SALY Owner/Operation registration — official governed route & receipt template

## Owner decision (documentary, non-Auth)
- Fuente: comunicación reportada por el dueño en el chat del arquitecto, **2026-11-13 12:53 America/Lima**.
- Literal exacto: **"Si me designo"**.
- Interpretación expresamente aprobada: Cristhian Luján owner documental de SALY y creación/homologación de un perfil canónico SALY propio, no hereda `PERFIL-PRODUCT-DIRECTOR-LF`.
- `identity_mode=UNVERIFIED_CHAT_DECLARATION`, `identity_verified=false`, `production_authorized=false`.
- Fuente JSON exacta: `docs/input-governance/b07_parent_child_candidate/10_owner_saly_decision_20261113.json`. SHA-256 UTF-8 del JSON canónico **107332ebbae4295dc76179bd5619856cb61807b91a856c080b12e1942018fb0f**. Esto NO es firma humana ni prueba Supabase Auth.
- `authority_receipt_sha256` del owner en SQL será SHA-256 de la representación `jsonb::text` del mismo registro (la serialización PostgreSQL es distinta de JSON canónico compactado); se verifica en el readback y no se copia el recibo LF.

## Ruta oficial sin escritor paralelo
1. `ACT-0001 → PROFILE_CREATE → CREACION_PERFIL_LF`: perfil canónico SALY `PERFIL-PRODUCT-DIRECTOR-SALY`. Pack candidato independiente: `profiles/saly_product_director/`. Validar 23/23 archivos de plantilla, contrato, esquema/juez/evals, creación nativa con RUN `COMPLETED`, readback `public.lf_activos` y `created_by_execution_id` de la **misma ejecución**. Solo `CANDIDATO/READ_ONLY/NO_HABILITADO`. **No INSERT manual** en `lf_activos` desde el Train SALY.
2. **Train de alta SALY separado de #3818**, por `ACT-0001 → ACTUALIZACION_DB_LF → lf-migration-merge-train`, archivo `supabase/migrations/20261113190500_lf_ig_b07_saly_operation_owner_register_v1.sql`. El SQL falla con `B07_SALY_PROFILE_NATIVE_CREATION_RECEIPT_REQUIRED` si paso 1 no tiene recibo. Exige prueba de provenance OIDC, PR #3832, manifest exacto, STEP preflight PASS_CLEAN, un solo RUN real de Train.
3. En un único `BEGIN/COMMIT`, `public.fn_lf_operation_reserve_execution_v1` crea bootstrap oficial de `ACTUALIZACION_REGLA_SALY`, luego **solo el Train oficial** registra operación `SANDBOX_ACTIVE/OP_CANDIDATE`, owner SALY `TEMP_DOCUMENTARY_ACTIVE/UNVERIFIED_CHAT_DECLARATION` con UUID **interno distinto de LF y no de Auth**, SHA documental propio y source execution real; metadata Router `SALY_RULE_UPDATE` **CANDIDATO_READ_ONLY / write_allowed=false**, modo `NO_WRITE`, `lf_profile_write_authority_v1` `PROPOSED`.
4. Validar readback `lf_operation_registry` unido a RUN bootstrap; `lf_ig_project_owner_v2` unido a Train; `lf_activos` perfil SALY creado nativamente; Router deshabilitado; mode `allowed=false/write_allowed=false`; grants sin apertura; 0 RUN históricos alterados. Status productivo sigue NO-GO.
5. **Integración posterior**: #3818 B07 mantiene preflight fail-closed y solo acepta el registro SALY cuando efectivamente existe. Aunque su preflight pase, no equivale a que Router o decisión V2 SALY estén habilitados; la función `lf_ig_rule_owner_decide_v2` actual tiene controles LF, y cualquier generalización para SALY necesita revisión separada y aprobación, sin un escritor paralelo.

## Gate de admisión de este PR
Este PR #3832 queda **DRAFT** hasta (a) perfil nativo creado, (b) CI incluido R17/PASE/Merge Gate en HEAD exacto, (c) guardas completos, (d) recibo de autorización del Train SALY cuando proceda. NO etiquetar `ready-to-merge` mientras el perfil nativo no exista. Independientemente, #3818 requiere OK específico del dueño para **DDL de tablas hija**.

## Recibos, inicialmente vacíos
| Paso | Evidencia | Estado |
|---|---|---|
| Owner chat | JSON `10_owner_saly_decision_20261113.json` y SHA | Documental, no Auth |
| Perfil nativo `CREACION_PERFIL_LF` | `execution_id`, 40 pasos según catálogo actual, readback `lf_activos` | PENDIENTE |
| Alta SALY Train | `train_execution_id`, `train_run_id`, HEAD, migration path, snapshot | PENDIENTE |
| Operación `ACTUALIZACION_REGLA_SALY` | source bootstrap real y readback de categoría | PENDIENTE |
| Owner SALY | `owner_sub` opaco interno, `authority_receipt_sha256` SHA PostgreSQL, source Train | PENDIENTE |
| Router+bindings | SALY_RULE_UPDATE candidato, NO_WRITE, perfil PROPOSED | PENDIENTE |
| Integración con #3818 | prueba preflight PRE fail / POST PASS en aislamiento, CI HEAD exacto | PENDIENTE |
| B07 Train | OK DDL explícito, backup/restore, readback post COMMIT | RETENIDO |

## División PR #3835 vs PR #3832
**PR #3835** contiene el pack candidato del perfil y la solicitud nativa fail-closed. **PR #3832** contiene solamente decisión SALY, registro futuro operación/owner/Router/bindings y pruebas de la migración. Ninguno acredita el RUN de `CREACION_PERFIL_LF`. El paso de Gate2 Issue/OIDC para `EJECUCION_PERFIL_LF` no sustituye al creador de perfil; actual caller de creación limitado a Customer con `production_authorized=true`, por lo que se exige corrección segura y gate de runtime antes del alta nativa SALY.
