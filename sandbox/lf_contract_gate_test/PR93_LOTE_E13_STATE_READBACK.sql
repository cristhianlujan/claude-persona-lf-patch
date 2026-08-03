-- PR #93 / LOTE-E.13 exact before/after state readback. SELECT-only.
select pg_catalog.jsonb_build_object(
  'database_name',pg_catalog.current_database()::pg_catalog.text,
  'writer_hmac_keys_v7_rows',(
    select pg_catalog.count(*) from private.lf_writer_hmac_keys_v7
  ),
  'reconciliation_writer_nonces_v7_rows',(
    select pg_catalog.count(*) from private.lf_reconciliation_writer_nonces_v7
  ),
  'github_reconciliation_runs_v3_rows',(
    select pg_catalog.count(*) from private.lf_github_reconciliation_runs_v3
  ),
  'gate_test_runs_v3_rows',(
    select pg_catalog.count(*) from private.lf_gate_test_runs_v3
  ),
  'lf_eventos_rows',(
    select pg_catalog.count(*) from public.lf_eventos
  ),
  'test_key_rows',(
    select pg_catalog.count(*)
    from private.lf_writer_hmac_keys_v7 k
    where k.key_id OPERATOR(pg_catalog.=) any(
      array[
        'lf-writer-2099-01-r98'::pg_catalog.text,
        'lf-writer-2099-02-r99'::pg_catalog.text,
        'lf-writer-2099-03-r100'::pg_catalog.text
      ]
    )
  ),
  'test_reconciliation_run_rows',(
    select pg_catalog.count(*)
    from private.lf_github_reconciliation_runs_v3 r
    where r.workflow_run_id OPERATOR(pg_catalog.=) 9000000000000101::pg_catalog.int8
  )
) as pr93_lote_e13_state_readback;
