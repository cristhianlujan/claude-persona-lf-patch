# D-05: revisión independiente y propuesta de PR (NO PUBLICAR)

## Preguntas al revisor Claude

1. ¿El validador acepta únicamente `REQUIRES` del plan y rechaza claves extra, nulos, tipos erróneos y estructuras adversariales profundas? Estudiar `load_inventory` y fijar casos negativos.
2. ¿Hay algún camino que cierre operativamente por recibos sintéticos o simples cadenas `provider_ref`/`provenance`? El core bloquea `operational=True`, pero falta adaptador con autoridad real.
3. ¿`eligible` y `transition` verifican exact-run, HEAD, catálogo, contrato y source pins también al reanudar? Revisar cierre derivado y la inmutabilidad.
4. ¿`NOT_APPLICABLE_JUSTIFIED` sólo puede acreditarse con decisión y recibo externo tipado? Hoy se bloquea el cierre N/A.
5. ¿`INVALIDATED` invalida eficazmente descendientes y elimina la acreditación efectiva de recibos previos? Hoy es cálculo puro, sin store.
6. ¿La semántica de `COMPLETE` del Simple Executor debe mapearse a resultado intermedio y nunca a closure sin verifier?
7. ¿Qué pruebas de tipado malicioso faltan (bool/int, JSON/Unicode, duplicados, exceso de profundidad, keys desconocidas)?
8. ¿Cuál es la familia de clasificación PASE apropiada para estas rutas nuevas? No inventar una familia.

## Matriz de integración (solo diseño)

| Subsistema | Entrada | Salida / identidad | Control y riesgo | Futuro adaptador |
|---|---|---|---|---|
| Simple Executor V1 | unidad PG, checkpoint REQUIRES | unidad COMPLETE y receipts fresh-run | COMPLETE != PIP closure; no reutilizar PASS | mapper de estados read-only |
| Neutral Step Recorder | ejecución/etapa | recibo neutral, hash | identidad exacta, sin duplicar recorder | lector/verificador |
| Evidence Ledger V1 | evidencia y provider | receipt/hash/verification_state | no confiar en claims locales | evidence verifier read-only |
| Worker | tarea puntual y límites | resultado tarea | no dar autoridad de cierre | task envelope |
| Runner | HEAD, EKB, CI, tests | PASS/FAIL/BLOCKED + fingerprint | no importar PASS histórico | result verifier |
| Router | acción resoluble ACT-0001 | ruta/autoridad | cero escritura desde núcleo | gate externo |
| PASE | changeset y HEAD | check requerido | plan exact-head no corrido | CI gate |
| Merge Train | PR con checks requeridos | merge autorizado | jamás merge directo | publicación posterior |
| Testing | PG14 handoff | recibos testing | no inferir cierre PG14 desde unidad | boundary adapter |

## PR propuesto (sólo borrador)

- Repo: `cristhianlujan/claude-persona-lf-patch`.
- Base: `main` actualizado al crear la futura rama, NO la rama de #3220. Mantener inventario como input externo candidate.
- Rama futura: `lf/pip1-core-isolated-d05`.
- Commit sugerido: `feat(programming): add isolated PIP-1 contract DAG and closure guards`.
- Título: `[DRAFT] PIP-1 Carril D: núcleo puro contract/DAG/transitions (sin activación)`.
- Descripción: D01-D05 sólo lógica pura Python, pruebas unitarias, receipt sintético y cierre operacional explícitamente bloqueado. Declarar que inventario #3220 NO APPROVED, no PG00, no runtime, no DB; exigir pruebas reales, clasificación, PASE y revisión independiente antes de GO.
- Rutas propuestas (no usadas aún en LF): `sandbox/lf_contract_gate_test/pip1_core/{pip1_core/,tests/,verify_exact_inventory.py,README.md}` con documentación específica del lote. Confirmar admisión de rutas antes del primer commit con el emisor PASE en checkout LF; si requiere manifest debe pertenecer al primer commit.
- Checks: unitarias, exact blob verification, mutaciones reales, CLI, diff check, `emit_ci_execution_plan_v2.py` sobre commit exacto y PASE requerido en PR.
- Bloqueantes: loader Python aún no probado con bytes reales, clasificación paths PASE, PASE NOT_RUN, revisión independiente, aprobación owner de eventual publicación y de N/A externo.
- Acción remota: NINGUNA. No push / no PR.
