-- LF #3779 Lote 3 | sandbox candidate only. NOT approved for production.
-- Reuses original request/decide/apply/guard; same rows, NO new table/Router/IG.
BEGIN;
DO $source_guards$
BEGIN
 IF md5(pg_get_functiondef('public.lf_rule_promotion_request_v1(text,text,text)'::regprocedure))
 IS DISTINCT FROM '2fcac9f18b1581985af93639e475cd1a'
 OR md5(pg_get_functiondef('public.lf_rule_promotion_decide_v1(text,text,text,text)'::regprocedure))
 IS DISTINCT FROM '16e45f40dad5cecc215a2f978be47728'
 OR md5(pg_get_functiondef('public.lf_rule_promotion_apply_v1(text)'::regprocedure))
 IS DISTINCT FROM 'd7fe763c999db6f6259b6b1e2bd69644'
 OR md5(pg_get_functiondef('public.lf_rule_promotion_guard_v1()'::regprocedure))
 IS DISTINCT FROM 'ee782e4bd0128c80ee13881899c0d74e'
 THEN RAISE EXCEPTION 'BLOCK_RULE_PROMOTION_LIVE_SOURCE_MD5_DRIFT'; END IF;
END $source_guards$;
ALTER TABLE public.lf_rule_promotion_v1
 ADD COLUMN judge_receipt jsonb,
 ADD COLUMN judge_receipt_sha256 text,
 ADD COLUMN decision_route text;


-- Source-first deterministic judge. Its output is a REAL database evaluation
-- receipt, NOT an independent semantic/human review receipt.
CREATE FUNCTION public.lf_rule_promotion_quality_judge_v1(p_promotion_id text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','public','lf_ops','extensions'
AS $quality$
DECLARE
 p public.lf_rule_promotion_v1%ROWTYPE;
 r lf_ops.reglas%ROWTYPE;
 e public.lf_operation_execution%ROWTYPE;
 step40 jsonb;
 step70 jsonb;
 conf jsonb;
 deps jsonb;
 policy record;
 v_decision record;
 v_decision_sha text;
 v_blocks text[]:=ARRAY[]::text[];
 v_class text;
 v_scope text;
 v_rule_sha text;
 v_policy_sha text;
 v_deps_sha text;
 v_origin text;
 v_owner text;
 v_human_required boolean:=false;
BEGIN
 SELECT * INTO p FROM public.lf_rule_promotion_v1 WHERE promotion_id=p_promotion_id;
 IF NOT FOUND THEN RETURN jsonb_build_object('classification','BLOCKED',
  'blocking_codes',jsonb_build_array('PROMOTION_NOT_FOUND')); END IF;
 SELECT * INTO r FROM lf_ops.reglas WHERE codigo=p.rule_code;
 IF NOT FOUND THEN RETURN jsonb_build_object('classification','BLOCKED',
  'blocking_codes',jsonb_build_array('RULE_NOT_FOUND')); END IF;
 SELECT * INTO e FROM public.lf_operation_execution
   WHERE execution_id=p.request_execution_id AND operation_code='EJECUCION_PERFIL_LF';
 SELECT evidence_payload INTO step40 FROM public.lf_operation_execution_steps
   WHERE execution_id=p.request_execution_id AND step_id='input_validate'
     AND status='STEP_PASS_WITH_EVIDENCE';
 SELECT evidence_payload INTO step70 FROM public.lf_operation_execution_steps
   WHERE execution_id=p.request_execution_id AND step_id='semantic_judge'
     AND status='STEP_PASS_WITH_EVIDENCE';
 conf:=COALESCE(r.valor_config,'{}'::jsonb);
 v_rule_sha:=public.lf_asset_snapshot_sha_v1('REGLA',r.codigo);
 v_owner:=to_jsonb(r)->>'owner_name';
 v_origin:=nullif(btrim(coalesce(r.origen,'')),'');
 IF p.status NOT IN ('PENDING','APPROVED') OR r.estado<>'CANDIDATO'
   THEN v_blocks:=array_append(v_blocks,'NOT_PENDING_CANDIDATE'); END IF;
 IF v_rule_sha IS DISTINCT FROM p.request_snapshot_sha256
   THEN v_blocks:=array_append(v_blocks,'RULE_SNAPSHOT_CHANGED'); END IF;
 IF v_owner IS DISTINCT FROM 'LF_GOVERNANCE'
   THEN v_blocks:=array_append(v_blocks,'FUNCTIONAL_OWNER_MISSING_OR_WRONG'); END IF;
 -- An ID asserted in the candidate is NOT sufficient: bind it to an
 -- approved and identity-matching record in the canonical decision ledger.
 IF v_origin IS NULL OR
   COALESCE((conf->>'source_decision_number') ~ '^[1-9][0-9]*$',false)=false
 THEN v_blocks:=array_append(v_blocks,'PARAMETER_PROVENANCE_NOT_ATTESTED');
 ELSE
   SELECT id_decision,decision_number,estado_normalizado,raw_payload
   INTO v_decision FROM public.lf_decisiones_gov
   WHERE decision_number=(conf->>'source_decision_number')::bigint
     AND estado_normalizado IN ('VIGENTE','APROBADA')
     AND id_decision=v_origin;
   IF NOT FOUND THEN
      v_blocks:=array_append(v_blocks,'CANONICAL_DECISION_SOURCE_NOT_APPROVED');
   ELSE
      -- A valid decision number can still refer to a DIFFERENT rule.
      -- Require an explicit canonical rule-code binding before auto approval.
      IF v_decision.raw_payload->>'rule_code' IS DISTINCT FROM r.codigo
         AND NOT (
           jsonb_typeof(v_decision.raw_payload->'rule_codes')='array'
           AND (v_decision.raw_payload->'rule_codes') ? r.codigo)
      THEN v_blocks:=array_append(v_blocks,'CANONICAL_DECISION_RULE_BINDING_MISSING');
      END IF;
      v_decision_sha:=encode(extensions.digest(convert_to(
         to_jsonb(v_decision)::text,'UTF8'),'sha256'),'hex');
   END IF;
 END IF;
 -- Sensitive numeric parameters require an explicit per-rule provenance
 -- reference that matches that authoritative decision, not a bare number.
 IF EXISTS(SELECT 1 FROM jsonb_each(conf) f(key,value)
       WHERE jsonb_typeof(f.value)='number' AND f.key<>'source_decision_number')
   AND NOT (
     jsonb_typeof(conf->'parameter_provenance')='object'
     AND conf#>>'{parameter_provenance,source_ref}'=v_origin
     AND conf#>>'{parameter_provenance,verified}'='true')
 THEN v_blocks:=array_append(v_blocks,'NUMERIC_PARAMETER_SOURCE_NOT_ATTESTED');
 END IF;
 IF conf ? 'numeric_thresholds_in_rule' AND conf->>'numeric_thresholds_in_rule'='DENY'
    AND EXISTS (SELECT 1 FROM jsonb_object_keys(conf) f(name)
                WHERE f.name LIKE '%timeout_seconds%' OR f.name LIKE '%rate_limit_count%')
 THEN v_blocks:=array_append(v_blocks,'NUMERIC_SECURITY_PARAMETER_BYPASS'); END IF;
 IF e.execution_id IS NULL OR e.status<>'IN_PROGRESS'
    OR e.target_code<>'PERFIL-PRODUCT-DIRECTOR-LF'
    OR e.manifest->>'read_only' IS DISTINCT FROM 'true'
    OR e.manifest->>'no_write' IS DISTINCT FROM 'true'
    OR e.manifest#>>'{router_profile_handoff,scope,target_type}' IS DISTINCT FROM 'REGLA'
    OR e.manifest#>>'{router_profile_handoff,scope,resolution_status}' IS DISTINCT FROM 'RESOLVED'
    OR e.manifest#>>'{router_profile_handoff,scope,target_hint}' IS DISTINCT FROM r.codigo
 THEN v_blocks:=array_append(v_blocks,'PRODUCT_DIRECTOR_RULE_SCOPE_NOT_ATTESTED'); END IF;
 IF NOT EXISTS(SELECT 1 FROM public.lf_profile_write_authority_v1 a
      WHERE a.profile_code=e.target_code AND a.operation_code='PROMOCION_REGLA_LF'
        AND a.status='ACTIVE')
 THEN v_blocks:=array_append(v_blocks,'PROMOTION_OPERATION_AUTHORITY_MISSING'); END IF;
 IF step40#>>'{input_governance,status}' IS DISTINCT FROM 'READY'
    OR step40#>>'{input_governance,scope_type}' IS DISTINCT FROM 'REGLA'
    OR step40#>>'{input_governance,scope_mode}' IS DISTINCT FROM 'ONE_CANONICAL_RULE'
    OR step40#>>'{input_governance,rule_code}' IS DISTINCT FROM r.codigo
    OR step40#>>'{input_governance,rule_source_sha256}' IS DISTINCT FROM v_rule_sha
    OR step40#>>'{input_governance,source_scope_validated}' IS DISTINCT FROM 'true'
 THEN v_blocks:=array_append(v_blocks,'STEP40_SOURCE_CURRENTNESS_SCOPE_NOT_VERIFIED'); END IF;
 IF step70#>>'{semantic_judge_result,status}' IS DISTINCT FROM 'PASS'
    OR step70#>'{semantic_judge_result,unsupported_claims}' IS DISTINCT FROM '[]'::jsonb
    OR step70#>>'{semantic_judge_result,verdict}'
       NOT IN ('PASS_INDEPENDENT_SEMANTIC','PASS_REVIEWED_CURRENT_CONTEXT')
 THEN v_blocks:=array_append(v_blocks,'PARENT_JUDGE_NOT_CLEAN'); END IF;
 -- Only declared canonical rule dependencies are consumed; unknown formats block.
 deps:=COALESCE(conf->'depends_on_rules','[]'::jsonb);
 IF jsonb_typeof(deps)<>'array' OR EXISTS (
   SELECT 1 FROM jsonb_array_elements(deps) d(value)
    WHERE jsonb_typeof(d.value)<>'string'
 ) THEN
   v_blocks:=array_append(v_blocks,'RULE_DEPENDENCY_SCHEMA_UNRESOLVED');
   deps:='[]'::jsonb;
 ELSE
   IF EXISTS(SELECT 1 FROM jsonb_array_elements_text(deps) d(code)
     LEFT JOIN lf_ops.reglas dep ON dep.codigo=d.code
     WHERE dep.id IS NULL OR dep.estado<>'VIGENTE')
   THEN v_blocks:=array_append(v_blocks,'RULE_DEPENDENCY_NOT_VIGENTE'); END IF;
   IF EXISTS(SELECT 1 FROM lf_ops.reglas v
       WHERE v.estado='VIGENTE' AND v.codigo<>r.codigo
         AND jsonb_typeof(v.valor_config->'depends_on_rules')='array'
         AND (v.valor_config->'depends_on_rules') ? r.codigo)
   THEN v_blocks:=array_append(v_blocks,'VIGENTE_DEPENDS_ON_CANDIDATO'); END IF;
 END IF;
 v_deps_sha:=encode(extensions.digest(convert_to(deps::text,'UTF8'),'sha256'),'hex');
 IF conf->>'auth_bypass'='true' OR conf->>'rls_bypass'='true'
    OR conf->>'skip_security_checks'='true'
    OR conf->>'allow_unauthenticated'='true'
    OR conf->>'disable_rate_limit'='true'
    OR conf->>'client_direct_operational_table_access'='ALLOW'
 THEN v_blocks:=array_append(v_blocks,'OBVIOUS_SECURITY_BYPASS'); END IF;
 IF nullif(conf->>'security_policy_code','') IS NOT NULL THEN
   SELECT policy_code,policy_config,status INTO policy FROM lf_ops.politicas_seguridad
     WHERE policy_code=conf->>'security_policy_code';
   IF NOT FOUND OR policy.status<>'VIGENTE' THEN
     v_blocks:=array_append(v_blocks,'CANONICAL_SECURITY_POLICY_NOT_VIGENTE');
   ELSE
     IF EXISTS(SELECT 1 FROM jsonb_object_keys(policy.policy_config) item(key)
       WHERE item.key NOT IN ('deny_by_default','server_side_enforcement',
                              'rls_policy_required','cross_tenant_access'))
     THEN v_blocks:=array_append(v_blocks,'SECURITY_POLICY_CHECK_COVERAGE_INCOMPLETE'); END IF;
     IF (policy.policy_config->>'deny_by_default'='true'
          AND conf->>'deny_by_default'='false')
       OR (policy.policy_config->>'server_side_enforcement'='true'
          AND conf->>'server_side_enforcement'='false')
       OR (policy.policy_config->>'rls_policy_required'='true'
          AND conf->>'rls_policy_required'='false')
       OR (policy.policy_config->>'cross_tenant_access'='DENY'
          AND conf->>'cross_tenant_access'='ALLOW')
     THEN v_blocks:=array_append(v_blocks,'VIGENTE_SECURITY_POLICY_CONFLICT'); END IF;
   END IF;
 END IF;
 v_policy_sha:=encode(extensions.digest(convert_to(COALESCE(
    (SELECT jsonb_agg(jsonb_build_object(
      'policy_code',s.policy_code,'status',s.status,
      'policy_config',s.policy_config) ORDER BY s.policy_code)
      FROM lf_ops.politicas_seguridad s WHERE s.status='VIGENTE'),
    '[]'::jsonb)::text,'UTF8'),'sha256'),'hex');
 -- HUMAN route is classified ONLY from the approved canonical decision,
 -- never from a free-form value in the candidate rule.
 v_human_required:=coalesce(v_decision.raw_payload->>'authority_class','')='HUMAN_ONLY';
 v_class:=CASE WHEN cardinality(v_blocks)>0 THEN 'BLOCKED'
      WHEN v_human_required THEN 'HUMAN_DECISION_REQUIRED'
      ELSE 'AUTO_APPROVABLE' END;
 RETURN jsonb_build_object(
   'schema_version','LF_RULE_PROMOTION_QUALITY_JUDGE_V1',
   'classification',v_class,'blocking_codes',to_jsonb(v_blocks),
   'promotion_id',p_promotion_id,'rule_code',r.codigo,
   'request_execution_id',p.request_execution_id,
   'requester_profile',p.requested_by_profile,
   'judge_actor','LF_RULE_PROMOTION_DETERMINISTIC_JUDGE_V1',
   'source_snapshot_sha256',v_rule_sha,
   'request_snapshot_sha256',p.request_snapshot_sha256,
   'owner_name',v_owner,'source_decision_sha256',v_decision_sha,
   'dependency_sha256',v_deps_sha,
   'security_policy_set_sha256',v_policy_sha,
   'scope_verified',NOT('PRODUCT_DIRECTOR_RULE_SCOPE_NOT_ATTESTED'=ANY(v_blocks)),
   'source_current',v_rule_sha IS NOT DISTINCT FROM p.request_snapshot_sha256,
   'deterministic_receipt_generated',true,
   'independent_semantic_judge_attested',false,
   'authenticated_human_authority_attested',false);
END $quality$;
REVOKE ALL ON FUNCTION public.lf_rule_promotion_quality_judge_v1(text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_quality_judge_v1(text) TO service_role;

CREATE FUNCTION public.lf_rule_promotion_governed_decide_v1(
 p_promotion_id text,p_decider_actor text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','public','extensions','lf_ops'
AS $governed$
DECLARE p public.lf_rule_promotion_v1%ROWTYPE;
  judgement jsonb; v_sha text; actor constant text:='LF_RULE_PROMOTION_DETERMINISTIC_JUDGE_V1';
BEGIN
 SELECT * INTO p FROM public.lf_rule_promotion_v1
  WHERE promotion_id=p_promotion_id FOR UPDATE;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_FOUND'); END IF;
 IF p.status<>'PENDING' THEN RETURN jsonb_build_object(
  'status','BLOCKED','blocking_code','PROMOTION_NOT_PENDING'); END IF;
 IF p_decider_actor IS DISTINCT FROM actor
    OR p_decider_actor=p.requested_by_profile
    OR p_decider_actor=p.request_execution_id
 THEN RETURN jsonb_build_object('status','BLOCKED',
   'blocking_code','DECIDER_NOT_SEPARATE_FROM_REQUESTER'); END IF;
 judgement:=public.lf_rule_promotion_quality_judge_v1(p_promotion_id);
 v_sha:=encode(extensions.digest(convert_to(judgement::text,'UTF8'),'sha256'),'hex');
 UPDATE public.lf_rule_promotion_v1 SET judge_receipt=judgement,
   judge_receipt_sha256=v_sha,
   decision_route=judgement->>'classification'
 WHERE promotion_id=p_promotion_id;
 IF judgement->>'classification'<>'AUTO_APPROVABLE' THEN
   RETURN jsonb_build_object('status',CASE WHEN judgement->>'classification'=
    'HUMAN_DECISION_REQUIRED' THEN 'HUMAN_DECISION_REQUIRED' ELSE 'BLOCKED' END,
    'blocking_codes',judgement->'blocking_codes',
    'judge_receipt_sha256',v_sha,'promotion_id',p_promotion_id,
    'independent_semantic_judge_attested',false);
 END IF;
 UPDATE public.lf_rule_promotion_v1
 SET status='APPROVED',decided_by=actor,decided_at=now()
 WHERE promotion_id=p_promotion_id AND status='PENDING';
 RETURN jsonb_build_object('status','APPROVED',
   'promotion_id',p_promotion_id,'decided_by',actor,
   'judge_receipt_sha256',v_sha,
   'independent_semantic_judge_attested',false);
END $governed$;
REVOKE ALL ON FUNCTION public.lf_rule_promotion_governed_decide_v1(text,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_governed_decide_v1(text,text)
 TO service_role;

CREATE OR REPLACE FUNCTION public.lf_rule_promotion_request_v1(p_execution_id text, p_rule_code text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare par record; r record; v_sha text; v_id text;
begin
 select * into par from public.lf_operation_execution e where e.execution_id=p_execution_id and e.operation_code='EJECUCION_PERFIL_LF' and e.status='IN_PROGRESS';
 if not found then return jsonb_build_object('status','BLOCKED','blocking_code','PARENT_EXECUTION_NOT_ACTIVE'); end if;
 if not exists(select 1 from public.lf_profile_write_authority_v1 a where a.profile_code=par.target_code and a.operation_code='PROMOCION_REGLA_LF' and a.status='ACTIVE') then
  return jsonb_build_object('status','BLOCKED','blocking_code','PROFILE_NOT_AUTHORIZED_FOR_PROMOTION','profile',par.target_code); end if;
 select * into r from lf_ops.reglas where codigo=p_rule_code;
 if not found then return jsonb_build_object('status','BLOCKED','blocking_code','RULE_NOT_FOUND'); end if;
 if r.estado<>'CANDIDATO' then return jsonb_build_object('status','BLOCKED','blocking_code','RULE_NOT_CANDIDATE','estado',r.estado); end if;
 if exists(select 1 from public.lf_rule_promotion_v1 p where p.rule_code=p_rule_code and p.status in ('PENDING','APPROVED')) then
  return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_ALREADY_OPEN'); end if;
 if nullif(btrim(p_reason),'') is null then return jsonb_build_object('status','BLOCKED','blocking_code','REASON_REQUIRED'); end if;
 v_sha := public.lf_asset_snapshot_sha_v1('REGLA',p_rule_code);
 insert into public.lf_rule_promotion_v1(rule_code,request_execution_id,requested_by_profile,request_snapshot_sha256,reason) values(p_rule_code,p_execution_id,par.target_code,v_sha,p_reason) returning promotion_id into v_id;
 return jsonb_build_object('status','PENDING_GOVERNED_DECISION','promotion_id',v_id,'snapshot_sha256',v_sha,'next_action','Requiere lf_rule_promotion_governed_decide_v1 y evidencia determinista; HUMAN solo ante autoridad real');
end $function$
;
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_decide_v1(p_promotion_id text, p_decision text, p_decided_by text, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare p record;
begin
 if p_decided_by is null or p_decided_by !~ '^HUMAN:.+' then return jsonb_build_object('status','BLOCKED','blocking_code','APPROVER_MUST_BE_HUMAN'); end if;
 if p_decision not in ('APPROVE','REJECT') then return jsonb_build_object('status','BLOCKED','blocking_code','DECISION_INVALID'); end if;
 select * into p from public.lf_rule_promotion_v1 where promotion_id=p_promotion_id for update;
 if not found then return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_FOUND'); end if;
 if p.status<>'PENDING' then return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_PENDING','estado',p.status); end if;
 if p.decision_route IS DISTINCT FROM 'HUMAN_DECISION_REQUIRED' THEN
  return jsonb_build_object('status','BLOCKED','blocking_code','HUMAN_NOT_REQUIRED_FOR_THIS_RULE'); END IF;
 -- An arbitrary HUMAN: string cannot substitute authentication.
 return jsonb_build_object('status','BLOCKED',
   'blocking_code','AUTHENTICATED_HUMAN_RECEIPT_REQUIRED');
 if p_decision='APPROVE' and public.lf_asset_snapshot_sha_v1('REGLA',p.rule_code) is distinct from p.request_snapshot_sha256 then
  update public.lf_rule_promotion_v1 set status='STALE' where promotion_id=p_promotion_id;
  return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_STALE'); end if;
 update public.lf_rule_promotion_v1 set status=case p_decision when 'APPROVE' then 'APPROVED' else 'REJECTED' end, decided_by=p_decided_by, decided_at=now(), reason=coalesce(reason,'')||' | '||coalesce(p_note,'') where promotion_id=p_promotion_id;
 return jsonb_build_object('status',case p_decision when 'APPROVE' then 'APPROVED' else 'REJECTED' end,'promotion_id',p_promotion_id);
end $function$
;
CREATE OR REPLACE FUNCTION public.lf_rule_promotion_apply_v1(p_promotion_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare p record;
begin
 select * into p from public.lf_rule_promotion_v1 where promotion_id=p_promotion_id for update;
 if not found then return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_FOUND'); end if;
 if p.status<>'APPROVED' then return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_NOT_APPROVED','estado',p.status); end if;
 if p.decided_by IS DISTINCT FROM 'LF_RULE_PROMOTION_DETERMINISTIC_JUDGE_V1'
    OR p.decision_route IS DISTINCT FROM 'AUTO_APPROVABLE'
    OR p.judge_receipt IS NULL
    OR p.judge_receipt_sha256 IS DISTINCT FROM encode(
         extensions.digest(convert_to(p.judge_receipt::text,'UTF8'),'sha256'),'hex')
    OR p.judge_receipt IS DISTINCT FROM
         public.lf_rule_promotion_quality_judge_v1(p_promotion_id)
 THEN RETURN jsonb_build_object('status','BLOCKED',
     'blocking_code','PROMOTION_JUDGE_RECEIPT_NOT_CURRENT'); END IF;
 if public.lf_asset_snapshot_sha_v1('REGLA',p.rule_code) is distinct from p.request_snapshot_sha256 then
  update public.lf_rule_promotion_v1 set status='STALE' where promotion_id=p_promotion_id;
  return jsonb_build_object('status','BLOCKED','blocking_code','PROMOTION_STALE'); end if;
 update lf_ops.reglas set estado='VIGENTE' where codigo=p.rule_code and estado='CANDIDATO';
 if NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED',
   'blocking_code','PROMOTION_RULE_ROW_NOT_CANDIDATE'); END IF;
 update public.lf_rule_promotion_v1 set status='APPLIED', applied_at=now() where promotion_id=p_promotion_id;
 return jsonb_build_object('status','APPLIED','rule_code',p.rule_code);
end $function$
;
REVOKE ALL ON FUNCTION public.lf_rule_promotion_request_v1(text,text,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.lf_rule_promotion_decide_v1(text,text,text,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.lf_rule_promotion_apply_v1(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_request_v1(text,text,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_decide_v1(text,text,text,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.lf_rule_promotion_apply_v1(text) TO service_role;
COMMIT;
