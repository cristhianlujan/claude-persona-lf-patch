-- LF Executor 4.3: readonly catalog snapshot. Never executes DDL or reads application rows.
WITH targets(relation_name) AS (VALUES ('programacion.provenance_channels'),('public.lf_activos'),('public.lf_operation_contracts'),('public.lf_operation_execution'),('public.lf_operation_execution_steps'),('public.lf_operation_judges'),('public.lf_operation_registry'),('public.lf_operation_step_contracts'),('public.lf_operation_step_judge_bindings'),('public.lf_operation_steps'),('public.lf_router_action_registry')),
obj AS (
 SELECT t.relation_name,c.oid,c.relowner,c.relkind,c.relrowsecurity,c.relforcerowsecurity
 FROM targets t JOIN pg_class c ON c.oid=to_regclass(t.relation_name)
), raw AS (
SELECT o.relation_name,jsonb_build_object(
'relation',o.relation_name,'kind',o.relkind,'owner',pg_get_userbyid(o.relowner),
'rls',o.relrowsecurity,'force_rls',o.relforcerowsecurity,
'columns',COALESCE((SELECT jsonb_agg(jsonb_build_object(
 'name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,
 'identity',a.attidentity,'generated',a.attgenerated,'default',pg_get_expr(d.adbin,d.adrelid),
 'collation',CASE WHEN a.attcollation=0 OR a.attcollation=(SELECT typcollation FROM pg_type WHERE oid=a.atttypid)
 THEN NULL ELSE a.attcollation::regcollation::text END)
 ORDER BY a.attnum) FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
 WHERE a.attrelid=o.oid AND a.attnum>0 AND NOT a.attisdropped),'[]'::jsonb),
'constraints',COALESCE((SELECT jsonb_agg(jsonb_build_object(
 'name',c.conname,'type',c.contype,'definition',pg_get_constraintdef(c.oid,true),
 'validated',c.convalidated,'references',CASE WHEN c.confrelid<>0 THEN c.confrelid::regclass::text ELSE NULL END)
 ORDER BY c.conname) FROM pg_constraint c WHERE c.conrelid=o.oid),'[]'::jsonb),
'indexes',COALESCE((SELECT jsonb_agg(jsonb_build_object(
 'name',i.indexrelid::regclass::text,'definition',pg_get_indexdef(i.indexrelid),
 'unique',i.indisunique,'valid',i.indisvalid)
 ORDER BY i.indexrelid::regclass::text) FROM pg_index i WHERE i.indrelid=o.oid),'[]'::jsonb),
'triggers',COALESCE((SELECT jsonb_agg(jsonb_build_object(
 'name',tg.tgname,'definition',pg_get_triggerdef(tg.oid,true),
 'enabled',tg.tgenabled,'function',tg.tgfoid::regprocedure::text,
 'function_source_sha256',encode(extensions.digest(convert_to(pg_get_functiondef(tg.tgfoid),'UTF8'),'sha256'),'hex'))
 ORDER BY tg.tgname) FROM pg_trigger tg WHERE tg.tgrelid=o.oid AND NOT tg.tgisinternal),'[]'::jsonb),
'policies',COALESCE((SELECT jsonb_agg(jsonb_build_object(
 'name',p.polname,'command',p.polcmd,'permissive',p.polpermissive,
 'roles',(SELECT jsonb_agg(CASE WHEN rid=0 THEN 'PUBLIC' ELSE rid::regrole::text END ORDER BY rid)
   FROM unnest(p.polroles) rid),
 'using',pg_get_expr(p.polqual,p.polrelid),'with_check',pg_get_expr(p.polwithcheck,p.polrelid))
 ORDER BY p.polname) FROM pg_policy p WHERE p.polrelid=o.oid),'[]'::jsonb),
'grants',COALESCE((SELECT jsonb_agg(jsonb_build_object(
 'role',CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END,
 'privilege',a.privilege_type,'grantable',a.is_grantable)
 ORDER BY a.grantee,a.privilege_type)
 FROM aclexplode(coalesce((SELECT relacl FROM pg_class WHERE oid=o.oid),acldefault('r',o.relowner))) a
 WHERE a.grantee<>o.relowner),'[]'::jsonb)
) AS definition FROM obj o)
SELECT jsonb_build_object(
 'schema_version','LF_OPERATIONAL_BASELINE_CATALOG_READBACK_V1',
 'authority','LIVE_PG_CATALOG_READONLY_NOT_MIGRATION_SOURCE',
 'observed_at',(SELECT clock_timestamp()::text),
 'expected_relations',(SELECT count(*) FROM targets),
 'resolved_relations',(SELECT count(*) FROM obj),
 'relations',(SELECT jsonb_agg(definition ORDER BY relation_name) FROM raw)
)::text AS payload;
