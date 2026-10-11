CREATE OR REPLACE FUNCTION programacion.fn_ig_m98_candidate_field_gate_v2(p_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path TO 'pg_catalog' AS $f$
DECLARE r record; pol jsonb; c jsonb; d jsonb; s jsonb; ok boolean; did uuid; producer jsonb; n int; k int; ord int:=0; current_source jsonb;
BEGIN
 IF p_id IS NULL THEN RETURN jsonb_build_object('status','BLOCKED','reason','PER_FIELD_RECEIPT_MISSING'); END IF;
 SELECT receipt_id,verification_state,verification_payload,receipt_payload,source_head_sha INTO r
 FROM private.lf_evidence_ledger_v1 WHERE receipt_id=p_id
 AND receipt_kind='IG_SHADOW_COMPARISON' AND gate_code='IG_SHADOW_CANDIDATE_COMPARE';
 IF NOT FOUND THEN RETURN jsonb_build_object('status','BLOCKED','reason','PRODUCER_RECEIPT_MISSING'); END IF;
 IF r.verification_state IS DISTINCT FROM 'VERIFIED'
 OR r.verification_payload->>'comparison_scope' IS DISTINCT FROM 'PER_FIELD_CURRENT_CANDIDATE'
 THEN RETURN jsonb_build_object('status','BLOCKED','reason','PRODUCER_UNVERIFIED_PER_FIELD'); END IF;
 SELECT to_jsonb(v) INTO producer FROM private.lf_evidence_ledger_v1 v WHERE v.receipt_id=p_id;
 IF r.verification_payload->>'provider_readback_verified' IS DISTINCT FROM 'true'
 OR r.verification_payload->>'digest_recomputed' IS DISTINCT FROM 'true'
 THEN RETURN jsonb_build_object('status','BLOCKED','reason','PRODUCER_READBACK_NOT_VERIFIED');END IF;
 c:=r.receipt_payload->'typed_evidence';
 IF c->>'source_head_sha' IS DISTINCT FROM r.source_head_sha
 THEN RETURN jsonb_build_object('status','BLOCKED','reason','PRODUCER_BINDING_MISMATCH'); END IF;
 IF c->>'schema_version' IS DISTINCT FROM 'IG_SHADOW_FIELD_DIFF_SET_V1'
 OR jsonb_typeof(c->'field_diffs') IS DISTINCT FROM 'array'
 OR c#>>'{coverage,status}' IS DISTINCT FROM 'COMPLETE'
 OR coalesce(c#>>'{coverage,difference_count}','') !~ '^[0-9]+$'
 OR (c#>>'{coverage,difference_count}')::integer<>jsonb_array_length(c->'field_diffs')
 OR coalesce(c#>>'{coverage,examined_field_count}','') !~ '^[1-9][0-9]*$'
 THEN RETURN jsonb_build_object('status','BLOCKED','reason','FIELD_UNIVERSE_NOT_VERIFIED');END IF;
 -- Current-source proof: no empty or old producer can satisfy a newer screen/run.
 IF coalesce(c->>'screen_id','') !~ '^[0-9]+$' OR coalesce(c->>'version_id','') !~ '^[0-9]+$'
 OR coalesce(c->>'run_id','') !~ '^[0-9]+$'
 OR coalesce(c->>'source_snapshot_sha256','') !~ '^[0-9a-f]{64}$'
 OR coalesce(c->>'canonical_shadow_sha256','') !~ '^[0-9a-f]{64}$'
 THEN RETURN jsonb_build_object('status','BLOCKED','reason','PRODUCER_SOURCE_SCOPE_INVALID');END IF;
 IF NOT EXISTS(SELECT 1 FROM programacion.input_readiness_runs run
 WHERE run.id=(c->>'run_id')::bigint AND run.pantalla_id=(c->>'screen_id')::int
 AND run.version_id=(c->>'version_id')::bigint
 AND run.status='COMPLETED' AND run.source_snapshot_sha256=c->>'source_snapshot_sha256'
 AND programacion.fn_input_readiness_run_is_current(run.id))
 THEN RETURN jsonb_build_object('status','BLOCKED','reason','PRODUCER_RUN_NOT_CURRENT');END IF;
 current_source:=programacion.fn_ig_m96_shadow_field_probe_v1((c->>'screen_id')::int,(c->>'version_id')::bigint);
 IF current_source->>'schema_version' IS DISTINCT FROM 'IG_M96_SHADOW_FIELD_OBSERVATION_V1'
 OR c->>'canonical_shadow_sha256' IS DISTINCT FROM current_source->>'canonical_shadow_sha256'
 OR jsonb_typeof(current_source->'field_diffs') IS DISTINCT FROM 'array'
 OR jsonb_array_length(current_source->'field_diffs')<>jsonb_array_length(c->'field_diffs')
 THEN RETURN jsonb_build_object('status','BLOCKED','reason','CURRENT_SHADOW_SCOPE_UNVERIFIED'); END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(current_source->'field_diffs') base(value)
 WHERE NOT EXISTS(SELECT 1 FROM jsonb_array_elements(c->'field_diffs') candidate(value)
 WHERE candidate.value->>'diff_ref'=base.value->>'diff_ref'
 AND candidate.value->>'diff_sha256'=base.value->>'diff_sha256'
 AND candidate.value->>'subject_scope'=base.value->>'subject_scope'
 AND candidate.value->>'current_sha256'=base.value->>'current_sha256'
 AND candidate.value->>'candidate_sha256'=base.value->>'candidate_sha256'))
 THEN RETURN jsonb_build_object('status','BLOCKED','reason','CURRENT_FIELD_DIFF_BINDING_MISMATCH');END IF;
 SELECT especificacion INTO pol FROM programacion.contratos WHERE contrato_codigo='INPUT_GOVERNANCE_DIVERGENCE_LEVELS_CONTRACT'
 ORDER BY version_id DESC,id DESC LIMIT 1;
 -- Read-only candidate qualification; not a requirement to activate the consumer.
 IF pol->>'status' IS DISTINCT FROM 'DECLARED_NOT_ACTIVATED'
 OR pol#>>'{technical_admission,status}' IS DISTINCT FROM 'VERIFIED_CANDIDATE'
 OR jsonb_typeof(pol->'declarations') IS DISTINCT FROM 'array'
 OR jsonb_array_length(coalesce(pol->'declarations','[]'::jsonb))=0
 THEN RETURN jsonb_build_object('status','BLOCKED','reason','CANDIDATE_FIELD_MAPPING_NOT_VERIFIED',
 'consumer_activation_required',false); END IF;
 FOR d IN SELECT value FROM jsonb_array_elements(c->'field_diffs') LOOP
  SELECT EXISTS(SELECT 1 FROM jsonb_array_elements(pol->'declarations') x
  WHERE x.value->>'consumer_code'=d->>'consumer_code'
  AND x.value->>'subject_scope'=d->>'subject_scope'
  AND x.value->>'field_path'=d->>'field_path'
  AND x.value->>'level_code'=d->>'level_code'
  AND x.value->>'policy_ref'=d->>'policy_ref'
  AND x.value->>'mapping_ref'=d->>'mapping_ref') INTO ok;
  IF NOT ok THEN RETURN jsonb_build_object('status','BLOCKED','reason','FIELD_MAPPING_MISSING','diff_ref',d->>'diff_ref'); END IF;
  ord:=ord+1;
  IF d->>'level_code' NOT IN ('D1','D2','D3','D5') THEN
   RETURN jsonb_build_object('status','BLOCKED','reason','D4_OR_UNCLASSIFIED');END IF;
  SELECT count(*),count(*) FILTER(WHERE programacion.fn_ig_m98_independent_receipt_match_v6(producer,d,to_jsonb(v))),
   min(v.receipt_id) FILTER(WHERE programacion.fn_ig_m98_independent_receipt_match_v6(producer,d,to_jsonb(v)))
   INTO n,k,did FROM private.lf_evidence_ledger_v1 v
   WHERE v.receipt_kind='IG_SHADOW_FIELD_ADJUDICATION' AND v.gate_code='IG_SHADOW_FIELD_ADJUDICATION'
   AND v.subject_ref=d->>'diff_ref' AND v.subject_sha256=d->>'diff_sha256'
   AND v.source_head_sha=r.source_head_sha;
  IF n<>1 OR k<>1 THEN
   RETURN jsonb_build_object('status','BLOCKED','reason','VERIFIED_INDEPENDENT_DECISION_MISSING_OR_AMBIGUOUS','diff_ref',d->>'diff_ref');END IF;
  c:=jsonb_set(c,ARRAY['field_diffs',(ord-1)::text,'decision_receipt_id'],to_jsonb(did::text),true);
 END LOOP;
 s:=programacion.fn_ig_m96_adjudication_structure_v1(c);
 IF s->>'status'<>'STRUCTURAL_READY_NOT_ADMITTED' THEN RETURN s;END IF;
 RETURN jsonb_build_object('status','TECHNICALLY_VERIFIED_NOT_RELEASED','verified_producer_receipt',p_id,'release_authorized',false);
END $f$;
