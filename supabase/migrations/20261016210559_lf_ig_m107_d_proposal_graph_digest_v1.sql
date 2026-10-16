DO $pre$ BEGIN
 IF (SELECT md5(pg_get_functiondef(p.oid)) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='programacion' AND p.proname='fn_guard_input_gap_proposal_update_v512')
 IS DISTINCT FROM 'ca77e15ccbf7692654daf7a560adedae' THEN RAISE EXCEPTION 'IG_M107_D_PROPOSAL_GUARD_DRIFT'; END IF;
 IF (SELECT md5(pg_get_functiondef(p.oid)) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='programacion' AND p.proname='fn_input_governance_validate_gap_proposals_v1')
 IS DISTINCT FROM '0e7796945fd392a6123529147b8fcde2' THEN RAISE EXCEPTION 'IG_M107_D_VALIDATOR_DRIFT'; END IF;
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo IN
 ('IG-M107-C-SEMANTIC-GRAPH-CONDITIONAL-035','IG-M107-B-ACTIVE-GUARD-ONEPASS-033'))<>2
 THEN RAISE EXCEPTION 'IG_M107_D_PRIOR_EKB_MISSING'; END IF;
 IF (SELECT count(*) FROM pg_trigger WHERE tgrelid='programacion.input_gap_proposals'::regclass
 AND NOT tgisinternal AND tgenabled IN ('O','A') AND (tgtype&16)=16)<>2
 THEN RAISE EXCEPTION 'IG_M107_D_PROPOSAL_TRIGGERS_MISSING'; END IF;
END $pre$;
CREATE OR REPLACE FUNCTION programacion.fn_ig_m107_d_proposal_bundle_v1(p_run_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'pg_catalog','programacion'
AS $function$
DECLARE v_manifest jsonb; v_bundle jsonb;
BEGIN
 v_manifest:=programacion.fn_input_build_source_manifest(p_run_id);
 v_bundle:=programacion.fn_ig_m107_bundle_from_manifest_v1(p_run_id,v_manifest);
 RETURN v_bundle||jsonb_build_object('manifest_receipts',v_manifest);
END;
$function$;
CREATE OR REPLACE FUNCTION programacion.fn_guard_input_gap_proposal_update_v512()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion'
AS $function$
declare
  v_run record;
  v_payload jsonb;
  v_ref jsonb;
  v_observed jsonb;
  v_readbacks jsonb := '[]'::jsonb;
  v_bundle jsonb;
  v_graph_sha text;
  v_graph_count integer;
  v_direct_mode boolean;
begin
  if new.run_id is distinct from old.run_id or new.assessment_id is distinct from old.assessment_id or new.family_code is distinct from old.family_code or new.gap_code is distinct from old.gap_code or new.proposal_kind is distinct from old.proposal_kind or new.proposed_payload is distinct from old.proposed_payload or new.canonical_target is distinct from old.canonical_target or new.source_refs is distinct from old.source_refs or new.evidence_refs is distinct from old.evidence_refs or new.confidence is distinct from old.confidence or new.stage_impact is distinct from old.stage_impact or new.contradictions_checked is distinct from old.contradictions_checked or new.curator_identity is distinct from old.curator_identity or new.curator_execution_id is distinct from old.curator_execution_id or new.curator_sha256 is distinct from old.curator_sha256 or new.created_at is distinct from old.created_at then
    raise exception 'V512_PROPOSAL_CURATOR_FIELDS_IMMUTABLE:%',old.id;
  end if;
  if old.validator_outcome<>'PENDING' then raise exception 'V512_PROPOSAL_VALIDATOR_RECEIPT_IMMUTABLE:%',old.id; end if;
  v_bundle:=programacion.fn_ig_m107_d_proposal_bundle_v1(old.run_id);
  IF coalesce((v_bundle#>>'{g1,continuation_current}')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'INPUT_GOVERNANCE_CONTINUATION_CURRENTNESS_BLOCKED:table=%:run=%:code=%',
      TG_TABLE_NAME,old.run_id,coalesce(v_bundle#>>'{g1,code}','CURRENTNESS_UNKNOWN');
  END IF;
  if new.validator_outcome='PENDING' then raise exception 'V512_PROPOSAL_VALIDATION_MUST_BE_TERMINAL:%',old.id; end if;
  select * into v_run from programacion.input_readiness_runs where id=old.run_id;
  if v_run.status<>'VALIDATING' then raise exception 'V512_PROPOSAL_VALIDATOR_REQUIRES_VALIDATING_RUN:%',old.run_id; end if;
  if new.validator_identity is null or new.validator_identity=v_run.curator_identity or new.validator_identity is distinct from v_run.validator_identity then
    raise exception 'V512_PROPOSAL_VALIDATOR_NOT_INDEPENDENT:%',old.id;
  end if;
  if new.validator_evidence='{}'::jsonb then raise exception 'V512_PROPOSAL_VALIDATOR_EVIDENCE_REQUIRED:%',old.id; end if;
  if coalesce((new.validator_evidence->>'direct_source_readback')::boolean,false) is not true then raise exception 'V512_PROPOSAL_DIRECT_SOURCE_READBACK_REQUIRED:%',old.id; end if;
  if new.validator_evidence->>'source_snapshot_sha256' is distinct from v_run.source_snapshot_sha256 then raise exception 'V512_PROPOSAL_SOURCE_SNAPSHOT_MISMATCH:%',old.id; end if;

  if coalesce((v_bundle->>'full_manifest_current')::boolean,false) IS NOT TRUE then
    raise exception 'V512_PROPOSAL_SOURCE_SNAPSHOT_STALE:%',old.id;
  end if;

  v_direct_mode:=coalesce(new.validator_evidence->>'source_readback_scheme','LEGACY')='DIRECT_GRAPH_SHA_V1';
  if new.validator_evidence ? 'source_readback_scheme' and not v_direct_mode then
    raise exception 'V512_PROPOSAL_SOURCE_READBACK_SCHEME_UNSUPPORTED:%',old.id;
  end if;
  if v_direct_mode then
    select count(*),max(e->>'observed_sha256') into v_graph_count,v_graph_sha
    from jsonb_array_elements(v_bundle->'manifest_receipts') e
    where e->'ref'='{"kind":"SCREEN_CANONICAL_GRAPH"}'::jsonb;
    if v_graph_count<>1 or v_graph_sha !~ '^[0-9a-f]{64}$' then
      raise exception 'V512_PROPOSAL_GRAPH_RECEIPT_MISSING:%',old.id;
    end if;
  end if;
  for v_ref in select value from jsonb_array_elements(old.source_refs)
  loop
    if coalesce(v_ref->>'kind','')='INPUT_GAP_PROPOSAL' then raise exception 'V512_PROPOSAL_CANNOT_VALIDATE_FROM_PROPOSAL_SOURCE:%',old.id; end if;
    if v_direct_mode and v_ref->>'kind'='SCREEN_CANONICAL_GRAPH' then
      if not (v_ref?'pantalla_id')
        or (v_ref->>'pantalla_id')::integer is distinct from v_run.pantalla_id then
        raise exception 'SCREEN_CANONICAL_GRAPH_REQUIRES_EXPLICIT_PANTALLA_ID:%',v_run.pantalla_id;
      end if;
    else
      v_observed:=programacion.fn_input_resolve_source_ref(v_ref,v_run.pantalla_id,v_run.version_id);
    end if;
    v_readbacks:=v_readbacks || jsonb_build_array(jsonb_build_object(
      'source_ref',v_ref,
      'source_observed_sha256',case when v_direct_mode and v_ref->>'kind'='SCREEN_CANONICAL_GRAPH'
      then v_graph_sha else programacion.fn_v09_sha256_jsonb(v_observed) end
    ));
  end loop;
  if new.validator_evidence->'source_readbacks' is distinct from v_readbacks then
    raise exception 'V512_PROPOSAL_SOURCE_READBACK_DIGEST_MISMATCH:%',old.id;
  end if;

  if new.validator_outcome='PASS' and new.status not in ('VALIDATED','HUMAN_DECISION_REQUIRED') then raise exception 'V512_PROPOSAL_PASS_STATUS_INVALID:%',old.id; end if;
  if new.validator_outcome='FAIL' and new.status<>'REJECTED' then raise exception 'V512_PROPOSAL_FAIL_STATUS_INVALID:%',old.id; end if;
  new.validated_at:=coalesce(new.validated_at,now());
  v_payload:=jsonb_build_object('curator_sha256',old.curator_sha256,'validator_identity',new.validator_identity,'validator_outcome',new.validator_outcome,'validator_evidence',new.validator_evidence,'status',new.status,'validated_at',new.validated_at);
  new.validator_sha256:=programacion.fn_v09_sha256_jsonb(v_payload);
  return new;
end;
$function$;
CREATE OR REPLACE FUNCTION programacion.fn_input_governance_validate_gap_proposals_v1(p_run_id bigint, p_validator_identity text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'programacion'
AS $function$
declare
  v_run record;
  p record;
  r jsonb;
  u record;
  v_obs jsonb;
  v_readbacks jsonb;
  v_cache jsonb:='{}'::jsonb;
  v_key text;
  v_count int:=0;
  v_human int:=0;
begin
  select * into v_run from programacion.input_readiness_runs where id=p_run_id;
  if not found then raise exception 'INPUT_REMEDIATION_VALIDATE_RUN_NOT_FOUND:%',p_run_id; end if;
  if v_run.status<>'VALIDATING' then raise exception 'INPUT_REMEDIATION_VALIDATE_REQUIRES_VALIDATING:%',p_run_id; end if;
  if p_validator_identity is distinct from v_run.validator_identity or p_validator_identity=v_run.curator_identity then raise exception 'INPUT_REMEDIATION_VALIDATOR_IDENTITY_INVALID:%',p_run_id; end if;
  for u in
    select distinct r.value as source_ref
    from programacion.input_gap_proposals gp
    cross join lateral jsonb_array_elements(coalesce(gp.source_refs,'[]'::jsonb)) r(value)
    where gp.run_id=p_run_id and gp.validator_outcome='PENDING'
  loop
    v_key:=u.source_ref::text;
    v_obs:=programacion.fn_input_resolve_source_ref(u.source_ref,v_run.pantalla_id,v_run.version_id);
    v_cache:=v_cache||jsonb_build_object(v_key,v_obs);
  end loop;
  for p in select * from programacion.input_gap_proposals where run_id=p_run_id and validator_outcome='PENDING' order by id loop
    v_readbacks:='[]'::jsonb;
    for r in select value from jsonb_array_elements(p.source_refs) loop
      v_key:=r::text;
      if not (v_cache ? v_key) then raise exception 'INPUT_REMEDIATION_SOURCE_CACHE_MISS:%',v_key; end if;
      v_obs:=v_cache->v_key;
      v_readbacks:=v_readbacks||jsonb_build_array(jsonb_build_object('source_ref',r,'source_observed_sha256',case when r->>'kind'='SCREEN_CANONICAL_GRAPH'
      then v_obs->>'observed_sha256' else programacion.fn_v09_sha256_jsonb(v_obs) end));
    end loop;
    update programacion.input_gap_proposals set validator_identity=p_validator_identity,validator_outcome='PASS',status=case when proposal_kind='HUMAN_DECISION_REQUIRED' then 'HUMAN_DECISION_REQUIRED' else 'VALIDATED' end,
      validator_evidence=jsonb_build_object('direct_source_readback',true,'source_snapshot_sha256',v_run.source_snapshot_sha256,'source_readback_scheme','DIRECT_GRAPH_SHA_V1','source_readbacks',v_readbacks,'analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX','proposal_is_canonical_source',false,'automatic_canonicalization','DENY'),validated_at=now() where id=p.id;
    v_count:=v_count+1;
    if p.proposal_kind='HUMAN_DECISION_REQUIRED' then v_human:=v_human+1; end if;
  end loop;
  return jsonb_build_object('run_id',p_run_id,'validated_proposal_count',v_count,'human_decision_required_count',v_human,'analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX');
end;
$function$;
DO $post$ BEGIN
 IF position('fn_ig_m107_d_proposal_bundle_v1' in pg_get_functiondef(
    'programacion.fn_guard_input_gap_proposal_update_v512()'::regprocedure))=0
 OR position('V512_PROPOSAL_SOURCE_READBACK_DIGEST_MISMATCH' in pg_get_functiondef(
    'programacion.fn_guard_input_gap_proposal_update_v512()'::regprocedure))=0
 OR position('full_manifest_current' in pg_get_functiondef(
    'programacion.fn_guard_input_gap_proposal_update_v512()'::regprocedure))=0
 OR position('source_readback_scheme' in pg_get_functiondef(
    'programacion.fn_input_governance_validate_gap_proposals_v1(bigint,text)'::regprocedure))=0
 OR (SELECT count(*) FROM pg_trigger WHERE tgrelid='programacion.input_gap_proposals'::regclass
 AND NOT tgisinternal AND tgenabled IN ('O','A') AND (tgtype&16)=16)<>2
 THEN RAISE EXCEPTION 'IG_M107_D_REQUIRED_GUARDS_NOT_PRESERVED'; END IF;
END $post$;


-- Executed inside the Migration Train's exact-version transaction. The
-- synthetic validator run rolls back; only the EKB evidence survives.
DO $test$
DECLARE
 v_curator jsonb; v_id bigint; v_run programacion.input_readiness_runs%rowtype;
 v_validator text; v_component bigint; v_one record; v_bad jsonb; v_err text;
 v_result jsonb; v_refs_count integer; v_graph_count integer;
 v_graph_sha text; v_graph_match integer:=0; v_other_match integer:=0;
 v_pre_count integer; v_trigger_count integer;
BEGIN
 IF (SELECT max(id) FROM programacion.input_readiness_runs WHERE pantalla_id=43)<>933
  OR (SELECT status FROM programacion.input_readiness_runs WHERE id=933)<>'COMPLETED'
 THEN RAISE EXCEPTION 'IG_M107_D_HISTORICAL_SOURCE_CHANGED'; END IF;
 SELECT count(*) INTO v_pre_count FROM programacion.input_readiness_runs WHERE pantalla_id=43;
 BEGIN
  v_curator:=programacion.fn_input_governance_direct_step_v1(43,'MANUAL');
  IF v_curator->>'status' IS DISTINCT FROM 'VALIDATOR_RUNTIME_REQUIRED'
   OR v_curator->>'step' IS DISTINCT FROM 'CURATOR_MATERIALIZED' THEN
   RAISE EXCEPTION 'IG_M107_D_CURATOR_TEST_SETUP_FAILED:%',left(v_curator::text,300); END IF;
  v_id:=(v_curator->>'run_id')::bigint;
  SELECT * INTO STRICT v_run FROM programacion.input_readiness_runs WHERE id=v_id;
  IF v_run.status<>'CURATING' THEN RAISE EXCEPTION 'IG_M107_D_TEST_RUN_INVALID'; END IF;
  SELECT id INTO STRICT v_component FROM programacion.componentes
   WHERE version_id=v_run.version_id AND componente_codigo='INPUT_VALIDATOR';
  v_validator:='INPUT_VALIDATOR:SQL:ig-governed-dispatch-v1:'||gen_random_uuid()::text;
  UPDATE programacion.input_readiness_runs SET status='VALIDATING',
    validator_identity=v_validator,validator_component_id=v_component WHERE id=v_id;
  SELECT * INTO STRICT v_run FROM programacion.input_readiness_runs WHERE id=v_id;
  SELECT count(*),count(*) FILTER (WHERE source_refs->0->>'kind'='SCREEN_CANONICAL_GRAPH')
    INTO v_refs_count,v_graph_count FROM programacion.input_gap_proposals
    WHERE run_id=v_id AND validator_outcome='PENDING';
  IF v_refs_count<>20 OR v_graph_count<>19 THEN
    RAISE EXCEPTION 'IG_M107_D_PROPOSAL_COHORT_DRIFT:%:%',v_refs_count,v_graph_count; END IF;
  SELECT id,source_refs INTO STRICT v_one
  FROM programacion.input_gap_proposals
  WHERE run_id=v_id AND source_refs->0->>'kind'='SCREEN_CANONICAL_GRAPH'
  ORDER BY id LIMIT 1;
  v_bad:=jsonb_build_object(
    'direct_source_readback',true,'source_snapshot_sha256',v_run.source_snapshot_sha256,
    'source_readback_scheme','DIRECT_GRAPH_SHA_V1',
    'source_readbacks',jsonb_build_array(jsonb_build_object(
        'source_ref',v_one.source_refs->0,
        'source_observed_sha256',repeat('0',64))),
    'analysis_revision','INPUT_GOV_REMEDIATION_1_4_SAFE_AUTOFIX',
    'proposal_is_canonical_source',false,'automatic_canonicalization','DENY'
  );
  BEGIN
    UPDATE programacion.input_gap_proposals SET validator_identity=v_validator,
      validator_outcome='PASS',status='VALIDATED',validator_evidence=v_bad,
      validated_at=clock_timestamp() WHERE id=v_one.id;
  EXCEPTION WHEN OTHERS THEN v_err:=SQLERRM; END;
  IF position('V512_PROPOSAL_SOURCE_READBACK_DIGEST_MISMATCH' in coalesce(v_err,''))=0
    OR (SELECT validator_outcome FROM programacion.input_gap_proposals WHERE id=v_one.id)<>'PENDING'
  THEN RAISE EXCEPTION 'IG_M107_D_FALSE_SHA_NOT_REJECTED:%',v_err; END IF;

  v_result:=programacion.fn_input_governance_validate_gap_proposals_v1(v_id,v_validator);
  IF (v_result->>'validated_proposal_count')::integer<>v_refs_count THEN
    RAISE EXCEPTION 'IG_M107_D_BATCH_VALIDATION_FAILED:%',left(v_result::text,350); END IF;
  SELECT m->>'observed_sha256' INTO STRICT v_graph_sha
    FROM jsonb_array_elements(v_run.source_manifest) m
    WHERE m->'ref'='{"kind":"SCREEN_CANONICAL_GRAPH"}'::jsonb;
  SELECT count(*) FILTER (
    WHERE ref->'source_ref'->>'kind'='SCREEN_CANONICAL_GRAPH'
       AND ref->>'source_observed_sha256'=v_graph_sha),
    count(*) FILTER (
    WHERE ref->'source_ref'->>'kind'='SCREEN_STATE_SET'
       AND (ref->>'source_observed_sha256') ~ '^[0-9a-f]{64}$')
    INTO v_graph_match,v_other_match
  FROM programacion.input_gap_proposals p
  CROSS JOIN LATERAL jsonb_array_elements(p.validator_evidence->'source_readbacks') ref
  WHERE p.run_id=v_id AND p.validator_outcome='PASS'
    AND p.validator_evidence->>'source_readback_scheme'='DIRECT_GRAPH_SHA_V1';
  IF v_graph_match<>19 OR v_other_match<>1 THEN
    RAISE EXCEPTION 'IG_M107_D_MANIFEST_PROPOSAL_SHA_MISMATCH:%:%',v_graph_match,v_other_match;
  END IF;
  SELECT count(*) INTO v_trigger_count FROM pg_trigger
    WHERE tgrelid='programacion.input_gap_proposals'::regclass
      AND NOT tgisinternal AND tgenabled IN ('O','A') AND (tgtype&16)=16;
  IF v_trigger_count<>2 THEN RAISE EXCEPTION 'IG_M107_D_TRIGGER_COVERAGE_INVALID'; END IF;

  RAISE EXCEPTION 'IG_M107_D_REVERT_TEMP_RUN' USING ERRCODE='PZ127';
 EXCEPTION WHEN SQLSTATE 'PZ127' THEN NULL;
 END;
 IF (SELECT count(*) FROM programacion.input_readiness_runs WHERE pantalla_id=43)<>v_pre_count
   OR EXISTS(SELECT 1 FROM programacion.input_readiness_runs WHERE id=v_id)
   OR EXISTS(SELECT 1 FROM programacion.input_gap_proposals WHERE run_id=v_id)
   OR EXISTS(SELECT 1 FROM programacion.input_family_assessments WHERE run_id=v_id)
   OR v_graph_match<>19 OR v_other_match<>1 OR v_trigger_count<>2
 THEN RAISE EXCEPTION 'IG_M107_D_ROLLBACK_NOT_CLEAN'; END IF;

 INSERT INTO public.lf_error_knowledge(
 id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
 severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,evidencia,
 created_at,updated_at,lifecycle_phase,root_cause_family,detectability,source_context,source_ref)
 VALUES(gen_random_uuid(),'IG-M107-D-PROPOSAL-GRAPH-RECEIPT-036','GOVERNANCE',
 'M10.7 lote D: reuso SHA de grafo del manifiesto vigente dentro de UPDATE de propuesta',
 'El guard conserva manifiesto completo actual, currentness, identidad y validación de fuentes. Para las referencias de grafo usa su SHA calculado en ese manifiesto, sin segunda reconstrucción.',
 '19 referencias al mismo grafo ocasionaban una segunda reconstrucción por propuesta además de la construcción del manifiesto independiente por UPDATE.',
 'PROPOSAL_SAME_UPDATE_MANIFEST_GRAPH_DIGEST_REUSE',
 'No compartir datos entre propuestas, transacciones o runs. Verificar pantalla/ref y hashes; conservar modo legacy, referencias de otras clases, dos triggers y rechazo fail-closed.',
 'Train: 20 propuestas PASS en un solo run temporal; 19 SHA del grafo coinciden con manifiesto y 1 referencia de estado conserva verificación independiente; SHA falso rechazado; rollback limpio; dos triggers activos.',
 'MEDIUM',1,clock_timestamp(),clock_timestamp(),'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7/LOT_D',
 'ACTIVO',jsonb_build_object(
   'schema_version','IG_M107_D_PROPOSAL_GRAPH_SHA_V1',
   'screen_id',43,'run_id_rolled_back',v_id,
   'proposals_passed',v_refs_count,
   'graph_digest_matches',v_graph_match,'other_ref_matches',v_other_match,
   'source_sha_tamper_rejected',true,'source_sha_error',v_err,
   'proposal_update_triggers_active',v_trigger_count,
   'rollback_clean',true,'no_cross_update_cache',true,
   'validator_p90_measured',false,'CP3_closed',false)::text,
 clock_timestamp(),clock_timestamp(),'VALIDATION','R5_EROSION_PROCESO',
 'LOUD_EARLY','One screen synthetic rollback, 20 proposals',
 'supabase/migrations/20261017001000_lf_ig_m107_d_proposal_graph_digest_v1.sql');
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo='IG-M107-D-PROPOSAL-GRAPH-RECEIPT-036')<>1
 THEN RAISE EXCEPTION 'IG_M107_D_EKB_NOT_PERSISTED'; END IF;
END $test$;
