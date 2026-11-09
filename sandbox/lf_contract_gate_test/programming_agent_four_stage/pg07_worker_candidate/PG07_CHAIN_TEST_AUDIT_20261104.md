# LF PG-07 — Cadena Worker candidata, auditoría independiente (04/11/2026)

## Base exacta y procedencia
- Base: PR #3536, HEAD `0eccf3e34aae34d225f0c74696708744abca8098`, PG-06 calificado por Claude con 15/15 pruebas.
- Rama: `lf/pg07-c1-c6-worker-chain-20261104`, PR draft exclusivo de PG-07.
- C1–C6: fuentes idénticas a las originales en #3528, conservadas sin nueva lógica de Worker. Seis notas de los checkpoints preservadas.
- Test nuevo `tests/test_pg07_c1_c6_chain_v1.py`: 15 casos, incluye positivo sintético desde la **ejecución efectiva del productor real PG-06_C5**, usando `make_chain()` y salida `pg06_c5`.

## Qué demuestra el positivo
C1 declara run/model/Worker 0.8 y precios **referenciales**, sin tokens consumidos. C2 usa un spec Worker v2 sintético que NO incluye oráculo oculto; el oráculo solo se referencia para verificador. C3 prepara selección material de contexto y límites del perfil del modelo (sin ejecutar `CONTEXT_BUDGET_GOVERNANCE`). C4 incorpora `STD-API-06` y ejemplos OK/NO declarados, sin ejecutar formateadores. C5 no modifica objetivo/scope en silencio ni ejecuta PG-10. C6 prepara manifiesto de lote con diff/usage/recibos **reportados por un fixture**, manteniendo `receipt_sealed=false`, `worker_invoked=false`, `receipt_digest_authenticated=false`, `production_authority=false`.

## Negativos
- C1 rechaza `cost_calculated:true` en run declarativo y `worker_invoked:true`/autoridad en el C5 upstream, aun recalculando digest.
- C2 rechaza oráculo oculto en worker-visible payload y autoridad inyectada.
- C3 ante presupuesto insuficiente devuelve diagnóstico `BLOCK_CONTEXT_BUDGET` sin truncar material; autoridad inyectada bloqueada.
- C4 material STD faltante o autoridad inyectada bloqueados.
- C5 cambio de objetivo no declarado o autoridad inyectada bloqueados.
- C6 rechaza `worker_invoked:true`, `cost_calculated:true` o autoridad en datos declarativos: **reportar costo no es demostrar costo ejecutado, y referencia de recibo no es recibo autenticado**.

## Comandos para Claude — HEAD exacto, salida literal obligatoria
```bash
ROOT=sandbox/lf_contract_gate_test/programming_agent_four_stage
python3 -m py_compile "$ROOT"/pg07_worker_candidate/tools/*.py "$ROOT"/pg07_worker_candidate/tests/*.py
cd "$ROOT"/pg07_worker_candidate
python3 -m unittest discover -s tests -p 'test_pg07_c1_c6_chain_v1.py' -v
cd ../pg06_preflight_candidate
python3 -m unittest discover -s tests -p 'test_pg06_c1_c5_chain_v1.py' -v
cd ../pg05_target_binding_candidate
python3 -m unittest discover -s tests -p 'test_pg05_chain_c1_c5_v1.py' -v
cd ../pg04_semantic_partition_candidate
python3 -m pytest -q tests
```

## Dictamen antes de ejecutar
**SOURCE_PORTED / TESTS_WRITTEN / NOT_TESTED / OFFICIAL_PENDING**. No se han ejecutado las pruebas nuevas en este turno: el código publicado exige verificación real antes de `TECHNICAL_PASS`.

En modo técnico diferimos invocación al Worker real, precios verificados, autenticación de receipts, autoridad de writer y ledger, dispatch por carriles y revisión independiente. Los nombres de funciones `fn_agent_task_worker_spec`, `fn_agent_task_execution_bundle`, `CONTEXT_BUDGET_GOVERNANCE` indican dependencias, no sustitutos.

No tocar Análisis, Supabase, `main`, Worker productivo ni Testing; no avanzar PG-08 antes de calificar PG-07.
