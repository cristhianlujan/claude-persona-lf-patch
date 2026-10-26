-- Follow-up to positive profile continuation routing.
-- PR #3170 already returns CONTINUE / CONTINUE_WITH_RESTRICTIONS through ACT-0001.
-- This migration preserves the exact upstream profile artifact in that Router return so
-- the next governed profile can inspect the real output instead of reconstructing it.
BEGIN;

DO $precheck$
BEGIN
  IF md5(pg_get_functiondef(
       'public.lf_profile_result_router_return_classify_v1(jsonb,text,text,text)'::regprocedure
     )) <> 'ee6f300f092649d4c3f3d63b52005280' THEN
    RAISE EXCEPTION 'LF_PROFILE_CONTINUATION_ARTIFACT_SOURCE_DRIFT';
  END IF;
END
$precheck$;

DO $patch$
DECLARE
  d text;
  old_block text;
  new_block text;
BEGIN
  d:=pg_get_functiondef(
    'public.lf_profile_result_router_return_classify_v1(jsonb,text,text,text)'::regprocedure
  );

  old_block:=$old$
    v_payload:=jsonb_build_object(
      'profile_status',p_profile_output->>'status',
      'verdict',p_profile_output->>'verdict',
      'routing',v_routing,
      'blocking_codes',coalesce(p_profile_output->'blocking_codes','[]'::jsonb),
      'repair_actions',coalesce(p_profile_output->'repair_actions','[]'::jsonb),
      'remaining_risks',coalesce(p_profile_output->'remaining_risks','[]'::jsonb),
      'next_gate',p_profile_output->>'next_gate'
    );
  END IF;
$old$;

  new_block:=$new$
    v_payload:=jsonb_build_object(
      'profile_status',p_profile_output->>'status',
      'verdict',p_profile_output->>'verdict',
      'routing',v_routing,
      'blocking_codes',coalesce(p_profile_output->'blocking_codes','[]'::jsonb),
      'repair_actions',coalesce(p_profile_output->'repair_actions','[]'::jsonb),
      'remaining_risks',coalesce(p_profile_output->'remaining_risks','[]'::jsonb),
      'next_gate',p_profile_output->>'next_gate',
      'upstream_profile_output_sha256',
        'sha256:'||encode(
          extensions.digest(convert_to(p_profile_output::text,'UTF8'),'sha256'),
          'hex'
        ),
      'upstream_profile_output',p_profile_output
    );
  END IF;
$new$;

  IF (length(d)-length(replace(d,old_block,'')))/length(old_block)<>1 THEN
    RAISE EXCEPTION 'LF_PROFILE_CONTINUATION_ARTIFACT_PATCH_ANCHOR_DRIFT';
  END IF;

  d:=replace(d,old_block,new_block);
  EXECUTE d;
END
$patch$;

COMMENT ON FUNCTION public.lf_profile_result_router_return_classify_v1(jsonb,text,text,text) IS
'Classifies typed post-profile routing signals. RETURN_TO_ORCHESTRATOR and positive CONTINUE/CONTINUE_WITH_RESTRICTIONS transitions return through ACT-0001 Stage1; direct target_profile remains forbidden. Positive continuations carry the exact upstream profile output plus its canonical jsonb SHA-256 so the next governed profile can review the actual artifact.';

COMMENT ON FUNCTION public.lf_profile_result_router_return_prepare_v1(text) IS
'At terminal profile completion, prepares a fresh ACT-0001 Stage1 request for typed redirects and positive continuations. The classifier preserves the exact upstream profile artifact for positive continuation; no direct target_profile is honored.';

DO $postcheck$
DECLARE
  x jsonb;
  bad jsonb;
  terminal jsonb;
  expected_sha text;
  src text;
BEGIN
  x:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object(
      'status','PASS_WITH_RESTRICTIONS',
      'claim','Current value is evidenced; downstream quality review is required.',
      'authority_reads',jsonb_build_array(
        jsonb_build_object(
          'source_ref','supabase://lf_ops.politicas_sesion/1',
          'result','CURRENT_ROW_RESOLVED'
        )
      ),
      'source_readbacks',jsonb_build_array(
        jsonb_build_object(
          'source_ref','supabase://lf_ops.politicas_sesion/1',
          'observed',jsonb_build_object('idle_timeout_seconds',900)
        )
      ),
      'evidence_map',jsonb_build_array(
        jsonb_build_object(
          'assertion','900 seconds is current',
          'verdict','SUPPORTED'
        )
      ),
      'blocking_codes',jsonb_build_array('NO_CURRENT_AUTHORITY_FOR_1200_SECONDS'),
      'next_gate','QUALITY_REVIEW',
      'routing',jsonb_build_object(
        'activation_path','ROUTER',
        'via','ORCHESTRATOR',
        'pipeline_action','CONTINUE_WITH_RESTRICTIONS',
        'resolution_target','QUALITY_PACK'
      )
    ),
    'Analiza el timeout B2B sin modificar nada.',
    'POSTCHECK-EVIDENCE-CONTINUE-ARTIFACT',
    'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF'
  );

  expected_sha:='sha256:'||encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'status','PASS_WITH_RESTRICTIONS',
          'claim','Current value is evidenced; downstream quality review is required.',
          'authority_reads',jsonb_build_array(
            jsonb_build_object(
              'source_ref','supabase://lf_ops.politicas_sesion/1',
              'result','CURRENT_ROW_RESOLVED'
            )
          ),
          'source_readbacks',jsonb_build_array(
            jsonb_build_object(
              'source_ref','supabase://lf_ops.politicas_sesion/1',
              'observed',jsonb_build_object('idle_timeout_seconds',900)
            )
          ),
          'evidence_map',jsonb_build_array(
            jsonb_build_object(
              'assertion','900 seconds is current',
              'verdict','SUPPORTED'
            )
          ),
          'blocking_codes',jsonb_build_array('NO_CURRENT_AUTHORITY_FOR_1200_SECONDS'),
          'next_gate','QUALITY_REVIEW',
          'routing',jsonb_build_object(
            'activation_path','ROUTER',
            'via','ORCHESTRATOR',
            'pipeline_action','CONTINUE_WITH_RESTRICTIONS',
            'resolution_target','QUALITY_PACK'
          )
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  IF x->>'status' IS DISTINCT FROM 'RETURN_TO_ROUTER'
     OR x->>'redirect_kind' IS DISTINCT FROM 'PROFILE_CONTINUE_WITH_RESTRICTIONS'
     OR x->>'next_action' IS DISTINCT FROM 'REENTER_ROUTER_STAGE1'
     OR x#>>'{router_return_request,next_entrypoint}' IS DISTINCT FROM 'ACT-0001_STAGE1'
     OR x#>>'{router_return_request,unresolved_payload,routing,resolution_target}' IS DISTINCT FROM 'QUALITY_PACK'
     OR x#>>'{router_return_request,unresolved_payload,upstream_profile_output,status}' IS DISTINCT FROM 'PASS_WITH_RESTRICTIONS'
     OR x#>>'{router_return_request,unresolved_payload,upstream_profile_output,claim}' IS DISTINCT FROM 'Current value is evidenced; downstream quality review is required.'
     OR x#>>'{router_return_request,unresolved_payload,upstream_profile_output_sha256}' IS DISTINCT FROM expected_sha
     OR position(
          'Current value is evidenced; downstream quality review is required.'
          in x#>>'{router_return_request,stage1_literal}'
        )=0
  THEN
    RAISE EXCEPTION 'LF_PROFILE_CONTINUATION_ARTIFACT_REGRESSION:%',
      left(x::text,2600);
  END IF;

  bad:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object(
      'status','PASS_WITH_RESTRICTIONS',
      'target_profile','PERFIL-QUALITY-PACK',
      'routing',jsonb_build_object(
        'activation_path','ROUTER',
        'via','ORCHESTRATOR',
        'pipeline_action','CONTINUE_WITH_RESTRICTIONS',
        'resolution_target','QUALITY_PACK'
      )
    ),
    'No direct profile.',
    'POSTCHECK-CONTINUE-DIRECT-TARGET',
    'PERFIL-EVIDENCE-LINEAGE-REVIEWER-LF'
  );

  IF bad->>'status' IS DISTINCT FROM 'BLOCKED'
     OR bad->>'code' IS DISTINCT FROM 'PROFILE_RESULT_DIRECT_TARGET_PROFILE_FORBIDDEN'
  THEN
    RAISE EXCEPTION 'LF_PROFILE_CONTINUATION_DIRECT_TARGET_REGRESSION:%',bad;
  END IF;

  terminal:=public.lf_profile_result_router_return_classify_v1(
    jsonb_build_object(
      'status','PASS',
      'self_verdict','PASS',
      'output_type','PRODUCT_DIRECTION_SPEC'
    ),
    'Emit final decision.',
    'POSTCHECK-TERMINAL-UNCHANGED',
    'PERFIL-PRODUCT-DIRECTOR-LF'
  );

  IF terminal->>'status' IS DISTINCT FROM 'COMPLETE'
     OR terminal->>'next_action' IS DISTINCT FROM 'EMIT_PROFILE_RESULT'
  THEN
    RAISE EXCEPTION 'LF_PROFILE_CONTINUATION_TERMINAL_REGRESSION:%',terminal;
  END IF;

  src:=pg_get_functiondef(
    'public.lf_profile_result_router_return_classify_v1(jsonb,text,text,text)'::regprocedure
  );

  IF strpos(src,'upstream_profile_output')=0
     OR strpos(src,'upstream_profile_output_sha256')=0
     OR strpos(src,'''QUALITY_PACK''')>0
     OR strpos(src,'''COMPOSER''')>0
  THEN
    RAISE EXCEPTION 'LF_PROFILE_CONTINUATION_ARTIFACT_SOURCE_CONTRACT_REGRESSION';
  END IF;
END
$postcheck$;

COMMIT;
