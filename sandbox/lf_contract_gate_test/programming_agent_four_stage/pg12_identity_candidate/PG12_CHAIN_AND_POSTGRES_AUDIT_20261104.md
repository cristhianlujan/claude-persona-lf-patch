# PG-12 — Identidad, manifiesto, checks y readback PostgreSQL (2026-11-04)

## Fuente exacta y alcance
- Rama `lf/pg12-identity-manifest-chain-20261104`, base exacta PR #3542 HEAD `837b188d5d33f8fc597f2ac03789d9e5ce182293`, calificado por Claude con 26/26 tests.
- C1–C4 reutilizados **sin alterar** desde #3528; cuatro documentos conservados.
- `tools/pg12_git_identity_and_pg11_bridge_v1.py`: conector no autoritativo PG10→PG11→PG12 y verificador de bytes de objetos Git; diferencia `SHA declarado` frente a `SHA recalculado de bytes`.
- `tests/test_pg12_identity_chain_v1.py`: 12 pruebas candidatas (no ejecutadas aún en checkout).
- `tools/pg12_disposable_postgres_readback_v1.py`: harness opt-in de persistencia real y lectura en **segunda sesión** PostgreSQL desechable.

## Conexión de etapa sin omitir PG11
El test positivo importa `inputs()` del test de PG-11 que genera la salida real de PG-10 C5 y PG-11 C1; usa `bridge_pg10_c5_to_pg11_c1` y la salida real `prepare_pg11_c5` en `prepare_pg12_c1`. El nuevo bridge verifica:
- PG-11 C5→PG-12 C1 por `candidate_sha256`.
- Enlace original PG10 C5→PG11 C1, `run_ref`, repositorio, commit base y commit candidato; los SHA se revalidan.
- Sin `production_authority` ni `handoff_allowed`.
- **Recomputación Git SHA-1:** `sha1(b'commit <len>\\0'+commit_bytes)` y `sha1(b'tree <len>\\0'+tree_bytes)`; además, el header `tree` del commit debe coincidir con el OID del árbol.

**Distinción obligatoria:** el test positivo de cadena usa los SHA sintéticos históricos del checkout (`a*40`, `b*40`) y por ello NO afirma que se verificaron bytes de objetos Git correspondientes a esa cadena. El verificador de bytes se prueba **por separado** sobre objetos Git sintéticos correctamente serializados y prueba errores de OID en commits y árboles. Para GO de identidad sobre un candidato real debe aportarse commit/base/tree byte-exact desde Git y ejercitar el puente en modo prueba de objetos completa. El bridge deja `git_object_sha1_recomputed_from_supplied_bytes=false` cuando esos bytes no están disponibles.

## C2 — Decimales y suma
La lógica reutilizada del C2 exige `Decimal` finito, precisión máxima de seis decimales, `wasted_cost <= cost`, tokens no negativos, cache <= input, y que el total sea exactamente la suma de filas. Pruebas negativas:
- costo `1.2.3`;
- `NaN`;
- total `0.31` con etapas `0.10+0.20`;
- tokens cacheados mayores que tokens de entrada.
Los importes son **declarados, no facturados por un modelo real**.

## C3 — Resultados enlazados
Se construyen los 13 registros de check PG08(8) y PG11(5) para un único `PG12_C1.candidate_sha256`, todos `NOT_RUN` y sin recibo. Prueba negativa: no se admite `PASS` sin `execution_receipt_ref`/result SHA. La suite no falsifica checks productivos.

## C4 — Persistencia de verdad en PostgreSQL descartable
C4 reutilizado solo genera `payload_candidate`, digest y un plan; sus indicadores `persisted=false`, `readback_matched=false` permanecen sin autoridad. Para **cumplir experimentalmente** el requisito de write/readback se añadió un harness independiente:
`tools/pg12_disposable_postgres_readback_v1.py`.

1. Exige `PG12_DISPOSABLE_DB=YES` y `PG12_TEST_DSN` cuyo nombre de base empieza con `pg12_test_` (no usar ninguna base de producción).
2. Importa el productor real C4 desde la suite de pruebas; comprueba que el digest del payload coincida.
3. Crea esquema único, tabla de ensayo e **INSERT real PostgreSQL con COMMIT** usando `psql`.
4. Abre **otra sesión de psql** y ejecuta `SELECT payload::text`, parsea JSONB, compara igualdad estructural exacta y SHA-256 canónico con el payload original.
5. Elimina el esquema en `finally`, incluso si falla la comparación.
6. No escribe nada en Supabase, no concede autoridad productiva ni sustituye al writer PG-12.

**No hay evidencia de ejecución en este turno:** el entorno disponible carece de una instancia PostgreSQL desechable y de `psql`. Hasta ejecutar el harness con salida literal `PG12_C4_POSTGRES_DISPOSABLE_READBACK_PASS` y los dos digests idénticos, C4 **no está técnicamente probado como persistido/releído**.

### Comandos exact-HEAD para Claude
```bash
git rev-parse HEAD
ROOT=sandbox/lf_contract_gate_test/programming_agent_four_stage
python3 -m py_compile "$ROOT"/pg12_identity_candidate/tools/*.py "$ROOT"/pg12_identity_candidate/tests/*.py
cd "$ROOT"/pg12_identity_candidate
python3 -m unittest discover -s tests -p 'test_pg12_identity_chain_v1.py' -v
# SOLO en instancia PostgreSQL descartable realmente creada:
# createdb pg12_test_lf_pg12   # con un servidor local de pruebas, nunca Supabase
# export PG12_DISPOSABLE_DB=YES
# export PG12_TEST_DSN=pg12_test_lf_pg12
# python3 tools/pg12_disposable_postgres_readback_v1.py
cd ../pg11_integrity_candidate
python3 -m unittest discover -s tests -p 'test_pg10_pg11_bridge_and_waiver_time_v1.py' -v
python3 -m unittest discover -s tests -p 'test_pg11_integrity_chain_v1.py' -v
```

## Estado hasta que se ejecuten pruebas
**SOURCE_PORTED / 12_TESTS_WRITTEN / POSTGRES_HARNESS_PREPARED / NOT_RUN / OFFICIAL_PENDING**. Sin merge, actualizaciones productivas, Supabase writes, Analysis, main ni Testing. No avanzar PG13 antes de dictamen independiente PG12.
