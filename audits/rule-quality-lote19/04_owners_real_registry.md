# Lote 19 — Registro real de owners y brecha L13/L17

**Estado:** OBJETIVO para catálogo/contadores, REQUIERE_REVISION_SEMANTICA para equivalencia y controles de adopción. Fuente: SELECT O1–O4 en Supabase `mhwmirqcgxxukpctffuv`. No crear, actualizar ni activar.

## Hallazgo operativo
- `lf_ops.perfiles` tiene **8** roles de aplicación (6 B2B CANDIDATO, 2 B2C VIGENTE); no son automáticamente owners de calidad por familia.
- `lf_ops.permisos`: **45**; `lf_ops.perfiles_permisos`: **129** asignaciones de permiso, todas con estado CANDIDATO en la lectura. **OBJETIVO O2.**
- Asignaciones explícitas a usuarios actuales: `empresa_usuarios_perfiles`=0, `empresa_usuarios_permisos`=0, `b2b_user_company_profiles`=0, `b2b_user_company_permissions`=0. **No significa que no haya usuarios externos; solo que esas tablas están vacías.**
- Perfiles de agentes LF: **11** activos tipo PERFIL en `v_lf_fuente_operativa` y **10** descriptores en `lf_profile_selection_registry_v1`; son fuentes diferentes, no sumarlas.
- `programacion.perfiles_calidad` tiene **2** perfiles de evaluación, no owners de proyectos.
- SALY: `saly.proyecto` tiene **1** proyecto (columna `codigo`, sin `owner_profile_code`); `saly.reglas` tiene **14** reglas.

## Objetos equivalentes al modelo de L13/L17
L13 define en PG18 sandbox `projects(project_code,owner_profile_code,owner_name,created_by,review_interval_days)`, `actors`, `families`, `category_family_map` y control anti-SUPER_ADMIN. Fuente repositorio: `docs/rule-quality-lote13/03_design_generic.md` (blob Git SHA-1 `26a06c7c64ab40368f4da22d478298676bdcbfcd`).

L17 plantea un adaptador JWT firmado y mapeo `project_code+sub+role` a `actor_code/profile_code`. Fuente: `docs/rule-quality-lote17/03_design_results_limits.md` (blob Git SHA-1 `6c873b32f9bd7004b82f80c64e40c297cdb1a3af`). **Ambos son sandbox; no autoridades Supabase desplegadas.**

### Objetos exactos consultados (SELECT O3; OBJETIVO)
| schema | tabla | existe |
|---|---|---|
| rule_quality_l13 | actors | NO |
| rule_quality_l13 | category_family_map | NO |
| lf_ops | empresa_usuarios_perfiles | SI |
| rule_quality_l13 | families | NO |
| rule_quality_l13 | l17_actor_subjects | NO |
| public | lf_profile_selection_registry_v1 | SI |
| lf_ops | perfiles_permisos | SI |
| lf_ops | perfiles | SI |
| saly | perfiles | NO |
| rule_quality_l13 | projects | NO |
| saly | proyecto | SI |


**Conclusión REQUIERE_REVISION_SEMANTICA:** la conjunción confiable `project_code + owner_profile_code + actor` **no está acreditada en las tablas inspeccionadas**. `saly.proyecto.codigo` identifica proyecto; `lf_ops.perfiles.profile_code` identifica rol de aplicación; no hay FK, contrato y mapa de autorización que permita tratarlos como el owner gobernado del modelo PG18. `programacion.input_family_assessments.family_code` clasifica evaluaciones, no autoriza propietarios. `public.lf_strategy_snapshots.project_code` no constituye registro `projects`.

## Directorio de perfiles existentes — SELECT O4
| fuente | codigo | estado | alcance |
|---|---|---|---|
| LF_AGENT_REGISTRY | ACT-0051 | CURRENT | GITHUB_SKILL |
| LF_CANONICAL_ASSET | ACT-0051 | READ_ONLY | Cristhian |
| LF_APP_ROLE | B2B_ADMIN_EMPRESA | CANDIDATO | B2B |
| LF_APP_ROLE | B2B_ADMIN_LF | CANDIDATO | GLOBAL |
| LF_APP_ROLE | B2B_APROBADOR | CANDIDATO | B2B |
| LF_APP_ROLE | B2B_LECTOR_AUDITOR | CANDIDATO | B2B |
| LF_APP_ROLE | B2B_OPERADOR_INTEGRAL | CANDIDATO | B2B |
| LF_APP_ROLE | B2B_OPERADOR | CANDIDATO | B2B |
| LF_APP_ROLE | CLIENTE_ANONIMO | VIGENTE | B2C |
| LF_APP_ROLE | CLIENTE_AUTENTICADO | VIGENTE | B2C |
| LF_AGENT_REGISTRY | PERFIL-CUSTOMER-FINANCIAL-UX-DECISIONING | CURRENT | GITHUB_SKILL |
| LF_CANONICAL_ASSET | PERFIL-CUSTOMER-FINANCIAL-UX-DECISIONING | READ_ONLY | OWNER_NAME_NULL |
| LF_AGENT_REGISTRY | PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531 | CURRENT | LF_ACTIVOS_RAW_PAYLOAD |
| LF_CANONICAL_ASSET | PERFIL-CX-TRUST-EXPERIENCE-ARCHITECT-LF-20260531 | READ_ONLY | Cristhian |
| LF_AGENT_REGISTRY | PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF | CURRENT | GITHUB_SKILL |
| LF_CANONICAL_ASSET | PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF | READ_ONLY | OWNER_NAME_NULL |
| LF_AGENT_REGISTRY | PERFIL-GAMIFICATION-SYSTEM-ARCHITECT | CURRENT | GITHUB_SKILL |
| LF_CANONICAL_ASSET | PERFIL-GAMIFICATION-SYSTEM-ARCHITECT | READ_ONLY | OWNER_NAME_NULL |
| LF_AGENT_REGISTRY | PERFIL-PRODUCT-DIRECTOR-LF | CURRENT | GITHUB_SKILL |
| LF_CANONICAL_ASSET | PERFIL-PRODUCT-DIRECTOR-LF | READ_ONLY | OWNER_NAME_NULL |
| LF_AGENT_REGISTRY | PERFIL-QUALITY-PACK | CURRENT | GITHUB_SKILL |
| LF_CANONICAL_ASSET | PERFIL-QUALITY-PACK | READ_ONLY | OWNER_NAME_NULL |
| LF_CANONICAL_ASSET | PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF-V06-CANDIDATE | READ_ONLY | OWNER_NAME_NULL |
| LF_AGENT_REGISTRY | PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF | CURRENT | GITHUB_SKILL |
| LF_CANONICAL_ASSET | PERFIL-SYSTEMIC-ROOT-CAUSE-REPAIR-LF | READ_ONLY | OWNER_NAME_NULL |
| LF_AGENT_REGISTRY | PERFIL-UI-ARCHITECT | CURRENT | GITHUB_SKILL |
| LF_CANONICAL_ASSET | PERFIL-UI-ARCHITECT | READ_ONLY | OWNER_NAME_NULL |
| LF_AGENT_REGISTRY | PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531 | CURRENT | LF_ACTIVOS_RAW_PAYLOAD |
| LF_CANONICAL_ASSET | PERFIL-UX-PRODUCT-EXPERIENCE-ARCHITECT-LF-20260531 | READ_ONLY | Cristhian |
| PROGRAMACION_QUALITY | QC_BASE_V02 | defined | QUALITY_PROFILE |
| PROGRAMACION_QUALITY | QC_LOGIN_REFERENCE_V02 | defined | QUALITY_PROFILE |
| SALY_PROJECT | SALY-001 | ACTIVO | IDEACION |


## SQL, hashes y límites
- **O1 OBJETIVO**: 261 filas; SHA-256 JSONB `9f4e2cf2b772f61e3e661a3412f1b0ad034ecfa6bc8a409325fe6405ac181782`.
- **O2 OBJETIVO**: 13 filas; SHA-256 JSONB `0a39861a2b631a91e10fc1033bbf780c7d244f75634ff4a5d8780bb77797b43d`.
- **O3 OBJETIVO**: 11 filas; SHA-256 JSONB `43d668a83116b87366bdb76f0e04d03dad69bf6ce47928ba04c631acff7223fb`.
- **O4 OBJETIVO**: 32 filas; SHA-256 JSONB `f124e594c0208ccc99b2e193f0ca657a7663e4e1c377b87dc0480670be5f2480`.

Consultas íntegramente reproducibles y normalización del SHA en `05_owners_select.sql`. La ausencia del esquema `rule_quality_l13` y de tablas `projects/actors/category_family_map` en este catálogo **no demuestra ausencia de un servicio externo de identidad**. No se consultaron sistemas externos ni se ejecutó PG18.

## Brecha para decisión humana
1. Identificar owner de negocio (no SUPER_ADMIN), perfil de calidad y personas por proyecto LF y SALY; comprobar que sus fuentes existen y están aprobadas.
2. Definir mapping canónico `project_code↔owner_profile_code↔actor/sub` con aislamiento por proyecto y autenticación confiable (no parámetro libre, ni usar `session_user` como identidad final).
3. Definir familias y categorías por proyecto sin renombrar masivamente las 578 reglas ni 14 SALY.
4. Probar P0/P1 negativos y positivos en banco independiente; obtener recibos de trazabilidad, firmas, readback y rollback ANTES de solicitar instalación gobernada.
