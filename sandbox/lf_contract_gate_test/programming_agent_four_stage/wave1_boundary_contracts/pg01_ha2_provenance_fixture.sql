-- H-A2 sandbox: columns and governance tables mirrored from Supabase (read-only inspection 29-oct).
ALTER TABLE public.lf_operation_execution ADD COLUMN created_by_execution_id text NOT NULL DEFAULT 'UNKNOWN',
 ADD COLUMN created_at timestamptz DEFAULT now(), ADD COLUMN updated_at timestamptz DEFAULT now(), ADD COLUMN updated_by_execution_id text,
 ADD COLUMN target_repo text, ADD COLUMN target_path text, ADD COLUMN idempotency_key text, ADD COLUMN request_sha256 text,
 ADD COLUMN lease_owner text, ADD COLUMN lease_expires_at timestamptz;
ALTER TABLE public.lf_operation_execution ALTER COLUMN status SET DEFAULT 'IN_PROGRESS', ALTER COLUMN manifest SET DEFAULT '{}'::jsonb;
CREATE UNIQUE INDEX ON public.lf_operation_execution(operation_code,idempotency_key) WHERE idempotency_key IS NOT NULL;
ALTER TABLE public.lf_operation_execution_steps ADD COLUMN created_by_execution_id text NOT NULL DEFAULT 'UNKNOWN';
CREATE TABLE private.lf_evidence_ledger_v1(receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),execution_id text NOT NULL,capability_code text NOT NULL,gate_code text NOT NULL,receipt_kind text NOT NULL,subject_type text NOT NULL,subject_ref text NOT NULL,subject_sha256 text NOT NULL,source_head_sha text NOT NULL,authority_ref text NOT NULL,resolver_id text NOT NULL,provider text NOT NULL,provider_ref text NOT NULL,verification_method text NOT NULL,verification_state text NOT NULL,verification_payload jsonb NOT NULL DEFAULT '{}',receipt_payload jsonb NOT NULL,receipt_sha256 text NOT NULL,created_by_execution_id text NOT NULL,verified_at timestamptz,created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE private.lf_orchestrator_dispatch_receipts_v1(receipt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),orchestrator_execution_id text NOT NULL,consumer_execution_id text NOT NULL,capability_code text NOT NULL,plan_digest text NOT NULL,dispatch_scope jsonb NOT NULL,orchestrator_operation_code text NOT NULL,orchestrator_operation_version text NOT NULL,guard_code text NOT NULL,receipt_sha256 text NOT NULL,issued_by_execution_id text NOT NULL,issued_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.lf_capability_binding(execution_id text,capability_code text,bound_version text NOT NULL,bound_manifest_sha256 text NOT NULL,binding_mode text NOT NULL,binding_state text NOT NULL DEFAULT 'BOUND',step_count_at_bind int NOT NULL DEFAULT 0,rebind_count int NOT NULL DEFAULT 0,bound_at timestamptz NOT NULL DEFAULT now(),last_checked_at timestamptz NOT NULL DEFAULT now(),bound_by_execution_id text NOT NULL,last_checked_by_execution_id text NOT NULL,PRIMARY KEY(execution_id,capability_code));
-- Same privilege split as Supabase: service_role may write executions/steps/binding, not ledger nor dispatch.
GRANT INSERT,UPDATE,SELECT ON public.lf_operation_execution,public.lf_operation_execution_steps,public.lf_capability_binding TO service_role;
-- Sandbox helper: a judge whose provenance chain is complete (synthetic, owner-written; NOT a real review).
CREATE FUNCTION pg_temp.govern(p_judge text) RETURNS void LANGUAGE plpgsql AS $g$
DECLARE ctx text; c record; orch text:='ORCH-'||p_judge; plan text; cms text:=repeat('c',64); rid uuid; did uuid; sha text; ref text;
BEGIN
 ref:=(SELECT manifest->>'subject_ref' FROM public.lf_operation_execution WHERE execution_id=p_judge);
 ctx:=split_part(ref,'/',2);
 SELECT * INTO c FROM private.lf_decision_context_asof_v1 WHERE context_id=ctx::uuid;
 plan:=encode(extensions.digest('plan:'||p_judge,'sha256'),'hex');
 INSERT INTO private.lf_evidence_ledger_v1(execution_id,capability_code,gate_code,receipt_kind,subject_type,subject_ref,subject_sha256,source_head_sha,authority_ref,resolver_id,provider,provider_ref,verification_method,verification_state,receipt_payload,receipt_sha256,created_by_execution_id,verified_at)
 VALUES(c.created_by_execution_id,'PROGRAMMING','G','SUBJECT','PROGRAMMING_ANALYSIS_PACKAGE',ref,c.context_sha256,repeat('1',40),'SANDBOX','R','P','PR','M','VERIFIED','{}',repeat('e',64),'LEDGER-'||p_judge,now()) RETURNING receipt_id INTO rid;
 sha:=encode(extensions.digest(convert_to(jsonb_build_object('schema_version','LF_ORCHESTRATOR_DISPATCH_RECEIPT_V1','orchestrator_execution_id',orch,
  'orchestrator_operation_code','ORQ_SANDBOX','orchestrator_operation_version','1','consumer_execution_id',p_judge,'capability_code','INDEPENDENT_ASSURANCE',
  'plan_digest',plan,'dispatch_scope','{}'::jsonb,'guard_code','ORCHESTRATOR_EXECUTION_GUARD_V1')::text,'UTF8'),'sha256'),'hex');
 INSERT INTO private.lf_orchestrator_dispatch_receipts_v1(orchestrator_execution_id,consumer_execution_id,capability_code,plan_digest,dispatch_scope,orchestrator_operation_code,orchestrator_operation_version,guard_code,receipt_sha256,issued_by_execution_id)
 VALUES(orch,p_judge,'INDEPENDENT_ASSURANCE',plan,'{}','ORQ_SANDBOX','1','ORCHESTRATOR_EXECUTION_GUARD_V1',sha,orch) RETURNING receipt_id INTO did;
 INSERT INTO public.lf_capability_binding(execution_id,capability_code,bound_version,bound_manifest_sha256,binding_mode,bound_by_execution_id,last_checked_by_execution_id)
 VALUES(p_judge,'INDEPENDENT_ASSURANCE','2.0.1',cms,'INITIAL',orch,orch);
 UPDATE public.lf_operation_execution SET target_type='PROGRAMMING_ANALYSIS_PACKAGE',target_code=ref,created_by_execution_id=orch,
  manifest=manifest||jsonb_build_object('producer_execution_id',c.created_by_execution_id,'subject_type','PROGRAMMING_ANALYSIS_PACKAGE',
  'source_head_sha',repeat('1',40),'subject_receipt_id',rid::text,'capability_manifest_sha256',cms,'plan_digest',plan,'orchestrator_execution_id',orch,
  'review_required',true,'runtime_activation',false,'production_activation',false,
  'capability_binding_receipt',jsonb_build_object('ready',true,'entry_guard',jsonb_build_object('ready',true,'receipt_id',did::text),'binding',jsonb_build_object('ready',true))) WHERE execution_id=p_judge;
 UPDATE public.lf_operation_execution_steps SET created_by_execution_id=p_judge WHERE execution_id=p_judge;
END $g$;
