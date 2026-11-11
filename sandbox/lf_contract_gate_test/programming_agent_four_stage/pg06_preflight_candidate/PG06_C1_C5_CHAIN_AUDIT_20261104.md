# PG-06 — Cadena C1–C5 y verificación independiente (04/11/2026)

## Base, autoría y alcance
La rama `lf/pg06-c1-c5-chain-positive-20261104` se crea directamente desde PR #3535, HEAD exacto `417a1e0ee6afe51ba2409d6f081c7714d0ec8d76`. Por lo tanto, hereda la prueba de PG-04→PG-05 y los artefactos C1–C5. Se trasladaron **sin alterar** C1, C2, C3 y C5 desde PR #3528. **C4 se tomó exclusivamente de** `bfd118c6705eecefbab952ab22b579909165806e`, blob `1d4e0709b26d33c95693cba8fe1808d775a1ef08` (corrige el `SyntaxError` original). Cinco documentos anteriores se conservaron.

## Test nuevo
`tests/test_pg06_c1_c5_chain_v1.py` contiene **15 pruebas**; importa `build_chain()` de la prueba existente de PG-05 y vuelve a invocar `assemble_pg05_pg06_candidate` de forma efectiva. No falsifica directamente el sobre PG-05.

Positivo fuente: PG-05 → C1 reutilización de decisión PG-01 declarada → C2 selección de toolchain y observación de entorno declaradas → C3 frentes A7 sintéticos y plan de reversión explícito → C4 **primera invocación con valores válidos declarados** de baseline BUILD y LINT por solución → C5 solicitud a `INDEPENDENT_ASSURANCE`. Se comprueban `candidate_sha256` encadenados, igualdad de cobertura y flags de autoridad en falso. Son **observaciones sintéticas**, NO ejecución real de build/lint, ni lectura del catálogo/A7 real, ni recibos auténticos.

Negativos: rebind en mitad de ejecución, inyección `production_authority=true` con re-hash en C1, C2, C3, C4 y C5; CURRENTNESS stale, versión de toolchain distinta, frente A7 omitido, C4 PASS con exit_code!=0, C4 sin LINT, manifiesto corrupto. C5 nunca invoca revisor ni crea recibo.

## Evidencias a ejecutar en el HEAD exacto
```bash
ROOT=sandbox/lf_contract_gate_test/programming_agent_four_stage
python3 -m py_compile "$ROOT"/pg06_preflight_candidate/tools/*.py "$ROOT"/pg06_preflight_candidate/tests/*.py

cd "$ROOT"/pg06_preflight_candidate
python3 -m unittest discover -s tests -p 'test_pg06_c1_c5_chain_v1.py' -v

cd ../pg05_target_binding_candidate
python3 -m unittest discover -s tests -p 'test_pg05_chain_c1_c5_v1.py' -v

cd ../pg04_semantic_partition_candidate
python3 -m pytest -q tests
```

Verificar de forma independiente el conteo, los casos positivos y los negativos, el blob exacto de C4 y los HEAD exactos. Si aparece algún fallo real, **no atribuir TECHNICAL_PASS** y devolver traceback literal. El autor no puede atribuir PASS por añadir archivos.

## Bloqueos que siguen diferidos
Autoridad, admisión PG-05 real, decisión PG-01 verificada, toolchain ejecutada, baseline build/lint real, material A7 auténtico, autorización de writer, revisión independiente y recibo. Ningún componente despliega, escribe, reserva lock o eleva `handoff_allowed`.

**Estado de partida:** SOURCE_PORTED / TESTS_WRITTEN / NOT_TESTED / OFFICIAL_PENDING.
