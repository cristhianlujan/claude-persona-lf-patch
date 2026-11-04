# PG-05 — Validación de cadena desde PG-04 y negativos (2026-11-04)

## Base exacta
Rama: `lf/pg05-source-positive-negative-chain-20261104`.
Parte del **HEAD `44b95d89e173ccc4b5e5b0632b9439f7a2f29e4e` de PR #3534**, cuyo bridge PG-03_C8→PG-04 pasó 6/6 y PG-04 pasó 146/146 según verificación independiente de Claude.

Los seis productores C1, C2, C3, C4, C5 y PG05→PG06 se **portaron íntegros, sin reescritura** desde PR #3528. El PR nuevo solo debe contener PG-05, apilado sobre #3534. No ejecutar ramas sobre `main` ni fusionar.

## Test exact-HEAD: productores reales, no mocks vacíos
`tests/test_pg05_chain_c1_c5_v1.py` incluye 13 casos. `pg04_real_exit()` importa `test_pg04_remaining_edges_v1.exit_fixture` y llama al productor **`assemble_pg04_exit_candidate` real** con target sintético explícito; después ejecuta:
- `prepare_pg05_c1`: nombre de rama planificado, no creado
- `prepare_pg05_c2`: resoluciones L3/repo paths explícitas, shared contracts solo lectura
- `prepare_pg05_c3`: colisiones write/write, dependencias y solicitud de lock, no lock adquirido
- `prepare_pg05_c4`: diagnóstico de diff por solución, sin permiso de escritura
- `prepare_pg05_assurance_request`: solicitud a revisor existente, no juez nuevo
- `assemble_pg05_pg06_candidate`: contrato de salida al siguiente PG, sin dispatch

Cobertura del test:
1. Positivo sintético de cadena completa C1→C5→salida PG-06 y digests enlazados.
2. C1 sin target: `BLOCKED`; C1 autoridad inyectada con digest recalculado: BLOCK.
3. C2 path traversal: BLOCK; C2 autoridad inyectada: BLOCK.
4. C3 autoridad inyectada: BLOCK; choque de path exacto entre soluciones: conflicto reportado y sin locks.
5. C4 path fuera del write-scope: bloquea solo la solución afectada; C4 autoridad inyectada: BLOCK.
6. C5 digest de manifiesto distinto: BLOCK; C5 autoridad inyectada: BLOCK.
7. Salida: recibo de revisión falso y autoridad falsa: BLOCK.

**Importante:** el caso positivo produce `CANDIDATE_NOT_ADMITTED` y nunca prueba la creación real de ramas, el lock real, un diff aplicado ni una revisión independiente.

## Comandos de Claude (checkout exacto de PR nuevo)
```bash
ROOT=sandbox/lf_contract_gate_test/programming_agent_four_stage
python3 -m py_compile "$ROOT"/pg05_target_binding_candidate/tools/*.py "$ROOT"/pg05_target_binding_candidate/tests/*.py
cd "$ROOT"/pg05_target_binding_candidate
python3 -m unittest discover -s tests -p 'test_pg05_chain_c1_c5_v1.py' -v
cd ../pg04_semantic_partition_candidate
python3 -m pytest -q tests
```

Informar salida literal, HEAD exacto, errores y cualquier modificación posterior. Revisión independiente sobre la base real del PR #3534.

## Criterios de calificación
- Todos los positivos y negativos pasan en un mismo HEAD exacto.
- La fuente exacta del PG-04 exit se consume sin reconstrucción manual de su salida.
- Un `production_authority:true` de cualquier tramo se rechaza, incluso recomputando digest.
- C1–C5 no requieren permisos productivos ni emiten `branch_created`, `locks_acquired`, `write_allowed`, `handoff_allowed` verdaderos.
- Supabase y el estado oficial permanecen sin alterar.

**Estado antes de ejecución:** `SOURCE_PORTED / TESTS_WRITTEN / NOT_YET_EXECUTED / OFFICIAL_PENDING`.
**Siguiente luego de calificar PG-05:** PG-06 debe traer **la versión corregida de C4 del PR #3528, commit `bfd118c6705eecefbab952ab22b579909165806e`**, nunca la versión antigua.
