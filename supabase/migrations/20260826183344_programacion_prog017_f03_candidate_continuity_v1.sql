-- PROG-017 / AUD24-F03 candidate continuity v1
DO $migration$
DECLARE
  v_def text;
  v_old text := $old$for b in select * from programacion.task_blockers where task_id=t.id and status='OPEN' loop
    v_ready:=false;$old$;
  v_new text := $new$for b in select * from programacion.task_blockers where task_id=t.id and status='OPEN' loop
    if not (
      b.blocker_code='AUD24_F03_EXTERNAL_HIDDEN_AUTHORITY_REQUIRED'
      and b.owner_type='INDEPENDENT_AUDITOR'
    ) then
      v_ready:=false;
    end if;$new$;
BEGIN
  SELECT pg_get_functiondef('programacion.fn_task_readiness(bigint)'::regprocedure) INTO v_def;
  IF strpos(v_def,v_old)=0 THEN RAISE EXCEPTION 'PROG017_READINESS_PATCH_SOURCE_MISMATCH'; END IF;
  IF strpos(replace(v_def,v_old,v_new),v_old)>0 THEN RAISE EXCEPTION 'PROG017_READINESS_PATCH_NOT_APPLIED'; END IF;
  EXECUTE replace(v_def,v_old,v_new);
END;
$migration$;

DO $migration$
DECLARE
  v_def text;
  v_anchor text := $old$      v_hidden_ok:=v_hidden_receipt_id is not null;$old$;
  v_new text := $new$      if v_hidden_receipt_id is null then
        select pr.id,pr.receipt_sha256 into v_hidden_receipt_id,v_hidden_receipt_sha256
        from programacion.provenance_receipts pr
        where pr.receipt_kind='AUDIT_VERDICT'
          and pr.execution_id is null
          and pr.head_sha=v_candidate_head_sha
          and pr.issuer_channel='F03_OIDC_AUDITOR_V1'
          and pr.subject_type='hidden_oracle_audit'
          and pr.subject_ref='agent-task://'||v_task.id::text||'/hidden-oracle'
          and pr.subject_sha256=v_hidden_subject_sha
          and pr.payload->>'finding_code'='AUD24-F03'
          and pr.payload->>'verdict'='PASS'
          and pr.payload->'independent'='true'::jsonb
          and length(btrim(coalesce(pr.payload->>'auditor_identity','')))>0
          and pr.payload->>'agent_task_id'=v_task.id::text
          and pr.payload->>'task_sha256'=coalesce(v_task.task_sha256,'')
          and pr.payload->>'target_execution_id'=v_execution_id::text
          and pr.payload->>'target_repo_full_name'=v_repo_full_name
          and pr.payload->>'target_head_sha'=v_candidate_head_sha
          and pr.payload->>'audited_head_sha'=v_candidate_head_sha
          and pr.payload->>'hidden_oracle_ref'=v_tc.hidden_oracle_ref
          and pr.payload->>'hidden_oracle_sha256'=v_tc.hidden_oracle_sha256
          and pr.payload->>'generation_source_sha256'=v_tc.generation_source_sha256
          and coalesce(pr.payload->>'receipt_contract_version','')~'^[0-9]+$'
          and (pr.payload->>'receipt_contract_version')::integer>=5
          and pr.payload->'semantic_nonreconstructibility_verified'='true'::jsonb
          and pr.payload->'replay_binding_verified'='true'::jsonb
          and pr.payload->'hidden_output_nonexposure_verified'='true'::jsonb
          and pr.payload->>'hidden_output'='HASH_ONLY'
          and pr.payload#>'{criteria_coverage,coverage_complete}'='true'::jsonb
          and pr.payload#>'{criteria_coverage,semantic_coverage_verified}'='true'::jsonb
        order by pr.id desc limit 1;
      end if;
      v_hidden_ok:=v_hidden_receipt_id is not null;$new$;
BEGIN
  SELECT pg_get_functiondef('programacion.fn_agent_task_worker_v10_authority_context_v2(bigint)'::regprocedure) INTO v_def;
  IF strpos(v_def,v_anchor)=0 THEN RAISE EXCEPTION 'PROG017_F03_CONSUMER_PATCH_SOURCE_MISMATCH'; END IF;
  EXECUTE replace(v_def,v_anchor,v_new);
END;
$migration$;

COMMENT ON FUNCTION programacion.fn_task_readiness(bigint)
IS 'Task readiness. PROG-017: AUD24-F03 independent-audit requirement remains visible in blockers but does not prevent materializing the candidate execution required to bind that audit; all other OPEN task blockers remain fail-closed.';

COMMENT ON FUNCTION programacion.fn_agent_task_worker_v10_authority_context_v2(bigint)
IS 'Worker v10 authority context. PROG-017/AUD24-F03: Acceptance/Delivery may consume only a provenance AUDIT_VERDICT contract >=5 already guarded and bound to the same execution, repo and candidate HEAD; hidden output remains HASH_ONLY.';