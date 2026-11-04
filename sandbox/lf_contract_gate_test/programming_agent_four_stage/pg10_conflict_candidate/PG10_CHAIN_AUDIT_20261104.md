# PG-10 — Auditoría independiente de conflictos, precedencia y decisiones (2026-11-04)

## Identidad y fuentes originales
- Base exacta: PR #3540, `2fa6b19b60a324aa0abe4197014250dac849331c`; PG-09 C1–C4 calificado por Claude 14/14 en modo técnico declarativo.
- Rama: `lf/pg10-conflict-decision-chain-20261104`, apilada sobre #3540. **Solo PG-10**.
- Cinco módulos C1–C5 originales portados **sin modificaciones** desde el PR #3528. Cinco notas históricas conservadas.
- Módulo nuevo y aislado `tools/pg10_decision_lineage_dedup_candidate_v1.py`: recibe `PG08_C6_C7_C8_FINAL_FEEDBACK_CANDIDATE_V1` y `PG09_C4_TYPED_ESCALATION_CANDIDATE_V1`, más el routing real PG-10_C3; **no reescribe sus contratos**, conserva los digest y rechaza preguntas duplicadas.
- `tests/test_pg10_decision_chain_v1.py`: 15 casos nuevos preparados.

## Camino positivo C1–C5, desde los productores existentes
`make_chain` de PG-09 llama a su vez a PG-08, PG-07 y predecesores. Se reutiliza:
```
PG-08 final (SHA)  ─────────────┐
PG-09_C4 (SHA) -> PG-10_C1 -> C2 -> C3 -> C4 -> C5
PG-07_C5 (SHA) -> PG-10_C1       └-> guarda de deduplicación + linaje
```
El fixture contiene conflicto real **declarado** `REQUIREMENT_VS_STANDARD` entre referencias de requisito y estándar. C2 elige `PRESERVE_EXISTING` sin autoridad. C3 clasifica una pregunta humana nueva, C4 construye el packet `PROGRAMMING_HUMAN_DECISION_PACKET_V1` con opciones, recomendación, riesgo, scopes disjuntos y condición de reanudación; C5 valida solo la **estructura** de 12 escenarios. **No se envían preguntas, no se verifica una decisión histórica ni se reanuda ejecución**.

## Pruebas específicas solicitadas por Claude

### C2 — Nunca prevalece una regla inferior
`test_c2_lower_priority_override_higher_priority_rejected` intenta `OVERRIDE_HIGHER_PRIORITY` como acción de conflicto. El contrato fuente permite solamente `PRESERVE_EXISTING`, `DEFER_PRECEDENCE`, `RETURN_PHASE1_A3` o `QUERY_EXACT_MISSING_EVIDENCE` según el tipo; la acción indebida debe producir `PG10_C2_ACTION_INVALID`. Adicionalmente se comprueba:
- `RENAME` de legado sin aprobación: `rename_allowed=false`, sin ejecutarlo;
- `migration_approval_authenticated=true` introducido por el invocador: rechazo `UNVERIFIED_APPROVAL_CLAIM`.

**Limitación:** esto es una prohibición determinista de acción, no una lectura autenticada de toda la jerarquía de precedencia 1.5. Esa integración depende de la fuente real y del calificador.

### C3 — No volver a preguntar lo ya respondido
El productor original C3 con `prior_decision_ref` decide `CHECK_PRIOR_DECISION_CURRENTNESS_BEFORE_QUESTION`, sin enviar pregunta. El nuevo guard recibe registros **caller-supplied** del ledger:
- Si el mismo `(solution_id, conflict_id, decision_question_key)` está `RESOLVED` e intentan proponerlo de nuevo → `PG10_DUPLICATE_ANSWERED_QUESTION`.
- Si está `STALE` o `PENDING` → `PG10_PRIOR_DECISION_REQUIRES_CURRENTNESS_CHECK`.
- Si existe `RESOLVED` sin pregunta nueva, se produce solo `reuse_decision_candidate=true`; no se autentica ni ejecuta.
- Si la ruta es `TECHNICAL_DECISION` y proponen pregunta humana → `PG10_NOT_A_NEW_HUMAN_QUESTION`.
- C4 tampoco puede montar paquete de preguntas para rutas con decisión previa.
**Limitación:** no hay fetch real del ledger ni evaluación confiable de vigencia. En modo productivo el lookup y control de unicidad deben estar atestados/transaccionales.

### Conexión solicitada PG-08/PG-09
El agregado nuevo requiere `candidate_sha256` genuinamente consistente desde `pg08_final`, `pg09_c4` y `pg10_c3`, conserva `source_pg08_final_sha256` y `source_pg09_c4_sha256`; no significa certificar un build. Compara el `run_ref` de PG-09_C4 y PG-10_C3. Esto **atiende trazabilidad declarativa**; no atribuye huellas reales de ejecución de herramientas.

## Más negativos
1. C1: conflicto sin ambas fuentes y autoridad falsa re-hasheada.
2. C2: override de menor jerarquía, renombre no aprobado y afirmación de aprobación falsa.
3. C3: pregunta duplicada respondida, decisión obsoleta, paquete humano para decisión previa y pregunta humana para decisión técnica.
4. C4: scopes afectados y READY no deben solaparse.
5. C5: matriz obligatoria de doce escenarios, ningún recibo de ejecución fabricado y ningún escenario omitido.

## Pruebas a ejecutar en HEAD exacto; salida literal
```bash
ROOT=sandbox/lf_contract_gate_test/programming_agent_four_stage
python3 -m py_compile "$ROOT"/pg10_conflict_candidate/tools/*.py "$ROOT"/pg10_conflict_candidate/tests/*.py

cd "$ROOT"/pg10_conflict_candidate
python3 -m unittest discover -s tests -p 'test_pg10_decision_chain_v1.py' -v

cd ../pg09_iteration_candidate
python3 -m unittest discover -s tests -p 'test_pg09_iteration_chain_v1.py' -v
cd ../pg08_build_candidate
python3 -m unittest discover -s tests -p 'test_pg08_full_chain_v1.py' -v
cd ../pg07_worker_candidate
python3 -m unittest discover -s tests -p 'test_pg07_c1_c6_chain_v1.py' -v
cd ../pg06_preflight_candidate
python3 -m unittest discover -s tests -p 'test_pg06_c1_c5_chain_v1.py' -v
cd ../pg05_target_binding_candidate
python3 -m unittest discover -s tests -p 'test_pg05_chain_c1_c5_v1.py' -v
cd ../pg04_semantic_partition_candidate
python3 -m pytest -q tests
```

El autor no ejecutó estas pruebas en un checkout exacto; el acceso Git desde el entorno de ejecución local no resolvió el host y no se infiere PASS a partir de GitHub. **Estado previo a calificación: SOURCE_PORTED / TESTS_WRITTEN / NOT_TESTED / OFFICIAL_PENDING**.

## Límites, gobernanza y entrega
C5 contiene exclusivamente **expectativas de 12 negativos**, no 12 ejecuciones con evidencias. No se escribió en Supabase ni se tocó Análisis, `main`, Worker real o Testing. El PR queda draft, sin merge, y PG-11 permanece fuera de alcance hasta calificación independiente.
