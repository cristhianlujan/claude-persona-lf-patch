# LF PG-14 — Última etapa de Fase 2: entrega candidata a Testing
Fecha: 2026-11-04

## Base exacta
- PR nuevo draft, apilado sobre PR #3548, HEAD **`2cdac92fee2d588efc5d85393dbc7a2f6e0bbeb1`**, calificado por Claude PG-13 3/3 y freeze local bloqueando ocho variantes de mutación.
- Rama `lf/pg14-testing-handoff-final-20261104`.
- C1, C2 y C3 originales fueron copiados **sin alteraciones** desde PR #3528.
- Contrato canónico **en repo**, en modo fuente sin autoridad: `wave1_boundary_contracts/testing_admission_contract_v1.json`. Su esquema es `TESTING_ADMISSION_CONTRACT_V1`, estado `SOURCE_ONLY_CANDIDATE`, sin motor paralelo. `EXECUTION` exige `analysis_package_ref`, `analysis_package_sha256`, `source_currentness_ref`, `frozen_candidate_ref`, `frozen_candidate_sha256`; NO exige `agent_task` ni Story.
- **Sin paquete READY autenticado de Análisis**. El fixture simula un paquete `ready_verified=false`, así que no abre una admisión real.

## C1 — PG13_C3 → PG14_C1 y SHA/tag congelados
El test positivo construye `build()` del verdadero productor de PG-13 (que llama PG-12, PG-11, PG-10 y previos). Usa `prepare_pg14_c1` y `bridge_pg13_to_pg14`, con cinco sobres reales de productores:
`pg12_c1`, `pg13_bridge`, `pg13_c1`, `pg13_c2`, `pg13_c3`.

El puente:
- revisa esquema, SHA-256 canónico y banderas de autoridad de cada sobre;
- enlaza `pg13_c3.source_pg13_c2_sha256`, `pg13_c2.source_pg13_c1_sha256`, la identidad PG-12 y `pg14_c1.source_pg13_c3_sha256`;
- verifica el commit y árbol congelados entre PG-12 y PG-13;
- exige `refs/tags/frozen/<commit_sha>` y OID sintácticamente válido del tag **anotado**;
- exige `frozen_candidate_sha256` idéntico a `pg12_c1.candidate_sha256`;
- exige `analysis_package_sha256` y `source_currentness_ref` coherentes con un sobre de Análisis declarado pero NO READY.

**Limitación**: el bridge no lee el tag desde Git productivo ni autentica el paquete de Análisis. `freeze_tag_authenticity_verified=false`, `analysis_ready_verified=false`.

Negativos: falta SHA de candidato o Análisis; SHA de freeze equivocado, contrato EXECUTION adulterado, tag ajeno, huella de Análisis ajena.

## C2 — Payload Testing completo
El original `prepare_pg14_c2` recibe: versión de catálogo, lista de obligaciones que incluye `B2B-RULE-TEST-001`, contrato `fn_submit_blind_test_contract` y `pending_copy_texts`. El guard complementario `validate_pg14_c2_completeness` exige **lista no vacía** de textos pendientes, además de catálogo, obligación B2B y blind test. La salida del receptor simulador rechaza paquete sin cualquiera de las cuatro piezas.

Los textos, obligaciones y oráculos son referencias de prueba, **no contenido leído de fuentes autenticadas**. Los textos pendientes nunca se inventan para producción.

## C3 — Fixture local ACCEPT/BLOCK y PostgreSQL desechable

`pg14_local_testing_receiver_v1.py` es receptor **simulado**, no Testing real:
- devuelve **ACCEPT** para un paquete candidato consistente y **BLOCK** si el request o la identidad está adulterada;
- verifica también la completitud C2; mantiene `testing_real_invoked=false`, `analysis_ready_authenticated=false` y `production_authority=false`;
- la aceptación local **NO** significa que el contrato productivo de Testing haya admitido el paquete, ni que exista READY.

`pg14_disposable_testing_readback_v1.py` es arnés opt-in de persistencia REAL:
1. Solo arranca si `PG14_DISPOSABLE_DB=YES` y la base se llama `pg14_test_*`.
2. Exige conexión local; inspecciona `current_database()` e `inet_server_addr()` antes de crear cualquier esquema.
3. Construye dos respuestas reales del simulador: `ACCEPT` por fixture válido y `BLOCK` por alteración del SHA congelado.
4. Crea esquema efímero con UUID, inserta ambos JSONB vía `psql` y confirma COMMIT en cada proceso.
5. En **otra sesión de psql**, relee ambas respuestas y compara igualdad JSON exacta y SHA-256 canónico.
6. Elimina el esquema en `finally` aunque falle un readback.
7. No conecta al servicio Testing, no escribe en Supabase y no autoriza despacho.

**Muy importante:** no hay `psql`/PostgreSQL desechable en el entorno del autor. La ejecución real del arnés debe hacerse por Claude en su PostgreSQL temporal, como con PG-12 C4. Hasta entonces NO declarar `PG14_C3_POSTGRES_PASS`.

## Comandos de auditoría exact-HEAD
```bash
git rev-parse HEAD
ROOT=sandbox/lf_contract_gate_test/programming_agent_four_stage
python3 -m py_compile "$ROOT"/pg14_testing_handoff_candidate/tools/*.py "$ROOT"/pg14_testing_handoff_candidate/tests/*.py
cd "$ROOT"/pg14_testing_handoff_candidate
python3 -m unittest discover -s tests -p 'test_pg14_final_chain_v1.py' -v

# Solo en PostgreSQL de prueba local desechable, nunca Supabase:
# createdb pg14_test_lf_admission
# export PG14_DISPOSABLE_DB=YES
# export PG14_TEST_DSN=pg14_test_lf_admission
# python3 tools/pg14_disposable_testing_readback_v1.py
#
# Se requieren ambas líneas:
# PG14_C3_LOCAL_ACCEPT_PERSISTED_READBACK_PASS
# PG14_C3_LOCAL_BLOCK_PERSISTED_READBACK_PASS
# PG14_C3_DIFFERENT_PSQL_SESSIONS=TRUE
# PG14_C3_REAL_TESTING_INVOKED=FALSE

cd ../pg13_freeze_candidate
python3 -m unittest discover -s tests -p 'test_pg13_freeze_chain_v1.py' -v
python3 -m unittest discover -s tests -p 'test_pg13_disposable_git_enforcement_v1.py' -v
cd ../pg12_identity_candidate
python3 -m unittest discover -s tests -p 'test_pg12_identity_chain_v1.py' -v
```
Se debe recopilar stdout literal, HEAD exacto, SHA de respuestas aceptada y bloqueada y confirmar que no queda esquema residual.

## Dictamen inicial
`SOURCE_PORTED / CONNECTOR_WRITTEN / 13_UNIT_TESTS_WRITTEN / POSTGRES_FIXTURE_PREPARED / NOT_TESTED`.

No se activa Testing real. No hay Análisis READY. No hay llamadas al Worker, cambios productivos, escritura Supabase, merge, ni modificación de `main`, Análisis o Testing.
