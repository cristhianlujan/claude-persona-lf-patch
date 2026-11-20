# B08_IDENTITY · G04 — Cotejo literal L28, SIN cierre ni escritura a live

Fuente literal: https://github.com/cristhianlujan/claude-persona-lf-patch/blob/lf/issue-3779-lote28-blocker-closure-plan-v1/audits/rule-quality-lote28/12_criterios_cierre_motor_7.md
Documento 12 blob Git SHA-1: 130d474921e0ad010e94a645a8f350f3ca86e611.

Texto rector (B08 G04 temporal):
"después de #3803 por Train, realizar una decisión documental de prueba registrada por el escritor oficial con todos los campos citados arriba, identity_verified=false, literal de decisor, fecha, SHA de record, SHA preimagen/propuesta, proponente distinto, parent RUN real elegible y readback en tabla/registro. Verificar negativa para decisor distinto, autorevisión documental, stale hash, decisión duplicada, fecha incorrecta y cualquier intento de marcar identity_verified=true sin prueba."

| Exigencia literal | Evidencia ejecutada | Estado estrictamente acreditado | Responsable del remanente |
|---|---|---|---|
| #3803 instalado por Train | Migración real fuente / Supabase SQL de solo lectura | PASS histórico, desplegado | ninguno |
| Escritor oficial y seis campos documentales | PG17.6/PG18.7 ejecutan function source sin modificar, positivo RECHAZAR y APROBAR con rollback | PASS LAB | — |
| Identity_verified=false e identity_mode=UNVERIFIED_CHAT_DECLARATION | Respuesta JSON bool false; columna registry exacta | PASS LAB | — |
| Literal de decisor + fecha y proponente distinto | Readback campos y parent synthetic output RAW proposed_by=product_director_lf | PASS LAB; actor real NO verificado | Operador RUN / IG |
| SHA registro y SHA preimagen/propuesta | Recalculo SHA256 del decision_record JSONB y coincidencia con 2 SHA de origen/patch | PASS LAB | — |
| Parent RUN real elegible | Fixture profile RUN IN_PROGRESS y cuatro pasos insertados únicamente en PG; no RUN real creado | **NO ACREDITADO EN LIVE** | Router, perfil y operador IG del carril oficial |
| Readback tabla/registro de decisión real | Readback completo dentro de transacción PG; luego ROLLBACK; SELECT live registra 0 filas en lf_ig_owner_decision_v2 | PASS LAB, **NO EN LIVE** | Operador escritor oficial, una autorización de nueva operación real |
| Negativo decisor distinto | LF_IG_OWNER_DECISION_INPUT_INVALID + 0 filas en PG17.6/18.7 | PASS LAB | — |
| Negativo autorevisión | LF_IG_OWNER_SELF_APPROVAL_FORBIDDEN + 0 filas | PASS LAB | — |
| Negativo stale SHA | LF_IG_OWNER_SOURCE_PREIMAGE_DRIFT + 0 filas | PASS LAB | — |
| Negativo duplicado | LF_IG_OWNER_DECISION_ALREADY_RECORDED_NO_OVERRIDE + 0 filas | PASS LAB | — |
| Negativo fecha incorrecta | LF_IG_OWNER_DECISION_DATE_INVALID + 0 filas; además OUT_OF_SCOPE | PASS LAB | — |
| Negativo identity_verified=true indebido | Séptimo campo booleano se deniega con LF_IG_OWNER_DECISION_RECORD_REQUIRED + 0 filas | PASS LAB | — |
| No JWT/MFA/atribución física temporal | Prueba usa string documental, no token/claim; tampoco demuestra identidad humana real | PASS de NO uso, no IAM | Seguridad/IAM para base final |
| Recibo y aceptación de B08 por plan | No expedidos | **PENDIENTE** | Auditor del plan L28 y dueño según criterio |

**Restricciones ejecutadas**: nunca se invocó lf_ig_rule_owner_decide_v2 contra el Supabase vivo; no se escribieron decisiones, RUNs ni se alteraron migraciones; no se añadió vía paralela de producción. Cierre B08 sigue **NO-GO** hasta resolver los puntos de RUN y recibo real por el carril oficial, fuera de este lote. Ninguna firma autenticada se atribuye al decisor temporal.

## Referencias
- PR test evidence: https://github.com/cristhianlujan/claude-persona-lf-patch/pull/3815
- R17: https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43414806820
- PASE: https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/43414806705
- Fuente SQL oficial: supabase/migrations/20261113030000_lf_ig_rule_lifecycle_writer_v2.sql
- Test: sandbox/lf_contract_gate_test/edge_function_operation/test_b08_documentary_owner_decide_pg176_pg187.py
