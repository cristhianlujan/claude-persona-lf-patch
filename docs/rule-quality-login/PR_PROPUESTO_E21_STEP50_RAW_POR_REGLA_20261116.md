# PR PROPUESTO — E21 Step50 ejecución real y RAW por regla (NO EJECUTAR RUN)

**Alcance autorizado por owner:** diseñar contrato de pruebas y evidencia fuente; NO iniciar un nuevo RUN, NO editar #4040 ni E7/E8, NO promover.

## Hallazgo exacto de código

| Fuente | Función / líneas | Falta técnica |
|---|---|---|
| `scripts/lf_profile_native_resume.py` | `main()`, líneas **1487–1512** | La rama `NATIVE_MODEL_INPUT_READY` solo `unwrap_profile_native_evidence` → `run_bound_validator` → `call_json(EDGE_URL, profile_native_continue_v1)`. **Ninguna** operación de reparación por regla se ejecuta antes del RAW. |
| `public.lf_profile_native_bridge_record_output_v1(text,jsonb,jsonb,text,text,text)` | definición live `pg_get_functiondef`, líneas **153–196** | Graba `p_profile_output` literalmente en `execute_profile`, adjuntando solo `profile_source_ref` y `context_receipt_ref`; no acredita `before/after` de regla, no exige evidencias gobernadas de PR/Train ni valida el conjunto de reglas reparadas. |
| `profiles/systemic_root_cause_repair_lf/schemas/output.schema.json` | `repair_execution` **2266–2420** | Permite `AUTHORIZED_NOT_EXECUTED` y `EXECUTED_WITH_READBACK` con `changes[]` y `readback_refs[]`; no exige recibo de PR/Train ni `rule_code` por cada fuente, ni prueba contra `lf_ops.reglas` vigente. |
| `profiles/systemic_root_cause_repair_lf/contracts/runtime_binding.json` | `governance.governed_repair_write.promotion_allowed` | Permanece estático `false`, distinto de E20 (`promotion_allowed` condicional en el handoff): debe evitar contradicción. Perfil NO gana permiso de promoción por ese cambio. |
| `profiles/systemic_root_cause_repair_lf/SKILL.md` | **12, 29, 59–79, 374** | Exige reparación `EXECUTED_WITH_READBACK` solo con autoridad Router, pero contiene veto textual absoluto a promoción. Separar ejecución de la solicitud de promoción; aplicación solo por ruta de promoción gobernada externa. |
| `public.lf_rule_promotion_score_v1(text,text)` | bloque `refs:=p50.evidence_payload#>'{profile_output,deliverable_created,product_decision,source_refs}'` | B busca exclusivamente estructura **Product Director**. El RAW SRCR del Run 95968F50 no tiene ese objeto; su `repair_execution.mode=AUTHORIZED_NOT_EXECUTED`. La fuente por regla y hashes 40/50/60/70 deben validarse con estructura SRCR explícita, no texto libre. |

## Un PR de reparación Step50 a crear, separado de L1/L2 y de #4040

**Título:** `fix(E21 Step50): ejecutar por Train, capturar recibos por regla y source-bind RAW SRCR`.

1. **Operación con efectos, NO escriba del modelo:** ejecutar las reparaciones por regla mediante ACT-0001/`ACTUALIZACION_DB_LF` → PR con migración de alcance → `ready-to-merge` → Merge Train → SELECT readback. El paso 50 del perfil solo consume esos recibos genuinos, no despliega DDL/DML por sí solo.
2. **Contrato de salida SRCR:** agregar `repair_execution.rule_receipts[]` (regla, PR, ejecución de Train, path de migración, before/after SHA fuente, source_ref exacta `supabase://lf_ops.reglas/<code>`, readback SHA, `ci_run` PG17/PG18) y validación estricta `EXECUTED_WITH_READBACK` para cada regla cubierta; hash del RAW incluye recibos del resultado que se registrará.
3. **Barrera de evidencia al Step50:** validar del lado autorizado que la ejecución de Train existe, fue aplicada, coincide con `rule_code`, pantalla/scope, autoría, antes/después, `request_sha256`, `execution_id` y CI en HEAD exacto. No aceptar claims de recibos escritos por LLM ni reutilizar un RUN anterior.
4. **Puente y scorer:** extender `lf_profile_native_bridge_record_output_v1` + validador SRCR y `lf_rule_promotion_score_v1` para reconocer `repair_execution.rule_receipts[].source_ref` además de la ruta Product Director. No otorgar B/D si no hay cadena válida 40/50/60/70, source_ref exacta y regla vigente después de Train; mantener hard_block intacto.
5. **Tests obligatorios PG17/PG18 ROLLBACK:** positivo recibo de efecto real y origin/sha; negativos SHA drift, PR no aplicado, source_ref no ligado, scope fuera de 51, duplicado, recibo ajeno, `AUTHORIZED_NOT_EXECUTED`, A sin `ci_run`, AUTH/PRIVACY hard_block y juez sin fuente. No reemplazar pruebas de autenticación del runtime Java por pruebas de existencia de políticas.
6. Solo **después** de esa reparación, iniciar un **nuevo** Run con `promotion_allowed=true`, registrar Step50 real con recibos de reparación, 60/70/80 y recalcular A/B/C/D por regla. No reutilizar `EXEC-PROFILE-GATE2-95968F50D6214EADB117E45E`.

## Estado

**PROPOSAL_ONLY**. No se ejecutó Step50 nuevo ni se creó RUN nuevo ni se aplicó promoción.
