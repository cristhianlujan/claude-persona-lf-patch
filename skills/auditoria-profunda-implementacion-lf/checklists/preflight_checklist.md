# Checklist por contexto y errores EKB

Actualizar references/ekb_current_snapshot.json con SELECT al reutilizar. Por revisión:
applies, motivo, resultado, evidencia y prueba. CANDIDATO no es confirmado;
SUPERSEDED no es regla vigente. El checklist orienta y no limita descubrimiento.

| Revisión | EKB fuente | Prueba |
|---|---|---|
| Campos obligatorios incluso pass_when | LF-PE10A-ASSERTION-CONTRACT-PASSWHEN-NULL-READY-20261027-001 | Consumidor vs SPEC; no READY sin condición |
| Identidad/SHA llegan completos | LF-IG-SCOPE-HASH-MISMATCH-20261114-001 (candidato) | Wrong run/tenant/scope/hash rechazados |
| Contexto aceptado sin inventar independencia | LF-OWNER-SCORE-CURRENT-CONTEXT-PROMOTION-20261115-001 | Score/hash/autoridad del efecto; AUTO no sustituye HUMAN |
| No agregar veto no aprobado del manifest | LF-OWNER-OVERRIDE-NO_PROMOTION-MANIFEST-20261115-001 | no_promotion no decide el pase; conservar demás límites explícitos |
| Revisar supersesión antes de reutilizar error | LF-QUALITY-CURRENT-CONTEXT-TECHNICAL-PASS-NOT-APPROVAL-20261115-001 (SUPERSEDED) | Histórico; no usar su antiguo veto para solicitudes actuales |
| Recibo no autoacredita independencia | LF-PE-STEP70-MODEL-RECEIPT-NOT-ATTESTED-20261031-002 | Flags/refs inventados rechazados |
| Autoridad humana separada | LF-PROMO-INDEPENDENT-JUDGE-OWNER-20261114-001 | PASS sin autoridad no habilita efecto |
| Primera falla antes de RPC | LF-PE-STEP70-WRITER-DIAGNOSIS-BEFORE-INSERT-20261031-003 | Reproducir argumento antes de culpar ACL |
| Veredicto llega al consumidor persistido | LF-PE-STEP70-CHAT-VERDICT-NOT-PERSISTED-20261031-001 | Chat no acredita registro |
| 11/11 no sustituye negativos | LF-PE-STEP70-RUN-CLOSED-EKB-ENFORCEMENT-OPEN-20261031-005 | Inválidos deben fallar |
| Snapshot con currentness y autoridad | IG-M107-G-CURATOR-SQL-FASTPATH-041 | Stale/tenant/run/SHA y fallback |
| Medir sin extrapolar caché hipotética | IG-M107-G-NATIVE-SNAPSHOT-DIGEST-COST-040 | Igualdad y métricas comparables |
| Reuso no cruza propuestas | IG-M107-D-PROPOSAL-GRAPH-RECEIPT-036 | Dos consumidores; objeto distinto falla |
| Conteo real de tests | PE10_C6_DECLARED_PLANNER_TEST_COUNT_DRIFT_V1 | Derivar del inventario ejecutado |
| Parser/plan SQL | PE10_C6_SQL_SCRIPT_PREFLIGHT_NO_PARSE_V1 | EXPLAIN aislado y frescura |
| Gate corresponde al trabajo | IG-M1013-REPOSITORY-REPAIR-POLICY-054 | Readback no hereda mutación |

Añadir suficiencia, comentario accionable, RLS, concurrencia, estados,
excepciones, retries, N+1, tipos/nulos/versiones/errores. NOT_APPLICABLE exige
motivo. Cada nueva casuística demostrada se añade como candidato trazable.

Aprendizaje candidato del propio piloto, aún sin registrar en EKB:
LF-DEEP-AUDIT-CI-SHALLOW-BASELINE-001. Verificar que el checkout contenga el
commit fuente, no solo el archivo; recuperar únicamente ese commit si falta.
Evidencia en references/ekb_candidate_ci_provenance.json y regresión real de
checkout superficial en evals/test_ci_provenance.py. No relajar el validador.
