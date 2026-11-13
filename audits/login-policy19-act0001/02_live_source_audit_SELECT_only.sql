-- AUDITORÍA SOLO SELECT, sin emisión de recibo ni DML/DDL.
SELECT scope_code,operation_code,effect_entrypoint,allowed_table,allowed_columns,forbidden_columns,
       schema_columns_sha256,writer_source_md5,policy_sha256
FROM public.lf_router_scope_policy_v1 ORDER BY scope_code;
SELECT p.proname,p.oid::regprocedure AS signature,
       md5(pg_get_functiondef(p.oid)) AS source_md5
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN
('lf_router_scope_bind_v1','lf_router_scope_receipt_consume_v2')
ORDER BY p.proname;
