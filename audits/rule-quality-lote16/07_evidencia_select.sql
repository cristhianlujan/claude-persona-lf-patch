-- LOTE 16. SELECT ONLY. SHA-256 sobre JSONB canónico con orden por texto de la fila.
-- Proyecto mhwmirqcgxxukpctffuv. No DDL/DML ni escritura en Supabase.

-- S01 | n=578 | SHA256_RESULT=59420d4b0b875d399a2eb9912be72d075994b072d861eb8fd2ebc77c1c4770d9
WITH source_rows AS MATERIALIZED (
SELECT id,codigo,categoria,titulo,descripcion,estado FROM lf_ops.reglas ORDER BY codigo,id
), packed AS (
SELECT COALESCE(jsonb_agg(to_jsonb(source_rows) ORDER BY to_jsonb(source_rows)::text),'[]'::jsonb) AS raw FROM source_rows
)
SELECT encode(sha256(convert_to(raw::text,'UTF8')),'hex') AS result_sha256, jsonb_array_length(raw) AS row_count, raw AS result_rows FROM packed;

-- S02 | n=57 | SHA256_RESULT=2c127c5e0e26962ea5f4d23c3e9878b53abc1564b7cb93045c43793b38bb0cce
WITH source_rows AS MATERIALIZED (
SELECT codigo,categoria,titulo,descripcion,pendiente_detalle,estado FROM lf_ops.reglas WHERE estado='VIGENTE' AND pendiente_decision IS TRUE ORDER BY codigo
), packed AS (
SELECT COALESCE(jsonb_agg(to_jsonb(source_rows) ORDER BY to_jsonb(source_rows)::text),'[]'::jsonb) AS raw FROM source_rows
)
SELECT encode(sha256(convert_to(raw::text,'UTF8')),'hex') AS result_sha256, jsonb_array_length(raw) AS row_count, raw AS result_rows FROM packed;

-- S03 | n=3 | SHA256_RESULT=8b70da4a3d3b381620473202de4a569d4b09fcfda6b3973e81661c3d2631b46a
WITH source_rows AS MATERIALIZED (
WITH refs AS (SELECT r.codigo AS origen_codigo,r.titulo AS origen_titulo,r.descripcion AS origen_descripcion,r.estado AS origen_estado,k.key AS campo,(k.value #>> '{}')::integer AS destino_id FROM lf_ops.reglas r CROSS JOIN LATERAL jsonb_each(coalesce(r.valor_config,'{}'::jsonb)) k WHERE k.key ~* '(^|_)rule_id$' AND jsonb_typeof(k.value)='number' AND r.estado='VIGENTE') SELECT refs.*,t.codigo AS destino_codigo,t.titulo AS destino_titulo,t.descripcion AS destino_descripcion,t.estado AS destino_estado FROM refs JOIN lf_ops.reglas t ON t.id=refs.destino_id WHERE t.estado='CANDIDATO' ORDER BY origen_codigo,campo
), packed AS (
SELECT COALESCE(jsonb_agg(to_jsonb(source_rows) ORDER BY to_jsonb(source_rows)::text),'[]'::jsonb) AS raw FROM source_rows
)
SELECT encode(sha256(convert_to(raw::text,'UTF8')),'hex') AS result_sha256, jsonb_array_length(raw) AS row_count, raw AS result_rows FROM packed;

-- S04 | n=20 | SHA256_RESULT=815d9f903189c7fe98c5b6c8ae7a32ca4b061d3422033010140fe60230f2dd3f
WITH source_rows AS MATERIALIZED (
WITH p AS (SELECT r.id,r.codigo,r.estado,k.key,k.value FROM lf_ops.reglas r CROSS JOIN LATERAL jsonb_each(coalesce(r.valor_config,'{}'::jsonb)) k WHERE jsonb_typeof(k.value) IN ('number','boolean','string') AND k.key ~* '(max|min|limite|limit|timeout|expir|sesion|session|reenv|intento|ventana|cooldown|retry|threshold|ttl|duracion|duraci|ratio|pct|percent|monto|amount)' AND k.key !~* '(_id$|^source_|decision|version|policy_id|rule_id|message_id|screen_id|error_id)'), pairs AS (SELECT a.codigo AS regla_a,b.codigo AS regla_b,a.key AS parametro,a.value AS valor_a,b.value AS valor_b,count(DISTINCT ra.pantalla_id) AS pantallas_comunes FROM p a JOIN p b ON a.codigo<b.codigo AND a.key=b.key AND a.value<>b.value JOIN lf_ops.reglas_pantallas ra ON ra.regla_id=a.id JOIN lf_ops.reglas_pantallas rb ON rb.regla_id=b.id AND ra.pantalla_id=rb.pantalla_id WHERE a.estado='VIGENTE' AND b.estado='VIGENTE' GROUP BY 1,2,3,4,5) SELECT p.*,a.titulo AS titulo_a,a.descripcion AS descripcion_a,b.titulo AS titulo_b,b.descripcion AS descripcion_b FROM pairs p JOIN lf_ops.reglas a ON a.codigo=p.regla_a JOIN lf_ops.reglas b ON b.codigo=p.regla_b ORDER BY pantallas_comunes DESC,regla_a,regla_b
), packed AS (
SELECT COALESCE(jsonb_agg(to_jsonb(source_rows) ORDER BY to_jsonb(source_rows)::text),'[]'::jsonb) AS raw FROM source_rows
)
SELECT encode(sha256(convert_to(raw::text,'UTF8')),'hex') AS result_sha256, jsonb_array_length(raw) AS row_count, raw AS result_rows FROM packed;
