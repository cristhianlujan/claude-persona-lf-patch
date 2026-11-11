# PG-03_C8 → PG-04: integración candidata sobre #3527 (2026-11-04)

## Base y alcance
- Base exacta: `b1957859d1872574417a345cf9b307a1500d9167` — PR #3527, PG-01–PG-03.
- PG-04: se trasladaron los **34 archivos originales** de #3528, sin sobrescribirlos, con blobs conservados.
- Contrato de partición reutilizado de PR #1912: `wave1_boundary_contracts/programming_solution_partition_contract_v1.json`, blob `54ea02669c2f9ad199ac6fde154ec5dd30d6decb`.
- Adaptador NUEVO Y ACOTADO: `pg04_semantic_partition_candidate/tools/pg03_pg04_exact_handoff_bridge_v1.py`.
- Prueba NUEVA: `pg04_semantic_partition_candidate/tests/test_pg03_pg04_exact_handoff_bridge_v1.py`.

## Cambio funcional
`partition_from_pg03_c8` recibe necesariamente el **sobre concreto** `PG03_C8_PG04_HANDOFF_CANDIDATE_V1`, devuelto por `prepare_pg04_handoff` en `pg03_strategy_candidate/pg03_handoff_boundary_v1.py`. Verifica digest canónico, no-autoridad, identidad de estrategia, contrato, cobertura de requisitos/aceptaciones y conjunto de soluciones/dependencias. Solo entonces llama al **particionador existente**, sin crear otro motor.

Por el momento se exige igualdad de los grupos de obligaciones de PG-03 y PG-04. Es deliberadamente conservador: no se puede cambiar silenciosamente la partición entre ambos. Reparticiones justificadas deberán tener un contrato de refinamiento propio.

El handoff C8 no contiene por sí solo todos los átomos de A9 ni outcome_registry: esos insumos siguen siendo declarados por el invocador. Un enlace estructural positivo no acredita autenticidad de A9.

## Test a ejecutar por Claude
```bash
cd sandbox/lf_contract_gate_test/programming_agent_four_stage/pg04_semantic_partition_candidate
python3 -m unittest discover -s tests -p 'test_pg03_pg04_exact_handoff_bridge_v1.py' -v
python3 -m pytest -q tests
```
Comprobar caso positivo con productor real C8, corrupción del digest, identidad de estrategia distinta, falta de requisito, autoridad falsa y contrato de handoff incorrecto. NO se atribuye PASS antes de ejecutar y leer salida en HEAD exacto.

## Estado
`SOURCE_PORTED / BRIDGE_WRITTEN / NOT_TESTED / NO_AUTHORITY`. Esta rama **no rebasa** #3528: efectúa extracción limpia de PG-04 a partir de #3527. #3528 conserva PG-05–PG-14 y el fix PG-06_C4 para refactor posterior. Sin Supabase writes, merge, Worker real, despliegue ni Testing.
