# #3845 — Selector dinámico de skills desde la operación (DRAFT · NO-GO)

## Disparo único del dueño
> Ejecuta EJECUCION_PERFIL_LF para <solicitud + contexto>

## Evidencia SELECT (13-nov-2026 · Supabase solo lectura)
- **Corrección expresa de diagnóstico:** `public.lf_activo_relaciones` es un grafo documental de activos; su ausencia de vínculos PERFIL→SKILL **NO** prueba falta de un selector de skills. El catálogo/invocador vigentes son `public.lf_skill_catalog_v1` (8 registros) y `public.lf_skill_invocation_v1` (14 invocaciones, 3 RUN padre). IG NO está registrado en el catálogo.
- Patrón canónico de selección del perfil: `public.lf_profile_selection_registry_v1` (descriptor JSONB, `LF_PROFILE_SELECTION_DESCRIPTOR_V1`, `CURRENT/STALE_SOURCE_CHANGED`) + `public.lf_profile_selector_policy_v1` (perfil, channels, entry_policy). Se reutiliza el **patrón**, no se crea Router de skills.
- `public.lf_operation_steps` + `public.lf_operation_step_contracts`: 11 pasos `EJECUCION_PERFIL_LF` `ACTIVE_ENFORCEMENT`. El canal verificado vive en `manifest.router_profile_handoff.channel`, faltante en algunos RUN históricos: esos casos se bloquean, nunca se infiere canal.
- `public.lf_skill_invoke_v1` ya impone perfil y operación autorizada, READY, inputs obligatorios, handler y replay; escribe la tabla oficial de invocación. No reemplazarlo.

## SQL candidato (sin DDL/DML vivo)
`supabase/migrations/20261114020000_lf_profile_skill_dynamic_selection_v1.sql`:
1. `lf_skill_selector_policy_v1`: asociación perfil+skill+operación requerida, canales, efectos autorizados y `DETERMINISTIC_REQUIRED` o `SEMANTIC_OPTIONAL`; solo el perfil ejecutor decide sus skills, Router no participa.
2. `lf_skill_selection_registry_v1`: descriptor `LF_SKILL_SELECTION_DESCRIPTOR_V1`, evidencia, fuente, revisión y `CURRENT/STALE_SOURCE_CHANGED`. Se rechazan entradas stale o catálogo no READY.
3. `lf_profile_skill_selection_prepare_v1`: filtra deterministicamente perfil/canal, operación, efecto, READY, autoridad de escritura gobernada y descriptor CURRENT; obligatorias se seleccionan por política. Para opcionales, entrega `SEMANTIC_SELECTION_REQUIRED` y candidatos al mismo chat nativo. La decisión semántica exige exactamente una skill habilitada, razón, evidencia, source_revision y modo `CURRENT_CONTEXT_REVIEW`; ambigüedad o stale => `BLOCKED`.
4. `lf_profile_execution_plan_v1`: lee los 11 pasos de BD y devuelve skills y `selection_receipt` sin valores codificados para IG en 40/50; no recibe skills del Router.
5. `lf_profile_skill_invoke_selected_v1`: verifica plan contra el RUN existente, llama `lf_skill_invoke_v1` oficial y liga el recibo de selección a `skill_run_id` + `parent_execution_id` en `lf_profile_skill_selection_receipt_v1`. El registro y efecto de la invocación siguen perteneciendo al invocador canónico.
6. IG: `INPUT_GOVERNANCE_CONTEXT_PACK` se añade como **DRAFT**, sin handler habilitado ni descriptor CURRENT hasta comprobación independiente. **No es ejecutable ni READY en Supabase vivo.**

## Candidato Edge/runner, sin API de modelo
- `profile_native_source_bind_v1` consulta el plan en SQL tomando `profile_code` y `channel` del RUN autorizado, nunca del usuario; cuando hay candidatos devuelve `SKILL_SEMANTIC_SELECTION_REQUIRED`. El runner nativo conserva `profile-native-operation-plan.json` cuando READY.
- `profile_native_skill_invoke_v1` usa la función de selección+invocación oficial, que valida de nuevo el perfil, permiso, skill y decisión; autoridad desde Edge OIDC (sin service_role en el chat).
- `scripts/lf_profile_native_resume.py` conserva encadenado 50→60→70→80 en el mismo execution_id, sin modelo externo/API. La resolución semántica real del chat y la invocación integral continúan como **NO-GO** hasta probar workflow nativo sin intervención y validar el handler de IG.

## Pruebas: aislamiento PG17.6/18.7, ROLLBACK
- Fixture 1: IG candidata se habilita `READY`/**CURRENT solo dentro de transacción de prueba**, elegida obligatoria por política, plan 11 pasos y recibo ligado al RUN.
- Fixture 2: skill ficticia elegida por decisión semántica única con descripción y evidencia, plan 11 pasos y recibo ligado al RUN.
- Negativas: elección múltiple => `SKILL_SEMANTIC_SELECTION_AMBIGUOUS`; descriptor `STALE_SOURCE_CHANGED` => `SKILL_DESCRIPTOR_STALE_OR_MISSING`. Ninguna habilita continuación.
- La prueba comprueba SQL y transporte simulado; **NO equivale a ejecutar el modelo ni el handler de IG en la base viva**. Reportar CI solo después de leer el HEAD exacto.
