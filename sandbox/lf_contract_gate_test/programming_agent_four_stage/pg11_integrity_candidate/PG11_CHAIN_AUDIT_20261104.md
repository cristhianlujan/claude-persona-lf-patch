# LF PG-11 — Mandato de revisión independiente exact-HEAD (2026-11-04)

## Procedencia y alcance
- Base: PR #3541, HEAD exacto `e6bc017fc45b1f587ae80ace5c0b9467bd804b83`, previamente calificado por Claude con 15/15.
- Rama: `lf/pg11-integrity-hunk-review-20261104`, solo código candidato de PG-11.
- **Cinco productores C1–C5 originales se copiaron sin alterar sus blobs desde #3528**, y se preservaron cinco informes preexistentes.
- Nuevo módulo de extensión no autoritativa: `tools/pg11_integrity_extension_candidate_v1.py`.
- Nuevas pruebas: `tests/test_pg11_integrity_chain_v1.py`, **14 tests escritos, no ejecutados sobre el checkout**.

## Productores reales y limitaciones
Los tests llaman a `prepare_pg11_c1`, `prepare_pg11_c2`, `prepare_pg11_c3`, `prepare_pg11_c4` y `prepare_pg11_c5` en secuencia. Los fixtures describen **un diff sintético**, una referencia de glosario, una supresión declarada, un waiver declarado, un requisito/lote y un revisor. No se finge haber leído un diff Git real, el catálogo, el ledger de waivers ni el directorio de identidad.

Este test de PG-11 **no recibe todavía el sobre real PG-10_C5**: los productores originales PG-11 empiezan por la identidad de un diff declarado, no por PG-10. Es un hueco de conexión que debe examinarse antes de declarar cadena PG-01→PG-11 íntegramente enlazada; no hay que inventar una fuente PG-10 inexistente.

## Tres casos obligatorios pedidos por Claude

### C4: Trazabilidad por hunk, no solo por archivo
`prepare_pg11_hunk_trace` recibe salida real de C4, manifest de hunks y enlaces explícitos `hunk_id,requirement_ref,batch_ref,scope_ref,evidence_ref`. Verifica:
- manifest único y bien formado, rango y hash declarado de cada hunk;
- cobertura exacta de todas las rutas modificadas;
- cada hunk tiene al menos un enlace autorizado por C4;
- rechazo `PG11_HUNK_ORPHAN` si se omite el vínculo del segundo hunk;
- rechazo `PG11_HUNK_LINK_NOT_AUTHORIZED` si se referencia un requisito ajeno;
- rechazo de digest inválido y autoridad inyectada con digest recalculado.

**Limitación:** una lista de hunks puede omitir un hunk real si la fuente Git no se autentica. `git_diff_readback_verified=false` y `hunk_coverage_verified=false`. Para aprobación final, vincular un extractor read-only del diff exacto.

### C3: Waiver vencido o no correspondiente a STD-GEN-05
`reject_invalid_waiver` exige `standard_ref=STD-GEN-05`, `approval_status_reported=APPROVED`, scope y suppression_id correctos y declaración consistente con C3. Rechaza `PG11_WAIVER_EXPIRED` y `PG11_WAIVER_WRONG_STD_GEN_05`. El C3 original sigue produciendo diagnóstico no autorizado para un `EXPIRED`, no PASS.

**Limitación:** no usa una fecha de reloj ni autentica autoridad del registro canónico; el estado EXPIRED es reportado. El enlace a política STD-GEN-05 debe cotejarse en la fase gobernada.

### C5: Revisor y constructor iguales bajo alias distintos
`guard_pg11_reviewer_aliases` exige mapeos de ambos `principal_ref` a `canonical_person_ref`, bloquea mapeo faltante y `PG11_SELF_REVIEW_CANONICAL_ALIAS` si los identificadores canónicos coinciden aunque sean `github:builder-x` frente a `email:reviewer-alt`. C5 original ya bloquea igualdad literal de principal.

**Limitación:** los mapeos son caller-supplied. `identity_provider_readback_verified=false`, `review_executed=false`: queda pendiente validación read-only con proveedor de identidades real, y separar firma y aprobación.

## Suite y trazabilidad de resultados

```bash
ROOT=sandbox/lf_contract_gate_test/programming_agent_four_stage
python3 -m py_compile "$ROOT"/pg11_integrity_candidate/tools/*.py "$ROOT"/pg11_integrity_candidate/tests/*.py

cd "$ROOT"/pg11_integrity_candidate
python3 -m unittest discover -s tests -p 'test_pg11_integrity_chain_v1.py' -v

cd ../pg10_conflict_candidate
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

**No declarar PASS por el mero archivo en GitHub.** Claude debe aportar stdout literal, HEAD exacto y diagnóstico de fallos. En este entorno el intento de `git ls-remote` falló con `Could not resolve host: github.com`; no se ejecutó una suite del checkout.

## Gobernanza
`SOURCE_PORTED / TESTS_WRITTEN / NOT_TESTED / OFFICIAL_PENDING`. Ningún artefacto activa producción, concede permisos, autentica waivers/revisores, fusiona PRs, escribe Supabase, modifica Análisis, `main` ni Testing. **No avanzar PG-12** sin el dictamen independiente de PG-11.
