-- Read only: transitive foreign-key requirements for LF Executor baseline replay.
WITH RECURSIVE initial(oid) AS (SELECT unnest(ARRAY['programacion.provenance_channels'::regclass,'public.lf_activos'::regclass,'public.lf_operation_contracts'::regclass,'public.lf_operation_execution'::regclass,'public.lf_operation_execution_steps'::regclass,'public.lf_operation_judges'::regclass,'public.lf_operation_registry'::regclass,'public.lf_operation_step_contracts'::regclass,'public.lf_operation_step_judge_bindings'::regclass,'public.lf_operation_steps'::regclass,'public.lf_router_action_registry'::regclass])::oid),
walk(oid,depth,path) AS (
 SELECT oid,0,ARRAY[oid] FROM initial
 UNION ALL
 SELECT fk.confrelid,w.depth+1,w.path||fk.confrelid FROM walk w
 JOIN pg_constraint fk ON fk.conrelid=w.oid AND fk.contype='f'
 WHERE w.depth<10 AND fk.confrelid<>0 AND NOT fk.confrelid=ANY(w.path)
), nodes AS (SELECT oid,min(depth) min_depth FROM walk GROUP BY oid),
relations AS (
 SELECT ns.nspname||'.'||c.relname relation,n.min_depth,
 (SELECT count(*) FROM pg_constraint fk WHERE fk.conrelid=c.oid AND fk.contype='f') fk_count
 FROM nodes n JOIN pg_class c ON c.oid=n.oid JOIN pg_namespace ns ON ns.oid=c.relnamespace
), edges AS (
 SELECT xns.nspname||'.'||src.relname AS source_relation,
 tns.nspname||'.'||target.relname AS target_relation,k.conname AS constraint_name
 FROM nodes n JOIN pg_constraint k ON k.conrelid=n.oid AND k.contype='f'
 JOIN pg_class src ON src.oid=k.conrelid JOIN pg_namespace xns ON xns.oid=src.relnamespace
 JOIN pg_class target ON target.oid=k.confrelid JOIN pg_namespace tns ON tns.oid=target.relnamespace
)
SELECT jsonb_build_object(
 'schema_version','LF_OPERATIONAL_BASELINE_FK_CLOSURE_READBACK_V1',
 'authority','LIVE_PG_CATALOG_READONLY_NOT_MIGRATION_SOURCE',
 'observed_at',clock_timestamp()::text,
 'root_count',(SELECT count(*) FROM initial),
 'total_count',(SELECT count(*) FROM nodes),
 'relations',(SELECT jsonb_agg(jsonb_build_object('relation',relation,'min_depth',min_depth,'fk_count',fk_count) ORDER BY min_depth,relation) FROM relations),
 'edges',(SELECT jsonb_agg(jsonb_build_object('from',source_relation,'to',target_relation,'constraint',constraint_name) ORDER BY source_relation,target_relation,constraint_name) FROM edges)
)::text AS payload;
