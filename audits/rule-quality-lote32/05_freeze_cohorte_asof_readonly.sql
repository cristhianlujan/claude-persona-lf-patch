-- L32 / B02 G01 — CAPTURA Y READBACK SOLO LECTURA (PostgreSQL 17.6+)
-- ESTADO: CANDIDATO NO EJECUTADO. Requiere Ops, permiso SELECT y custodia.
-- NO SELECT ejecutado por este lote; NO DML, DDL, funciones escritoras ni cambios de RUN.
-- Autoridad de referencia: L28 doc 12, L31 B02/G01; NO sustituye R01 L19.
--
-- PROPIEDAD CRITICA: PostgreSQL no ofrece SELECT AS OF arbitrario. "as_of_utc"
-- identifica el instante de una transacción REPEATABLE READ + su snapshot MVCC,
-- NO permite reconstruir ese estado semanas después desde timestamps. Exportar
-- en la MISMA transacción la lista literal F2 y hashes F1; el readback posterior
-- siempre usa ESA lista F2/manifest y no recalcula la membresía con now().
--
-- PRECONDICION: el dueño decidió el perímetro. Hasta entonces, esta consulta
-- produce una FOTO DE CANDIDATOS, no la cohorte aprobada. Ejecutar el bloque F
-- en UNA misma sesión. Si el cliente separa statements en sesiones, BLOQUEAR.

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

-- F0: contexto de la captura. Guardar el resultado RAW con hora y actor.
SELECT transaction_timestamp() AS as_of_utc,
       pg_current_snapshot()::text AS mvcc_snapshot,
       current_database() AS database_name,
       current_user AS read_only_actor,
       current_setting('server_version') AS pg_version,
       current_setting('transaction_isolation') AS isolation_level,
       current_setting('transaction_read_only') AS transaction_read_only;

-- F1: resumen exacto de la FOTO capturada. SHA sobre UTF-8 del JSONB
-- producido EN EL SERVIDOR ORIGEN, no sobre una reserializacion PG18.
-- - membership_sha256: solo los IDs ordenados.
-- - preimage_manifest_sha256: IDs + preimagen completa de cada RUN.
WITH frozen AS MATERIALIZED (
  SELECT r.execution_id,
         r.operation_code,
         r.status,
         encode(sha256(convert_to(to_jsonb(r)::text, 'UTF8')), 'hex') AS row_sha256
  FROM public.lf_operation_execution AS r
  WHERE r.status = 'IN_PROGRESS'
), packed AS (
  SELECT coalesce(jsonb_agg(f.execution_id ORDER BY f.execution_id COLLATE "C"), '[]'::jsonb) AS membership_json,
         coalesce(jsonb_agg(
           jsonb_build_object(
             'run_id', f.execution_id,
             'operation_code', f.operation_code,
             'status', f.status,
             'row_sha256', f.row_sha256
           ) ORDER BY f.execution_id COLLATE "C"), '[]'::jsonb) AS preimage_manifest_json,
         count(*) AS row_count,
         count(DISTINCT f.execution_id) AS distinct_id_count
  FROM frozen AS f
)
SELECT transaction_timestamp() AS as_of_utc,
       pg_current_snapshot()::text AS mvcc_snapshot,
       row_count,
       distinct_id_count,
       encode(sha256(convert_to(membership_json::text, 'UTF8')), 'hex') AS membership_sha256,
       encode(sha256(convert_to(preimage_manifest_json::text, 'UTF8')), 'hex') AS preimage_manifest_sha256,
       membership_json::text AS membership_jsonb_raw_text,
       preimage_manifest_json::text AS preimage_manifest_jsonb_raw_text
FROM packed;

-- F2: CSV LITERAL — exportar INTEGRO, sin LIMIT ni filtrado visual.
-- La columna row_sha256 es SHA de la fila COMPLETA. Retener CSV bytes,
-- su sha256 externo, encoding UTF-8, herramienta exportadora y orden.
SELECT r.execution_id AS run_id,
       r.operation_code,
       r.status,
       r.started_at,
       r.updated_at,
       r.lease_owner,
       r.lease_expires_at,
       r.lease_fence,
       r.checkpoint_seq,
       encode(sha256(convert_to(to_jsonb(r)::text, 'UTF8')), 'hex') AS row_sha256
FROM public.lf_operation_execution AS r
WHERE r.status = 'IN_PROGRESS'
ORDER BY r.execution_id COLLATE "C";

-- No persistencia ni efecto: terminar la transaccion de lectura.
ROLLBACK;

-- READBACK EN OTRA SESION, TAMBIEN SOLO LECTURA.
-- SUSTITUIR CADA '[]' por el JSONB literal de F1 preimage_manifest_json
-- EXACTO, cuya custodia/SHA se haya aprobado en G01.
-- CERO FILAS / [] => BLOCK_EMPTY_MANIFEST. NO generar lista desde now().
-- En una ejecucion real, pasar el JSON como PARAMETRO literal seguro
-- del cliente, no concatenar entrada libre ni poner secretos en evidencia.

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

-- R1: compara cada miembro firmado con el RUN visible actualmente.
-- Detecta IDs faltantes, duplicados, SHA alterado o maniﬁesto corrupto.
WITH cfg AS (
  SELECT '[]'::jsonb AS signed_preimage_manifest
), expected AS MATERIALIZED (
  SELECT x.run_id, x.row_sha256, x.status, x.operation_code
  FROM cfg, jsonb_to_recordset(cfg.signed_preimage_manifest)
       AS x(run_id text, operation_code text, status text, row_sha256 text)
), checks AS (
  SELECT count(*) AS n,
         count(DISTINCT run_id) AS n_distinct,
         count(*) FILTER (WHERE run_id IS NULL OR row_sha256 IS NULL OR
                         row_sha256 !~ '^[a-f0-9]{64}$') AS malformed
  FROM expected
), comparisons AS (
  SELECT e.run_id,
         e.row_sha256 AS expected_row_sha256,
         CASE WHEN r.execution_id IS NULL THEN NULL
              ELSE encode(sha256(convert_to(to_jsonb(r)::text, 'UTF8')), 'hex') END AS live_row_sha256,
         r.status AS live_status,
         e.status AS expected_status
  FROM expected e
  LEFT JOIN public.lf_operation_execution r ON r.execution_id = e.run_id
), delta AS (
  SELECT count(*) FILTER (WHERE live_row_sha256 IS NULL) AS missing,
         count(*) FILTER (WHERE live_row_sha256 IS NOT NULL
                               AND live_row_sha256 <> expected_row_sha256) AS mutated,
         count(*) FILTER (WHERE live_status IS DISTINCT FROM expected_status) AS changed_status
  FROM comparisons
)
SELECT transaction_timestamp() AS readback_at_utc,
       c.n AS frozen_list_rows,
       c.n_distinct AS frozen_distinct_ids,
       c.malformed,
       d.missing, d.mutated, d.changed_status,
       CASE
         WHEN c.n = 0 THEN 'BLOCK_EMPTY_MANIFEST'
         WHEN c.n <> c.n_distinct THEN 'BLOCK_DUPLICATE_ID'
         WHEN c.malformed > 0 THEN 'BLOCK_MALFORMED'
         WHEN d.missing > 0 THEN 'BLOCK_MISSING_ID'
         WHEN d.mutated > 0 OR d.changed_status > 0 THEN 'BLOCK_CHANGED_PREIMAGE'
         ELSE 'MEMBERSHIP_PREIMAGE_MATCH_AT_READBACK'
       END AS local_check_only_not_g01_acceptance
FROM checks c CROSS JOIN delta d;

-- R2: altas y otros RUN actualmente IN_PROGRESS QUE NO ESTAN EN LA FOTO.
-- Estas filas son DELTA FUERA DE COHORTE, no auto-inclusion. "Fuera"
-- NO significa necesariamente creado despues; puede haber cambio de estado.
WITH cfg AS (SELECT '[]'::jsonb AS signed_preimage_manifest),
expected AS (
  SELECT x.run_id
  FROM cfg, jsonb_to_recordset(cfg.signed_preimage_manifest)
       AS x(run_id text)
)
SELECT r.execution_id AS outside_run_id,
       r.operation_code,
       r.status,
       r.started_at,
       r.updated_at,
       transaction_timestamp() AS readback_at_utc
FROM public.lf_operation_execution AS r
WHERE r.status = 'IN_PROGRESS'
  AND NOT EXISTS (SELECT 1 FROM expected e WHERE e.run_id = r.execution_id)
ORDER BY r.execution_id COLLATE "C";

-- R3: conciliacion EXACTA contra los 61 RUN de PR #3803.
-- Reemplazar manifest y ARRAY[] por lista literal acreditada por DBA,
-- con filtro SQL, commit y as_of de origen. Con 0 valores => BLOQUEO.
WITH cfg AS (
  SELECT '[]'::jsonb AS signed_preimage_manifest,
         ARRAY[]::text[] AS pr3803_run_ids
), frozen AS (
  SELECT x.run_id
  FROM cfg, jsonb_to_recordset(cfg.signed_preimage_manifest) AS x(run_id text)
), pr3803 AS (
  SELECT unnest(pr3803_run_ids) AS run_id FROM cfg
), unique_frozen AS (
  SELECT DISTINCT run_id FROM frozen
), unique_pr AS (
  SELECT DISTINCT run_id FROM pr3803
), pairs AS (
  SELECT f.run_id AS f_id, p.run_id AS p_id
  FROM unique_frozen f FULL OUTER JOIN unique_pr p ON f.run_id = p.run_id
), totals AS (
  SELECT (SELECT count(*) FROM frozen) AS cohort_rows,
         (SELECT count(*) FROM unique_frozen) AS cohort_ids,
         (SELECT count(*) FROM pr3803) AS pr_rows,
         (SELECT count(*) FROM unique_pr) AS pr_ids,
         count(*) FILTER (WHERE f_id IS NOT NULL AND p_id IS NOT NULL) AS intersection,
         count(*) FILTER (WHERE f_id IS NOT NULL AND p_id IS NULL) AS only_cohort,
         count(*) FILTER (WHERE p_id IS NOT NULL AND f_id IS NULL) AS only_pr
  FROM pairs
)
SELECT *, CASE WHEN cohort_rows = 0 OR pr_rows = 0 THEN 'BLOCK_MISSING_SOURCE_LIST'
               WHEN cohort_rows <> cohort_ids OR pr_rows <> pr_ids THEN 'BLOCK_DUPLICATE_SOURCE_ID'
               ELSE 'SETS_COMPUTED_REQUIRE_DBA_EXPLANATION_AND_INDEPENDENT_READBACK'
          END AS comparison_status
FROM totals;

ROLLBACK;

-- GATES DOCUMENTALES EXTERNOS: comparar los 232 IDs historicos y los 32
-- priorizados (L19), gestionar delta, recibir los 61 PR, emitir G01 real,
-- luego G02 por el 100% de la cohorte. Este archivo NO ejecuta ni emite recibos.
