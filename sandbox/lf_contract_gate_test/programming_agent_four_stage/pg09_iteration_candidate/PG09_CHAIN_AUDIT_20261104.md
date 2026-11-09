# PG-09 — Gobernanza de iteraciones: auditoría exact-HEAD (04/11/2026)

## Base y procedencia

- Rama: `lf/pg09-iteration-governance-chain-20261104`.
- Base exacta: PR #3539, `ec516d2abbc225a5e2bdcaf48718b1719a34be8b`, calificado por Claude con 14/14 pruebas en modo declarativo.
- C1–C5: los **cinco productores originales sin reescritura** desde #3528, más seis documentos de la etapa.
- `tests/test_pg09_iteration_chain_v1.py`: **14 casos nuevos** con invocaciones a productores reales. La ejecución y el resultado siguen **POR_VERIFICAR**.
- Supabase oficial: PG-09_C1–C5 estaban `PENDING`; no hay escritura de estado.

## Qué cubren los tests

### C1 — Umbrales exactos y costos declarados
Fixture de presupuesto total USD 100.00 y lote USD 100.00; suma de costos reportados para dos soluciones:
- `79.99 / 100 = 79,99 %` → `REPORTED_WITHIN_BUDGET_UNVERIFIED`.
- `80.00 / 100 = 80 %` → `WARN_80_PERCENT`.
- `100.00 / 100 = 100 %` → `REQUIRES_DECISION`.
- Uso con costo `null` → decisión requerida, nunca cero gratuito.
- Inyección `production_authority=true` en PG-07_C5 incluso con huella recalculada → rechazo.

El cálculo comprueba la lógica exacta de `Decimal` sobre **costos declarados**, no autenticación de consumo ni costo real de un modelo.

### C2 — Convergencia
La cadena utiliza la salida del **productor real** de PG-07_C5. Se exige continuidad del digest y rechazo cuando la huella de C1 contiene un origen incompatible. En los fixtures de cadena sin iteraciones C2 produce diagnóstico sin afirmar progreso de ejecuciones reales. Las pruebas de convergencia de múltiples iteraciones con estancamiento todavía deben ampliarse si Claude las considera requisito de GO.

### C3 — Protección de calidad
Para probar una iteración no vacía se llama de nuevo al **productor real** `prepare_pg07_c5` sobre C2–C4 de PG-07 usando `baseline_bindings` canonizados del Worker spec. C2 de PG-09 procesa la misma iteración y C3 recibe cambios declarados en el diff:
- `TEST_DELETE` con `after_sha256=null` → `BLOCK`, no permite `retry`.
- `RULE_DISABLE` → `BLOCK`.
- `TEST_DELETE` contradictorio con `after_sha256` no nulo → rechazo de esquema.
- Las rutas y hashes son de fixture y no prueban inspección de diff Git real (`real_diff_scanned=false`).

### C4 — Escalamiento
Se invoca C4 con productos C1/C2/C3 reales y contexto de owner declarativo. Se prueba rechazo de run ajeno y, con 100 %, `RETURN` con `BUDGET_DECISION`. No hay envío real al owner ni autorización.

### C5 — Matriz adversarial
Se ejercita el receptor de los **nueve escenarios obligatorios**. A diferencia de la cadena positiva C1–C4, sus nueve filas son **envolturas sintéticas de una solución** derivadas de outputs de C1/C4 y ajustadas para cubrir los estados requeridos; **no son nueve ejecuciones auténticas del flujo C1–C4**. Verifica `required_case_count=9`, estructura coherente, rechazo de escenario ausente y autoridad fabricada; mantiene `executed_test_count=0` y `independent_verdict_issued=false`.

Para afirmar GO más fuerte en C5, crear harness adversarial con nueve escenarios que nazcan de los productores reales, correrlos y autenticar recibos de ejecución. No convertir la matriz en falso PASS.

## Comandos solicitados a Claude

```bash
ROOT=sandbox/lf_contract_gate_test/programming_agent_four_stage
python3 -m py_compile "$ROOT"/pg09_iteration_candidate/tools/*.py "$ROOT"/pg09_iteration_candidate/tests/*.py

cd "$ROOT"/pg09_iteration_candidate
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

Claude debe comunicar salida literal, HEAD completo, trazabilidad del fixture positivo y de los negativos, y corregir cualquier fallo antes de calificar. El autor **no ha ejecutado** estos comandos sobre el HEAD, por lo que el estado es `SOURCE_PORTED / TESTS_WRITTEN / NOT_TESTED`.

## No-autoridad

No se llama a modelos, Worker ni precios reales, no se emiten costos autenticados, no se ejecutan iteraciones ni se editan tests o reglas de repositorios reales, no se habilitan reintentos, no se cambian Analysis, Supabase, `main`, ni Testing. No avanzar PG-10 antes de la auditoría independiente.
