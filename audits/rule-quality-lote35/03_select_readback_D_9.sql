-- L35: 9 exact exceptions / 8 expired leases. SELECT only.
WITH wanted AS (SELECT unnest(ARRAY['EXEC-DB-LEDGER-NAME-RECONCILE-20260930080103-20261001','EXEC-DB-TRAIN-PR2867-20261017035500-R39000482544','EXEC-DB-TRAIN-PR3438-20261101020345-R41263578875','EXEC-DB-TRAIN-PR3807-20261113083527-R43394317535','EXEC-S30-LF-ASSURANCE-METHOD-V1-GATED-20260916-003','EXEC-S30-R19-AUTONOMOUS-20260915-001','EXEC-S30-R19-CURRENTNESS-REFRESH-20260917-002','EXEC-S30-R24-CI-GATE-DIAGNOSTIC-20260915-001','EXEC-S37-WP01-OPPORTUNITY-EXPANDER-20260914-001']::text[]) id)
SELECT w.id AS execution_id,r.operation_code,r.status,r.started_at,r.updated_at,r.completed_at,
r.lease_owner,r.lease_expires_at,r.lease_fence,r.checkpoint_seq,
encode(sha256(convert_to(coalesce(r.checkpoint_payload,'{}'::jsonb)::text,'UTF8')),'hex') AS checkpoint_sha256,
r.target_repo,r.target_path,r.target_code,
encode(sha256(convert_to(to_jsonb(r)::text,'UTF8')),'hex') AS live_row_sha256,
(SELECT coalesce(jsonb_agg(jsonb_build_object('order',s.step_order,'step',s.step_id,'status',s.status,
  'ref',s.evidence_ref,'at',s.observed_at,
  'blocking_codes',coalesce(s.evidence_payload->'blocking_codes','[]'::jsonb))
 ORDER BY s.step_order),'[]'::jsonb) FROM public.lf_operation_execution_steps s WHERE s.execution_id=w.id) AS steps,
(SELECT coalesce(jsonb_agg(jsonb_build_object('scope',e.effect_scope,'state',e.state,
'reserved_at',e.reserved_at,'resolved_at',e.resolved_at,
'receipt_sha256',encode(sha256(convert_to(coalesce(e.receipt,'{}'::jsonb)::text,'UTF8')),'hex'),
'receipt_keys',(SELECT jsonb_agg(key ORDER BY key) FROM jsonb_object_keys(coalesce(e.receipt,'{}'::jsonb)) key))
 ORDER BY e.effect_scope,e.dispatch_key),'[]'::jsonb) FROM public.lf_operation_effect_guard e WHERE e.execution_id=w.id) AS guard_rows,
m.version AS ledger_version,m.name AS ledger_name,coalesce(array_length(m.statements,1),0) AS ledger_statements,
clock_timestamp() as as_of_utc
FROM wanted w LEFT JOIN public.lf_operation_execution r ON r.execution_id=w.id
LEFT JOIN supabase_migrations.schema_migrations m
ON m.version=substring(r.target_path from 'migrations/([0-9]{14})_')
ORDER BY w.id COLLATE "C";
