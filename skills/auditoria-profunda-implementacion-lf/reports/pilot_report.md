# Piloto de auditoría profunda LF — 15/11/2026 (Lima)

Base: `bd599aff0a1353e5850fef1b9675c13b7344b317`. Tres defectos reproducidos en helpers LF locales; cero reparaciones funcionales aplicadas.

| Hallazgo | Ubicación | Observación real | Estado |
|---|---|---|---|
| LF-DA-001 | `scripts/lf_step70_separate_call_receipt_v1.py:118` | wrong_run_evaluator_status=PASS; explicit_binding_rejects=STEP70_RUN_ID_DRIFT | CONFIRMED local |
| LF-DA-002 | `scripts/lf_step70_separate_call_receipt_v1.py:119` | STEP70_SEPARATE_EVALUATOR_NOT_PASS → PASS_REVIEWED_CURRENT_CONTEXT; receipt_retained=false; downstream.accepted=true | CONFIRMED local |
| LF-DA-003 | `scripts/lf_step70_same_llm_eval_v1.py:52` | evaluator_status=PASS y schema_errors=['x is too short']; baseline válida pasa ambos | CONFIRMED local |

## Autoridad vigente

Se detectó e integró el cambio concurrente PR #4009 antes de publicar este candidato. SELECT de `public.lf_rule_promotion_request_v1` (MD5 `b3e08bb45bdf5bcbf5cfee5316ba3061`) admite `PASS_REVIEWED_CURRENT_CONTEXT` para **solicitar** promoción con autoridad del perfil, regla CANDIDATO, hashes Step40/50/60/70 y score. `lf_rule_promotion_score_v1` registra `NOT_PROVEN_OWNER_ACCEPTED`; no afirma independencia probada. El score distingue BLOCKED/MANUAL/AUTO, pero `lf_rule_promotion_decide_v1` mantiene `APPROVER_MUST_BE_HUMAN`: AUTO no suplanta a HUMAN. `manifest.no_promotion` fue neutralizado como veto. Esta auditoría no solicita ni aplica promociones.

El error EKB que imponía el requisito anterior quedó SUPERSEDED; se conservan snapshots anteriores como historia. El checklist vigente revisa 16 registros. Las tres reproducciones Python siguen presentes en la base nueva. Evidencia: [gobernanza actual](../references/governance_current_readback.json) y [EKB actual](../references/ekb_current_snapshot.json).

## Pruebas y medición

33 pruebas locales ejecutadas; 0 fallos; 0 errores. Incluyen diez casos de aceptación y negativos.

| Medición | Antes | Después | Alcance |
|---|---|---|---|
| Consultas repetidas | 5 | 1 | Fixture Python, mismos resultados y controles de identidad |
| Operaciones VM SQL | 68013 | 21 | SQLite, 20 000 filas, no benchmark PG |
| Plan SQL | SCAN payments | SEARCH por índice tenant/external_id | Resultado idéntico; tenant incorrecto devuelve vacío |

Los tests que reproducen defectos pasan porque comprueban el fallo esperado; no convierten código defectuoso en PASS funcional.

## LF-DA-001 — EXECUTION_ID_NOT_BOUND

Ubicación: `scripts/lf_step70_separate_call_receipt_v1.py:118`, función `normalize_when_unverified`, commit `bd599aff0a1353e5850fef1b9675c13b7344b317`, SHA256 `69fd695d432c1b02ddb0fd199f48054a7b26be6583730d338df481e9a634e43c`.

Código encontrado:
```python
        r=assess_separate_call_receipt(review)
```

Esperado: El RUN del caller debe llegar al validador del recibo y compararse con su execution_id.

Defecto: La llamada omite el execution_id esperado; un recibo sintético de otro RUN pasa el EVAL local si sus hashes coinciden.

Causa raíz: El padre conoce execution_id pero normalize_when_unverified no lo recibe. assess tiene guard opcional; evaluate recibe el mismo r.execution_id como dato y esperado.

Impacto: Binding de procedencia local; Diagnóstico del Step70 antes de SQL; No demuestra que SQL acepte promoción cruzada.

Corrección propuesta (sin aplicar):
```python
# Propuesta coordinada, no aplicada
# lf_profile_native_resume.py, complete_native_profile_semantic_and_report:
semantic_review, assessment = normalize_when_unverified(semantic_review, execution_id=execution_id)
# lf_step70_separate_call_receipt_v1.py:
def normalize_when_unverified(review, *, execution_id):
    r = assess_separate_call_receipt(review, execution_id=execution_id)
# Propagar el mismo argumento a validate_independent_semantic_review y sus callers;
# rechazar STEP70_RUN_ID_DRIFT antes de cualquier degradación de procedencia.
```

Prueba positiva: Recibo fixture válido del RUN esperado devuelve evaluator_status=PASS, con independencia no acreditada.

Prueba negativa: Recibo fixture de otro RUN: llamada sin binding acepta EVAL; con execution_id explícito rechaza STEP70_RUN_ID_DRIFT.

Resultado y readback: wrong_run_evaluator_status=PASS; explicit_binding_rejects=STEP70_RUN_ID_DRIFT. Consumidor: assess_separate_call_receipt → evaluate.

Evidencia ejecutada: `skills/auditoria-profunda-implementacion-lf/reports/pilot_trace.json#/run_binding`. Estado `CONFIRMED`; fix_scope `NONE`.

## LF-DA-002 — EVAL_FAILURE_MASKED

Ubicación: `scripts/lf_step70_separate_call_receipt_v1.py:119`, función `normalize_when_unverified`, commit `bd599aff0a1353e5850fef1b9675c13b7344b317`, SHA256 `69fd695d432c1b02ddb0fd199f48054a7b26be6583730d338df481e9a634e43c`.

Código encontrado:
```python
    except ValueError as exc:
        r={"status":"JUDGE_INDEPENDENCE_NOT_PROVEN",
           "producer_independence_proven":False,
           "receipt_contract_error":str(exc),
           "content_continuation_allowed":True}
    if r["status"]=="JUDGE_INDEPENDENCE_NOT_PROVEN" or not r["producer_independence_proven"]:
        safe=dict(review)
```

Esperado: Separar procedencia no acreditada de EVAL material fallido; conservar contradicciones de dictamen y no emitir PASS por fallback.

Defecto: Un receipt cuyo decision_body tiene unsupported_claims falla EVAL; el normalizador borra el receipt y genera PASS contextual que acepta el validador local con checks externos favorables.

Causa raíz: El catch de todo ValueError convierte errores materiales en JUDGE_INDEPENDENCE_NOT_PROVEN; luego sobrescribe verdict y elimina la evidencia discordante.

Impacto: Consistencia de dictamen anidado/externo; Validación local permite continuar tras material FAIL; Aceptación final por SQL/Edge no probada.

Corrección propuesta (sin aplicar):
```python
# Propuesta, no aplicada
except ValueError as exc:
    return review, {"status": "REVIEW_INVALID",
        "receipt_contract_error": str(exc),
        "producer_independence_proven": False,
        "content_continuation_allowed": False}
# En complete_native_profile_semantic_and_report, antes de persistir/normalizar:
if assessment.get("content_continuation_allowed") is not True:
    print(json.dumps({"phase": "SEMANTIC_REVIEW",
        "code": assessment.get("receipt_contract_error")}))
    return 1
# Mantener el caso de receipt ausente como procedencia no probada;
# para revaluar contenido producir evaluación explícita, sin borrar contradicción.
```

Prueba positiva: Receipt materialmente válido mantiene baseline RECEIPT_FORMAT_VALID_PROVENANCE_UNATTESTED, sin afirmar independencia.

Prueba negativa: unsupported_claims no vacío provoca STEP70_SEPARATE_EVALUATOR_NOT_PASS; comprobar si el fallback conserva el rechazo.

Resultado y readback: STEP70_SEPARATE_EVALUATOR_NOT_PASS → PASS_REVIEWED_CURRENT_CONTEXT; receipt_retained=false; downstream.accepted=true. Consumidor: normalize_when_unverified → validate_independent_semantic_review.

Evidencia ejecutada: `skills/auditoria-profunda-implementacion-lf/reports/pilot_trace.json#/eval_masking`. Estado `CONFIRMED`; fix_scope `NONE`.

## LF-DA-003 — EVAL_INPUT_INCOMPATIBLE

Ubicación: `scripts/lf_step70_same_llm_eval_v1.py:52`, función `evaluate`, commit `bd599aff0a1353e5850fef1b9675c13b7344b317`, SHA256 `62a306f4f44aac9aee959c578b4d63c330a80e8918ae77133d1481ee21a5fce0`.

Código encontrado:
```python
    chk(isinstance(refs,list) and len(refs)>0 and all(isinstance(r,str) and r for r in refs),
        "REVIEW_SOURCE_REFS_MISSING")
```

Esperado: EVAL debe respetar source_refs.items.minLength=4 del schema LF_STEP70_SAME_LLM_REVIEW_OUTPUT_V1.

Defecto: source_refs=['x'] incumple la SPEC pero el mismo RAW obtiene eval_status=PASS.

Causa raíz: EVAL comprueba string no vacío y omite el mínimo del schema; no ejecuta ese schema completo.

Impacto: Paridad SPEC/EVAL de referencias; Calidad del recibo evaluado; No acredita resolución real de refs ni autorización.

Corrección propuesta (sin aplicar):
```python
chk(isinstance(refs, list) and len(refs) > 0
    and all(isinstance(ref, str) and len(ref) >= 4 for ref in refs),
    "REVIEW_SOURCE_REFS_SCHEMA_INVALID")
# Añadir regresión de paridad con el schema congelado;
# validar referencias materialmente en la capa contextual, no solo por longitud.
```

Prueba positiva: RAW con source_refs fixture válidos: schema sin errores y EVAL PASS.

Prueba negativa: Mismo RAW con ['x']: schema rechaza 'x is too short'; EVAL actual devuelve PASS.

Resultado y readback: evaluator_status=PASS y schema_errors=['x is too short']; baseline válida pasa ambos. Consumidor: evaluate → assess_separate_call_receipt (no schema enforcement).

Evidencia ejecutada: `skills/auditoria-profunda-implementacion-lf/reports/pilot_trace.json#/schema_eval`. Estado `CONFIRMED`; fix_scope `NONE`.

## Límites y pendientes

- Los tres defectos están confirmados en helpers LF locales con entradas sintéticas de tests existentes; no se afirma explotación, aceptación SQL ni promoción real.
- No se aplicó corrección LF; todos los fixes son propuestas sin before/after aplicado.
- La autoridad SQL se consultó por definición en sandbox; no se invocó el promocionador.
- EKB es snapshot histórico. Checklist complementa descubrimiento, no garantiza ausencia de otros defectos.
- La suite automática acota estructura/fixtures; la semántica depende de la lectura del modelo nativo.
- PR/CI exact-head y evaluación del owner se informan en GitHub; este reporte no declara merge ni instalación.

Archivos de evidencia: [reporte JSON](pilot_report.json), [traza](pilot_trace.json), [tests](test_results.json), [readback SQL actual](../references/governance_current_readback.json), [EKB actual](../references/ekb_current_snapshot.json).

## Prueba de generalización

Un contexto nativo nuevo recibió la skill y tres archivos nuevos, sin respuestas esperadas. Detectó cuatro defectos: currency omitido en SPEC, currency perdido en payload, revision calculado pero no enviado y WAITING_FUNDS sin rama. Reprodujo 24/24 controles. Primero bloqueó formalmente por falta de commit; una segunda ejecución bajo commit real validó PASS sin relajar schema. El reporte acota EKB/consumidores externos no inspeccionados como PARTIAL. No es un juez de gobernanza LF. La suite incluye tres regresiones portátiles del caso. Evidencia: [forward_test.json](forward_test.json).
