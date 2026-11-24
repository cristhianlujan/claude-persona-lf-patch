# SALY — K01–K06 · Reestructuración candidata · Registro de pruebas

**Alcance:** sucesor del selector `visual.knowledge_select_review_v1`, matriz por tarea, único dueño por objeto, QA previo, referencia opcional y espera; no ejecutar Merge Train ni aplicar SALY real.

**PR:** https://github.com/cristhianlujan/claude-persona-lf-patch/pull/4689 (DRAFT — NO MERGE)  
**Ejecución:** https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/45298444825 — PostgreSQL 17 desechable, SUCCESS.  
**Dataset:** seis documentos K01–K06, bytes/SHA y 10 evidencias recuperadas en **solo lectura** de Supabase y cargadas en PostgreSQL 17 aislado. `visual.knowledge_select_review_v1` y `saly.creative_run_expire_v1` fueron copiados del `pg_get_functiondef` real.

## 1. Entrada → salida literal por caso

Los valores a continuación proceden del log real, sin inferencia ni sustituciones. Para la instrucción SQL completa ver el script; para timestamps ver el archivo de evidencia.

| Caso | INPUT | OUTPUT |
|---|---|---|
| A · NEW_SCREEN | `task=NEW_SCREEN; spatial=false; item=101; source=visual.knowledge_select_review_v1` | `{"source": "visual.knowledge_select_review_v1", "omitted": 0, "selected": ["K01", "K02", "K03", "K04", "K05", "K06"], "module_content_count": 6}` |
| B · NUMERIC_ADJUST | `task=NUMERIC_ADJUST; spatial=false; item=102` | `{"omitted": [{"reason": "TAREA_LOCAL_SIN_REDISENO", "module_code": "K01"}, {"reason": "TAREA_LOCAL_SIN_REDISENO", "module_code": "K02"}, {"reason": "TAREA_NO_REQUIERE_RECOMPOSICION", "module_code": "K03"}, {"reason": "TAREA_NO_REQUIERE_RECOMPOSICION", "module_code": "K04"}], "selected": ["K05", "K06"]}` |
| C · LOCAL_CORRECTION espacial | `task=LOCAL_CORRECTION; spatial=true; item=103` | `{"omitted": ["K01", "K02", "K03"], "selected": ["K04", "K05", "K06"]}` |
| D · Sin referencia | `step4; reference=NULL; image not sent by owner` | `{"step": "4", "status": "SIN_REFERENCIA", "execute": false, "blocking": false, "reference_observations": []}` |
| E · READY a 20 s | `E20_INPUT=ready_at_20_seconds` | `E20_OUTPUT= {'status': 'READY', 'first_observed_ready_seconds': 30, 'checks': [{'elapsed_seconds': 0, 'status': 'PENDING'}, {'elapsed_seconds': 30, 'status': 'READY'}, {'elapsed_seconds': 60, 'status': 'READY'}, {'elapsed_seconds': 90, 'status': 'READY'}, {'elapsed_seconds': 120, 'status': 'READY'}, {'elapsed_seconds': 150, 'status': 'READY'}, {'elapsed_seconds': 180, 'status': 'READY'}], 'count': 7, 'elapsed_seconds': 180, 'next_step': '11'}` |
| E · READY a 100 s | `E100_INPUT=ready_at_100_seconds` | `E100_OUTPUT= {'status': 'READY', 'first_observed_ready_seconds': 120, 'checks': [{'elapsed_seconds': 0, 'status': 'PENDING'}, {'elapsed_seconds': 30, 'status': 'PENDING'}, {'elapsed_seconds': 60, 'status': 'PENDING'}, {'elapsed_seconds': 90, 'status': 'PENDING'}, {'elapsed_seconds': 120, 'status': 'READY'}, {'elapsed_seconds': 150, 'status': 'READY'}, {'elapsed_seconds': 180, 'status': 'READY'}], 'count': 7, 'elapsed_seconds': 180, 'next_step': '11'}` |
| E · Nunca READY | `ENEVER_INPUT=never_ready` | `ENEVER_OUTPUT= {'status': 'ESPERA_AGOTADA', 'run_state': 'FALLIDO', 'run_expired': True, 'checks': [{'elapsed_seconds': 0, 'status': 'PENDING'}, {'elapsed_seconds': 30, 'status': 'PENDING'}, {'elapsed_seconds': 60, 'status': 'PENDING'}, {'elapsed_seconds': 90, 'status': 'PENDING'}, {'elapsed_seconds': 120, 'status': 'PENDING'}, {'elapsed_seconds': 150, 'status': 'PENDING'}, {'elapsed_seconds': 180, 'status': 'PENDING'}], 'count': 7, 'elapsed_seconds': 180}` |
| E · Expirar RUN SQL | `expired RUN deadline passed; use ORIGINAL creative_run_expire_v1` | `{"state": "FALLIDO", "run_id": 501, "status": "EXPIRED_CLOSED", "changed": true, "error_code": "LEASE_EXPIRED", "attempt_number": 1, "retry_dispatched": false}` |
| F · Doble K | `record K05 twice on same PLAN object; item 102` | `{"k05_row_count": 1, "step9_consumer": {"requirements": ["CTA copy unchanged"]}}` |
| G · K06 dos objetos | `K06 reviews PLAN and IMAGE as different objects, once each` | `{"k06_objects": 2, "different_objects": 2}` |
| H · QA independiente | `preQA author submits plan, same author attempts PASS, different reviewer PASS` | `{"verdict": "PASS", "different_reviewer": true}` |
| Z · ROLLBACK | `ROLLBACK all candidate changes and execution/QA records` | `{"preqa_rows": 0, "result_rows": 0, "selection_rows": 0, "creative_run_rows": 0}` |

### Otros readbacks reales
- **F, segundo intento del mismo K05 PLAN:** `2026-11-24T00:36:16.0316293Z psql:sandbox/creative_factory/k_task_v2/test_rollback_pg17.sql:92: NOTICE:  F_SECOND_OUTPUT: SALY_K_DUPLICATE_OBJECT_EXECUTION`.
- **F, readback step 9:** `{"k05_row_count": 1, "step9_consumer": {"requirements": ["CTA copy unchanged"]}}`. Reutiliza salida de K05, sin repetir ejecución.
- **H, intento de auto-PASS:** `2026-11-24T00:36:16.0328503Z psql:sandbox/creative_factory/k_task_v2/test_rollback_pg17.sql:128: NOTICE:  H_SELF_REVIEW_OUTPUT: SALY_PREQA_INDEPENDENT_REVIEWER_REQUIRED`.
- **H, revisión independiente:** `{"status": "PASS", "plan_sha256": "ac3df17b58b39a343f24cf80bb944605a5e72e5d8a22035866da9f0b7996d9e5", "reviewer_uid": "22222222-2222-4222-8222-222222222222", "independent_pass": true}`.
- **E, expiración no permitida:** `2026-11-24T00:36:16.1231859Z test_expirer_refuses_without_deadline (sandbox.creative_factory.k_task_v2.test_wait_after_dispatch_v2.TestWait.test_expirer_refuses_without_deadline) ... E_EXPIRY_GUARD_OUTPUT= {'status': 'EXPIRY_NOT_CONFIRMED', 'expire_readback': {'status': 'NOT_EXPIRED', 'changed': False}, 'checks': [{'elapsed_seconds': 0, 'status': 'PENDING'}, {'elapsed_seconds': 30, 'status': 'PENDING'}, {'elapsed_seconds': 60, 'status': 'PENDING'}, {'elapsed_seconds': 90, 'status': 'PENDING'}, {'elapsed_seconds': 120, 'status': 'PENDING'}, {'elapsed_seconds': 150, 'status': 'PENDING'}, {'elapsed_seconds': 180, 'status': 'PENDING'}], 'count': 7}`.

## 2. Entradas SQL y salida original sin reducción

- [SQL íntegro ejecutado](./test_rollback_pg17.sql)
- [Datos y documentos K reales usados en PostgreSQL 17 descartable](./fixture_live_knowledge_pg17.sql)
- [Log original de entrada/salida con timestamps](./github_actions_pg17_exact_io_20261124.txt)
- [Código de espera](./wait_after_dispatch_v2.py)
- [Pruebas de espera](./test_wait_after_dispatch_v2.py)

## 3. Estado de implementación — comprobado vs no comprobado

| Bloque | Estado | Evidencia / límite |
|---|---|---|
| Fuente única de K | **Probado en PG17 aislado** | Selector v2 llama v1 original y verifica bytes, versiones y evidencias |
| Matriz de 4 familias + espacial | **Probado** | A/B/C, además contratos para LOCAL_CHAT y corrección no espacial (sin caso independiente de test aún) |
| Un K por objeto | **Probado** | Segundo K05 rechazado; K06 PLAN e IMAGE permitidos como objetos distintos |
| Reutilización K05 en paso 9 | **Probado** | `creative_k_consume_v2` entrega exactamente resultado previo |
| Paso 4 SIN_REFERENCIA | **Probado** | `blocking=false` |
| QA plan independiente | **Probado con JWT simulado** | Autor ≠ revisor; no acredita un revisor externo conectado en SALY |
| Espera 7 checks (mín. 180 s) | **Probado con reloj virtual** | Listo a 20 detectado t30; listo a 100 detectado t120; sin listo→expire en t180 |
| Expiración real de función | **Probado en PG17 aislado** | `creative_run_expire_v1` original: estado FALLIDO/LEASE_EXPIRED con deadline vencido |
| Atomicidad | **Probado** | ROLLBACK: 0 selecciones, 0 resultados, 0 QA, 0 RUN |
| Ingreso y fuente del pedido (1) | **No probado end-to-end** | Se conserva contrato viejo; requiere adaptador de ingreso real |
| Descubrimiento de los 55 tokens/alias (3) | **Prueba separada #4688, no aplicada** | Depende de contexto SEALED+snapshot y alias 21–33. Alias 58–61 ya están correctos |
| Consolidación de seis dimensiones (6b) | **Especificada, no ejecutada por orquestador real** | No se introduce segunda ejecución de K |
| Handoff físico y despacho (9/10) | **No probado** | No se envió prompt ni adjuntos a Native; pendiente persistencia del payload literal y recibo |
| Polling contra proveedor real (10b) | **No probado** | `image_gen` en chat es bloqueante, no expone polling interno; se requiere readback real post-dispatch |
| QA visual con imagen real (11) | **No probado** | Solo ledger de K06 por IMAGE, no inspector real ni rúbrica aplicada a imagen |
| Diagnóstico+reintento acotado (11b) | **Especificado, no probado** | No se dispararon regeneraciones |
| Cierre item/order a TERMINADO (12) | **No probado** | `creative_chat_finalize_after_verified_delivery_v1` aún exige APROBADO internamente; no afirmar la contradicción resuelta |

## 4. Criterio de cierre del lote

Lote de pruebas de matriz/registro/QA y reloj virtual: **PASS**.  
Implementación completa de los 12 pasos + 6b/10b/11b sobre SALY real: **NO CERRADA**.  
Este PR queda DRAFT, sin merge, etiquetas de tren ni despliegue. La continuación requiere evidencia de integración, no nuevos candados a candidatos.

