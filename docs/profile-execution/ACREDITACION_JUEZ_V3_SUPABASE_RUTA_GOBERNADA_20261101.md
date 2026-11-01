# LF — Acreditación operativa del juez V3 mediante Supabase y ruta gobernada

**Estado:** documentación de procedimiento existente, basada en readback real. **Tipo de cambio:** documental, sin alterar juez, Router, Edge, RPC, permisos, EKB ni tablas. **Fecha:** 2026-11-01. **Alcance:** `EJECUCION_PERFIL_LF` / `semantic_judge` (paso 70) / `report_output` (paso 80).

## 1. Regla de lectura operativa

**La evidencia oficial de que el resultado del juez pasó por la ruta gobernada y fue aceptado** es el registro servidor de `public.lf_operation_execution_steps` del mismo `execution_id`, `step_id='semantic_judge'`, `status='STEP_PASS_WITH_EVIDENCE'`, asociado al recibo `actions://...` y a un run exitoso del workflow `lf-profile-resume-governed`, con comprobación de `trust_validation.valid=true` y digests originales. El paso 80 y `COMPLETED` se confirman con readback propio.

Este registro es **la acreditación operativa que utiliza el flujo vigente**. **No se exige un segundo comprobante externo al procedimiento para demostrar que el resultado fue transportado, evaluado y registrado**, y no se debe diagnosticar un error de invocación a partir de que la herramienta de lectura del asistente no pueda escribir en Supabase.

**Límite de afirmación:** la fila certifica la **aceptación y persistencia gobernadas del dictamen** y el contenido de las afirmaciones del recibo. Si `model_call_count=1`, `producer_independence_proven=true` y `judge_invocation_kind` figuran en el dictamen, son **campos declarados y aceptados por el validador**. El registro por sí solo **no es un log de una petición HTTP al proveedor del modelo ni una prueba externa de identidad del contexto de revisión**. No atribuirle tal capacidad; tampoco exigir evidencias nuevas no previstas por contrato para reconocer el cierre operacional ya registrado. Esto coincide con el EKB `LF-PE-STEP70-MODEL-RECEIPT-NOT-ATTESTED-20261031-002`.

## 2. Recorrido existente, sin crear otro juez

```text
Dictamen independiente V3 sobre RAW y scope exactos (no reutilizar otro run)
    -> GitHub Issue: LF_PROFILE_NATIVE_RESUME_REQUEST_V1
       campo semantic_judge_review, execution_id exacto
    -> etiqueta lf-profile-resume-governed
    -> GitHub Actions: LF Edge Deploy Credential Readback / native-profile-resume
    -> scripts/lf_profile_native_resume.py (checkout exacto, OIDC)
    -> Edge profile_native_continue_v1
    -> RPC lf_profile_native_bridge_record_semantic_v1
    -> RPC lf_record_profile_execution_step_v1
    -> Supabase: semantic_judge STEP_PASS_WITH_EVIDENCE [70]
    -> RPC lf_profile_native_bridge_record_report_v1
    -> Supabase: report_output STEP_PASS_WITH_EVIDENCE [80]
    -> lf_operation_execution COMPLETED, 11/11 clean
    -> terminal authority receipt READY
```

`service_role` permanece en la ruta server-side autorizada; no viaja en Router, Issue ni dictamen. `ACT-0001` solo deriva; no inicia directamente el perfil. El registro de un dictamen V3 exige que **ya exista un resultado de revisor para ese RAW**: el workflow de registro **no produce por sí solo una llamada independiente de modelo**. No tomar un PASS histórico, un `self_verdict` del productor ni un objeto construido ad hoc como resultado nuevo.

## 3. Readback mínimo verificable

Ejecutar en modo **solo lectura**, sobre el `execution_id` real:

```sql
select
    e.execution_id,
    e.status as execution_status,
    s.step_id,
    s.status as step_status,
    s.evidence_ref,
    s.evidence_payload->>'recorded_by_rpc' as recorder,
    s.evidence_payload#>>'{trust_validation,valid}' as trust_valid,
    s.evidence_payload#>>'{semantic_judge_result,candidate_sha256}' as candidate_sha256,
    s.evidence_payload#>>'{semantic_judge_result,scope_packet_sha256}' as scope_packet_sha256,
    s.evidence_payload#>>'{semantic_judge_result,model_call_count}' as declared_model_call_count,
    s.evidence_payload#>>'{semantic_judge_result,producer_independence_proven}' as declared_independence
from public.lf_operation_execution e
join public.lf_operation_execution_steps s using (execution_id)
where e.execution_id = '<EXECUTION_ID_VERIFICADO>'
  and s.step_id in ('semantic_judge', 'report_output')
order by s.step_order;
```

**Criterio paso 70:** fila `semantic_judge` presente y PASS; `evidence_ref` de artifact/run auténtico; `recorded_by_rpc` canónico; `trust_valid=true`; candidato y scope coinciden con hashes originales persistidos en `execute_profile` e `input_validate`; recibo V3 exactamente asociado al mismo `execution_id`, con 12 controles y check 11 `NOT_TESTED / not_applicable / ROUTER_ONLY` cuando no existe una comparación directa autorizada. Si hay `FAIL`, `BLOCKED` o `unsupported_claims`, no promover a PASS.

**Criterio paso 80:** fila `report_output` presente y PASS; estado general `COMPLETED`; 11 pasos `STEP_PASS_WITH_EVIDENCE`; `lf_profile_execution_terminal_authority_receipt_v1` en estado `READY`. No dar por completado un run con solo el paso 70.

## 4. Caso vivo acreditado — run 458E1067

- `execution_id`: `EXEC-PROFILE-GATE2-458E10677E34F812D924F11F`.
- [Issue #3436](https://github.com/cristhianlujan/claude-persona-lf-patch/issues/3436): transportó `semantic_judge_review` con 12 controles V3.
- [GitHub Actions #41258310552](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/41258310552): el job `Governed native profile bridge continuation` terminó **SUCCESS** y subió artifact `profile-native-output-41258310552/profile-semantic-judge.json`.
- En Supabase: `semantic_judge` (70) y `report_output` (80), ambos `STEP_PASS_WITH_EVIDENCE`; `lf_operation_execution.status=COMPLETED`, **11/11**; recibo terminal `READY`.
- `semantic_judge.evidence_ref`: `actions://cristhianlujan/claude-persona-lf-patch/runs/41258310552/artifact/profile-native-output-41258310552/profile-semantic-judge.json`.
- `recorded_by_rpc=lf_record_profile_execution_step_v1`, `core_recorder=lf_record_operation_step_core_v1`, `trust_validation.valid=true`.
- `candidate_sha256=815f640140722886b642bec43b21d827b9971dcd181faefddce82e9172ae3caf`.
- `scope_packet_sha256=31d65a5ed4b28f5d3a9aa492133d83f48f1656d872af8b80819c76dbaf6e9ccc`.
- El dictamen registrado declara `model_call_count=1`, `producer_independence_proven=true` y `judge_invocation_kind=NEW_INDEPENDENT_CURRENT_CHAT_GPT_NATIVE`; el workflow probado **consumió** ese JSON, **no invocó** al modelo nuevamente.

**Veredicto probatorio:** cierre gobernado y validación de contrato del recibo **ACREDITADOS**; una traza independiente del proveedor de la llamada de modelo **NO OBSERVADA** (no es requisito de readback adicional del procedimiento actual). No extrapolar estos hashes a otro run.

## 5. Estado del nuevo caso PR #3438 (no confundir con el anterior)

- Run `EXEC-PROFILE-GATE2-FB71EBD7D1A89272BFF20E44`.
- RAW original: `f497633c50d83d55b6247474c909f2b075eb531f3c069173698a7972ea4cfb87`.
- Scope: `7e8583e01c5dfa833838b73f68f4e08e15019da9b315f6ddabc97468ca066e0d`.
- [Actions #41266315589](https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/41266315589): `execute_profile` y `output_validate` PASS.
- **Readback de 2026-11-01:** `IN_PROGRESS`, 9/11, sin `semantic_judge` ni `report_output`. Este caso **aún no está acreditado ni cerrado**. Debe recibir un dictamen V3 del juez sobre **estos hashes**, mediante el mismo Issue/label/Edge/RPC; una vez registrado, comprobar terminal 11/11 y `READY`. No inventar una invocación para saltar esta precondición.

## 6. Control de interpretación y EKB

- `LF-PE-STEP70-CHAT-VERDICT-NOT-PERSISTED-20261031-001`: un dictamen en chat sin pase gobernado no equivale a step 70.
- `LF-PE-STEP70-MODEL-RECEIPT-NOT-ATTESTED-20261031-002`: recibo del transporte verificable; no convertir un campo `true`/ `1` en prueba externa de proveedor.
- `PROFILE-EXECUTION-SEMANTIC-JUDGE-NOT-ENFORCED-001` sigue en `ACTIVE_REMEDIATION`: cerrar un run 11/11 no prueba por sí solo el canary negativo del enforcement.
- Fuente canónica de juzgamiento: `profiles/product_director_lf/judges/product_director_semantic_judge.md` V3. Fuentes de ejecución: `scripts/lf_profile_native_resume.py`, `supabase/functions/lf-profiles-governance-caller-v1/profile_continuation.ts`, `public.lf_profile_native_bridge_record_semantic_v1`, `public.lf_profile_native_bridge_record_report_v1`.

**No se modifican:** la semántica del juez, los requisitos de recibo, los escritores, el estado del EKB, las autorizaciones ni el Router. Toda ampliación futura de evidencia de identidad del proveedor requiere un cambio de contrato separado y prueba de enforcement.
