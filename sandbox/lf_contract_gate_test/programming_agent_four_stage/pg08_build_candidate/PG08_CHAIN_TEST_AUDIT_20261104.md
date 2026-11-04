# LF PG-08 — Auditoría de build/calidad C1–C8 y consolidado de recibos (04/11/2026)

## 1. Control de versión
- Base exacta de PR #3537: `715046cfe6030b17878331193d4115696fafcadd`.
- Rama PG-08: `lf/pg08-build-quality-chain-20261104`.
- Ocho módulos C1–C8 originales portados **sin modificar** desde PR #3528, más nueve documentos históricos.
- Nuevo módulo **acotado a C6**: `tools/pg08_c6_final_receipts_candidate_v1.py` para consolidación tardía y rechazo de fingerprints contradictorios.
- Nuevo test: `tests/test_pg08_full_chain_v1.py` (14 pruebas preparadas; **no se atribuye PASS sin ejecución**).

## 2. Dependencias reales y por qué C6 requiere dos pasos
```
PG-07_C6 real
   -> PG-08_C1(build) -> C2(format/lint vs PG-06_C4) -> C3(typecheck)
   -> C4(unit/smoke/Flyway) -> C5(contracts)
   -> PG-08_C6 (recibos fuente C1–C5)
   -> PG-08_C7 (arquitectura, consume C6)
   -> PG-08_C8 (IaC/healthchecks, consume C7)
   -> PG-08_C6_C7_C8_FINAL_FEEDBACK_CANDIDATE_V1
```
El C6 original **no puede consumir C7/C8 antes de producirlos**, porque C7 ya requiere C6 y C8 requiere C7. Para cumplir la obligación de incluir evidencia de C7/C8 **sin introducir un ciclo**, se prepara un agregado final posterior a C8. No cambia ninguna firma original ni otorga autoridad.

La nueva función `consolidate_pg08_c6_c7_c8` exige identidad exacta de repo, base, candidato, diff, executor y conjunto de soluciones; recalcula los SHA de C6/C7/C8, valida los enlaces, y añade `PG-08_C7` y `PG-08_C8` al listado final. La función conserva los recibos **reportados**; `receipt_authenticated=false`, `tool_execution_verified=false`, `final_verdict_issued=false`. El test positivo adicional usa arquitectura ArchUnit y tres comandos declarados de contenedores con recibos referenciados: no solo `NOT_APPLICABLE`.

## 3. Tres obligaciones de auditoría de Claude
1. **C6 final incluye C7 y C8:** positivo y negativos de SHA/coverage; inspeccionar `feedback_checks` y la identidad de sus recibos reportados.
2. **PASS con fingerprints incompatibles:** `reject_falsified_pass_fingerprint` recibe comando, stdout, stderr y códigos de salida de una observación provista por el invocador, recomputa los tres SHA-256 y bloquea si cualquiera no coincide con el reporte, o si `exit_code != 0`. *No ejecuta el comando ni autentica al observador.* Se prueban modificaciones independientes del comando, stdout, stderr y contradicción entre cuerpo/huella.
3. **C8 secuencia de healthchecks:** rechaza `CONTAINER_HEALTHCHECK:PASS` sin `DOCKER_COMPOSE_UP` aplicable o si Compose declara `FAIL`. El caso positivo declara BUILD→COMPOSE→HEALTHCHECK PASS en un target local y permanece sin autoridad.

## 4. Resto de los negativos de la prueba
- C1: autoridad `production_authority=true` inyectada en manifiesto real PG-07_C6, incluso con digest recalculado.
- C2: identidad de candidate head distinta.
- C3: autoridad falsificada en el upstream.
- C4: secuencia Flyway APPLY/ROLLBACK/REAPPLY fuera de orden.
- C5: contrato `NOT_APPLICABLE` con `result=PASS` fraudulento.
- C6: `pg08_c5_pass=true` falsificado.
- C7: `receipts_authenticated=true` inyectado.
- C8: healthchecks inconsistentes.
- Consolidado final: enlace digest de C8→C7 falsificado.

## 5. Comandos de revisión exact-HEAD (ejecución pendiente)
```bash
ROOT=sandbox/lf_contract_gate_test/programming_agent_four_stage
python3 -m py_compile "$ROOT"/pg08_build_candidate/tools/*.py "$ROOT"/pg08_build_candidate/tests/*.py
cd "$ROOT"/pg08_build_candidate
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
Claude debe mostrar stdout/tracebacks y HEAD completo. No basta el estado de GitHub ni el código escrito.

## 6. Lo que NO demuestra
Los inputs de C1-C8 son **fixtures sintéticos** y los checks reportados, no ejecuciones de Maven/pnpm/tsc/mypy/Flyway/Spectral/Terraform/Docker. Las decisiones de `NOT_APPLICABLE` tampoco están autenticadas. El agregado C6 solo construye feedback; **no es PASS de calidad, no sella un recibo, no ejecuta CI, no activa Worker ni Testing**. La verificación de fingerprint debe recibir observaciones de un runner independiente confiable antes de poder servir como evidencia operativa.

**Estado inicial**: SOURCE_PORTED / TESTS_WRITTEN / NOT_TESTED / OFFICIAL_PENDING.

**No tocar** Analysis, Supabase, main, Worker productivo ni Testing. Mantener el PR draft y no abrir PG-09 hasta revisión independiente.
