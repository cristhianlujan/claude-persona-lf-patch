-- PR #93 / LOTE-E.14 exact before/after state readback. SELECT-only.
-- Secret key material is replaced by a SHA-256 digest and null flag before rowset hashing.
with table_names(table_name) as (
  values
    ('writer_hmac_keys_v7'::pg_catalog.text),
    ('reconciliation_writer_nonces_v7'::pg_catalog.text),
    ('github_reconciliation_runs_v3'::pg_catalog.text),
    ('gate_test_runs_v3'::pg_catalog.text),
    ('lf_eventos'::pg_catalog.text)
),
rowsets(table_name,row_json) as (
  select
    'writer_hmac_keys_v7'::pg_catalog.text,
    pg_catalog.jsonb_set(
      pg_catalog.to_jsonb(k) OPERATOR(pg_catalog.-) 'key_material'::pg_catalog.text,
      '{key_material_sha256}'::pg_catalog.text[],
      pg_catalog.to_jsonb(
        pg_catalog.encode(
          pg_catalog.sha256(
            pg_catalog.convert_to(
              coalesce(k.key_material,''::pg_catalog.text),
              'UTF8'::pg_catalog.name
            )
          ),
          'hex'::pg_catalog.text
        )
      ),
      true
    )
    OPERATOR(pg_catalog.||)
    pg_catalog.jsonb_build_object(
      'key_material_is_null',k.key_material is null
    )
  from private.lf_writer_hmac_keys_v7 k
  union all
  select 'reconciliation_writer_nonces_v7'::pg_catalog.text,pg_catalog.to_jsonb(n)
  from private.lf_reconciliation_writer_nonces_v7 n
  union all
  select 'github_reconciliation_runs_v3'::pg_catalog.text,pg_catalog.to_jsonb(r)
  from private.lf_github_reconciliation_runs_v3 r
  union all
  select 'gate_test_runs_v3'::pg_catalog.text,pg_catalog.to_jsonb(g)
  from private.lf_gate_test_runs_v3 g
  union all
  select 'lf_eventos'::pg_catalog.text,pg_catalog.to_jsonb(e)
  from public.lf_eventos e
),
summaries as (
  select
    names.table_name,
    pg_catalog.count(rows.row_json) as row_count,
    pg_catalog.encode(
      pg_catalog.sha256(
        pg_catalog.convert_to(
          coalesce(
            pg_catalog.jsonb_agg(
              rows.row_json order by rows.row_json::pg_catalog.text
            ) filter (where rows.row_json is not null),
            '[]'::pg_catalog.jsonb
          )::pg_catalog.text,
          'UTF8'::pg_catalog.name
        )
      ),
      'hex'::pg_catalog.text
    ) as rowset_sha256
  from table_names names
  left join rowsets rows
    on rows.table_name OPERATOR(pg_catalog.=) names.table_name
  group by names.table_name
),
state as (
  select pg_catalog.jsonb_object_agg(
    summaries.table_name,
    pg_catalog.jsonb_build_object(
      'rows',summaries.row_count,
      'rowset_sha256',summaries.rowset_sha256
    )
    order by summaries.table_name
  ) as tables
  from summaries
)
select pg_catalog.jsonb_build_object(
  'state_strength',
    'ROWSET_SHA256_WITH_KEY_MATERIAL_DIGEST'::pg_catalog.text,
  'database_name',pg_catalog.current_database()::pg_catalog.text,
  'tables',state.tables,
  'test_key_rows',(
    select pg_catalog.count(*)
    from private.lf_writer_hmac_keys_v7 k
    where k.key_id OPERATOR(pg_catalog.=) any(array[
      'lf-writer-2099-01-r98'::pg_catalog.text,
      'lf-writer-2099-02-r99'::pg_catalog.text,
      'lf-writer-2099-03-r100'::pg_catalog.text
    ])
  ),
  'test_reconciliation_run_rows',(
    select pg_catalog.count(*)
    from private.lf_github_reconciliation_runs_v3 r
    where r.workflow_run_id
      OPERATOR(pg_catalog.=) 9000000000000101::pg_catalog.int8
  )
) as pr93_lote_e14_state_readback
from state;
