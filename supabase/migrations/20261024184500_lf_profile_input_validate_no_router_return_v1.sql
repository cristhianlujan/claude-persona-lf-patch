-- EJECUCION_PERFIL_LF: CONTEXT_PACK remains inside profile execution after Router authorization.
BEGIN;

DO $patch_context_pack_resume$
DECLARE
  v_def text;
  v_old text := $old$'resume_via', 'public.lf_router_resolve_v1'$old$;
  v_new text := $new$'resume_via', case when p_consumer='CONTEXT_PACK' then 'EJECUCION_PERFIL_LF/input_validate' else 'public.lf_router_resolve_v1' end$new$;
  v_count integer;
BEGIN
  IF md5(pg_get_functiondef(
       'programacion.fn_lf_router_input_governance_resolve_v1(text,jsonb,text)'::regprocedure
     )) <> '72e153a7fbfe7b10a8c9ae694a61b334' THEN
    RAISE EXCEPTION 'PROFILE_INPUT_VALIDATE_IG_SOURCE_DRIFT';
  END IF;

  v_def:=pg_get_functiondef(
    'programacion.fn_lf_router_input_governance_resolve_v1(text,jsonb,text)'::regprocedure
  );
  v_count:=(length(v_def)-length(replace(v_def,v_old,'')))/length(v_old);

  IF v_count<>2 THEN
    RAISE EXCEPTION 'PROFILE_INPUT_VALIDATE_IG_RESUME_ANCHOR_COUNT:%',v_count;
  END IF;

  v_def:=replace(v_def,v_old,v_new);
  EXECUTE v_def;
END
$patch_context_pack_resume$;

UPDATE public.lf_operation_step_contracts
SET next_if_blocked='RETURN_TO_WORKER',
    notes=concat_ws(
      ' | ',
      nullif(notes,''),
      'CONTEXT_PACK/INPUT_GOVERNANCE pending or blocked is handled by the profile execution worker; the same Router decision is not re-entered.'
    ),
    updated_at=now()
WHERE operation_code='EJECUCION_PERFIL_LF'
  AND step_id='input_validate';

UPDATE public.lf_operation_step_judge_bindings
SET return_result_value='RETURN_TO_WORKER',
    updated_at=now()
WHERE operation_code='EJECUCION_PERFIL_LF'
  AND step_id='input_validate';

DO $verify$
DECLARE
  v_ig jsonb;
  v_adapters jsonb;
  v_next text;
  v_judge_return text;
BEGIN
  SELECT coalesce(jsonb_agg(to_jsonb(x) order by x.adapter_code),'[]'::jsonb)
    INTO v_adapters
  FROM public.v_lf_router_adapter_bindings x
  WHERE x.target_asset_code='PERFIL-PRODUCT-DIRECTOR-LF';

  v_ig:=programacion.fn_lf_router_input_governance_resolve_v1(
    'Agregar pestañas al detalle y trazabilidad del lote B2B-CARGA-003.',
    v_adapters,
    'CONTEXT_PACK'
  );

  IF v_ig#>>'{dispatch,resume_via}' IS DISTINCT FROM 'EJECUCION_PERFIL_LF/input_validate'
     OR coalesce(v_ig->>'status','') NOT IN ('INPUT_GOVERNANCE_REQUIRED','READY','BLOCKED','HUMAN_DECISION_REQUIRED')
  THEN
    RAISE EXCEPTION 'PROFILE_INPUT_VALIDATE_IG_RESUME_READBACK_FAIL:%',v_ig;
  END IF;

  SELECT next_if_blocked INTO v_next
  FROM public.lf_operation_step_contracts
  WHERE operation_code='EJECUCION_PERFIL_LF' AND step_id='input_validate';

  SELECT return_result_value INTO v_judge_return
  FROM public.lf_operation_step_judge_bindings
  WHERE operation_code='EJECUCION_PERFIL_LF' AND step_id='input_validate';

  IF v_next IS DISTINCT FROM 'RETURN_TO_WORKER'
     OR v_judge_return IS DISTINCT FROM 'RETURN_TO_WORKER' THEN
    RAISE EXCEPTION
      'PROFILE_INPUT_VALIDATE_CONTRACT_RETURN_FAIL:next=% judge=%',
      v_next,v_judge_return;
  END IF;
END
$verify$;

COMMIT;
