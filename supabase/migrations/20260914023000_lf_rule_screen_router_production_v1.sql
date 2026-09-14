-- Production integration for governed rule <-> screen relation capability.
-- Scope: router binding + controlled production promotion only.

DO $pre$
DECLARE
  v_status text;
  v_router_count integer;
BEGIN
  SELECT status INTO v_status
  FROM public.lf_operation_registry
  WHERE operation_code='VINCULACION_REGLA_PANTALLA_LF';

  IF v_status IS DISTINCT FROM 'SANDBOX_ACTIVE' THEN
    RAISE EXCEPTION 'LF_RULE_SCREEN_PROD_EXPECTED_SANDBOX_ACTIVE:%',v_status;
  END IF;

  SELECT count(*) INTO v_router_count
  FROM public.lf_router_action_registry
  WHERE operation_code='VINCULACION_REGLA_PANTALLA_LF';

  IF v_router_count<>0 THEN
    RAISE EXCEPTION 'LF_RULE_SCREEN_PROD_ROUTER_ALREADY_BOUND:%',v_router_count;
  END IF;

  IF to_regprocedure('public.lf_regla_pantalla_link_v1(text,text,integer,text)') IS NULL THEN
    RAISE EXCEPTION 'LF_RULE_SCREEN_PROD_HELPER_MISSING';
  END IF;
END
$pre$;

UPDATE public.lf_operation_contracts
SET status='SUPERSEDED_INTEGRATION',
    updated_by_execution_id='EXEC-VINCULACION-REGLA-PANTALLA-PROD-PROMOTION-20260914-001',
    updated_at=now()
WHERE operation_code='VINCULACION_REGLA_PANTALLA_LF'
  AND contract_code='CONTRACT-VINCULACION-REGLA-PANTALLA-LF-v1.0.0'
  AND status='ACTIVE_ENFORCEMENT';

INSERT INTO public.lf_operation_contracts(
  operation_code,contract_code,contract_path,contract_sha,required_before_write,
  allowed,blocked,required_after_write,status,created_by_execution_id
) VALUES (
  'VINCULACION_REGLA_PANTALLA_LF',
  'CONTRACT-VINCULACION-REGLA-PANTALLA-LF-v1.1.0',
  'supabase://public/lf_operation_contracts/CONTRACT-VINCULACION-REGLA-PANTALLA-LF-v1.1.0',
  null,
  '["ekb_preflight","execution_bound","router_resolved","exact_rule_identity","exact_screen_identity","unique_relation_guard"]'::jsonb,
  '{"destination":"lf_ops.reglas_pantallas","idempotent_insert":true,"accepted_observed_rule_states":["CANDIDATO","VIGENTE"],"observe_screen_active_without_new_restriction":true,"rule_mutation":false,"screen_mutation":false,"router_binding":true,"production_controlled":true,"automatic_consumer_integration":true}'::jsonb,
  '{"relation_delete":true,"rule_mutation":true,"screen_mutation":true,"rule_promotion":true,"runtime_activation":true}'::jsonb,
  '["exact_relation_readback","rule_unchanged","screen_unchanged","single_relation","no_delete","no_promotion","router_binding_active"]'::jsonb,
  'ACTIVE_ENFORCEMENT',
  'EXEC-VINCULACION-REGLA-PANTALLA-PROD-PROMOTION-20260914-001'
);

UPDATE public.lf_operation_step_contracts
SET contract_code='CONTRACT-VINCULACION-REGLA-PANTALLA-LF-v1.1.0',
    updated_by_execution_id='EXEC-VINCULACION-REGLA-PANTALLA-PROD-PROMOTION-20260914-001',
    updated_at=now()
WHERE operation_code='VINCULACION_REGLA_PANTALLA_LF'
  AND status='ACTIVE_ENFORCEMENT';

INSERT INTO public.lf_router_action_registry(
  asset_type,action_code,operation_code,operation_resolution,
  requires_existing_target,requires_missing_target,write_allowed,status,notes,
  created_by_execution_id
) VALUES (
  'REGLA_PANTALLA_RELATION','REGLA_PANTALLA_LINK','VINCULACION_REGLA_PANTALLA_LF','STATIC',
  false,false,true,'ACTIVE',
  'Rule/screen identities and eligibility are resolved inside the governed relation operation; idempotent INSERT only.',
  'EXEC-VINCULACION-REGLA-PANTALLA-PROD-PROMOTION-20260914-001'
);

DO $router_patch$
DECLARE
  v_def text;
  v_new text;
  p_type text := $p$elsif v_req ~ '(^| )(policy|politica|regla)( |$)' then v_type_hint := 'REGLA';$p$;
  r_type text := $p$elsif v_req ~ '(^| )(vincula|vincular|enlaza|enlazar|asocia|asociar|relaciona|relacionar|relacion|link)( |$)' and v_req ~ '(^| )(regla|policy)( |$)' and v_req ~ '(^| )(pantalla|screen)( |$)' then v_type_hint := 'REGLA_PANTALLA_RELATION';
    elsif v_req ~ '(^| )(policy|politica|regla)( |$)' then v_type_hint := 'REGLA';$p$;
  p_action text := $p$if v_req ~ '(^| )(consulta|consultar|estado|metadata|existe)( |$)' then v_action:='ASSET_INSPECTION';$p$;
  r_action text := $p$if v_req ~ '(^| )(consulta|consultar|estado|metadata|existe)( |$)' then v_action:='ASSET_INSPECTION';
    elsif v_type_hint='REGLA_PANTALLA_RELATION' and v_req ~ '(^| )(vincula|vincular|enlaza|enlazar|asocia|asociar|relaciona|relacionar|relacion|link)( |$)' then v_action:='REGLA_PANTALLA_LINK';$p$;
BEGIN
  SELECT pg_get_functiondef('public.lf_router_resolve_v1(text,text,text,text,text)'::regprocedure) INTO v_def;
  IF strpos(v_def,p_type)=0 OR strpos(v_def,p_action)=0 THEN
    RAISE EXCEPTION 'LF_RULE_SCREEN_PROD_ROUTER_SOURCE_DRIFT';
  END IF;
  v_new:=replace(replace(v_def,p_type,r_type),p_action,r_action);
  EXECUTE v_new;
END
$router_patch$;

DO $helper_patch$
DECLARE
  v_def text;
  v_new text;
BEGIN
  SELECT pg_get_functiondef('public.lf_regla_pantalla_link_v1(text,text,integer,text)'::regprocedure) INTO v_def;
  IF strpos(v_def,'''production_authorized'',false')=0 THEN
    RAISE EXCEPTION 'LF_RULE_SCREEN_PROD_HELPER_SOURCE_DRIFT';
  END IF;
  v_new:=replace(v_def,'''production_authorized'',false','''production_authorized'',true');
  EXECUTE v_new;
END
$helper_patch$;

UPDATE public.lf_operation_registry
SET version='v1.1.0',
    status='PRODUCCION_CONTROLADA',
    source_paths='["public.lf_router_resolve_v1","public.lf_router_action_registry","lf_ops.reglas","lf_ops.pantallas","lf_ops.reglas_pantallas","public.lf_regla_pantalla_link_v1"]'::jsonb,
    notes='Durable governed idempotent rule-screen relation capability. ACT-0001 Router binding active in controlled production; no DELETE and no rule/screen mutation.',
    updated_by_execution_id='EXEC-VINCULACION-REGLA-PANTALLA-PROD-PROMOTION-20260914-001',
    updated_at=now()
WHERE operation_code='VINCULACION_REGLA_PANTALLA_LF';

DO $post$
DECLARE
  v jsonb;
  c integer;
BEGIN
  SELECT count(*) INTO c
  FROM public.lf_router_action_registry
  WHERE asset_type='REGLA_PANTALLA_RELATION'
    AND action_code='REGLA_PANTALLA_LINK'
    AND operation_code='VINCULACION_REGLA_PANTALLA_LF'
    AND status='ACTIVE' AND write_allowed;
  IF c<>1 THEN RAISE EXCEPTION 'LF_RULE_SCREEN_PROD_ROUTER_BINDING_FAIL:%',c; END IF;

  IF (SELECT status FROM public.lf_operation_registry WHERE operation_code='VINCULACION_REGLA_PANTALLA_LF')<>'PRODUCCION_CONTROLADA' THEN
    RAISE EXCEPTION 'LF_RULE_SCREEN_PROD_STATUS_FAIL';
  END IF;

  SELECT count(*) INTO c
  FROM public.lf_operation_contracts
  WHERE operation_code='VINCULACION_REGLA_PANTALLA_LF'
    AND contract_code='CONTRACT-VINCULACION-REGLA-PANTALLA-LF-v1.1.0'
    AND status='ACTIVE_ENFORCEMENT'
    AND coalesce((allowed->>'router_binding')::boolean,false)
    AND coalesce((allowed->>'production_controlled')::boolean,false);
  IF c<>1 THEN RAISE EXCEPTION 'LF_RULE_SCREEN_PROD_CONTRACT_FAIL:%',c; END IF;

  v:=public.lf_router_resolve_v1('vincular regla con pantalla',null,null,null,'ROUTER');
  IF v->>'status'<>'READY_TO_EXECUTE'
     OR v->>'asset_type'<>'REGLA_PANTALLA_RELATION'
     OR v->>'action_code'<>'REGLA_PANTALLA_LINK'
     OR v->>'operation_code'<>'VINCULACION_REGLA_PANTALLA_LF' THEN
    RAISE EXCEPTION 'LF_RULE_SCREEN_PROD_NATURAL_ROUTE_FAIL:%',v;
  END IF;

  v:=public.lf_router_resolve_v1('vincular regla con pantalla',null,'REGLA_PANTALLA_LINK','REGLA_PANTALLA_RELATION','ROUTER');
  IF v->>'status'<>'READY_TO_EXECUTE' OR v->>'operation_code'<>'VINCULACION_REGLA_PANTALLA_LF' THEN
    RAISE EXCEPTION 'LF_RULE_SCREEN_PROD_EXPLICIT_ROUTE_FAIL:%',v;
  END IF;

  IF strpos(pg_get_functiondef('public.lf_regla_pantalla_link_v1(text,text,integer,text)'::regprocedure),'''production_authorized'',true')=0 THEN
    RAISE EXCEPTION 'LF_RULE_SCREEN_PROD_HELPER_FLAG_FAIL';
  END IF;
END
$post$;

UPDATE public.lf_operation_execution
SET status='COMPLETED',
    completed_at=now(),
    manifest=manifest||jsonb_build_object(
      'result','RULE_SCREEN_ROUTER_PRODUCTION_ACTIVATED',
      'router_binding','REGLA_PANTALLA_LINK',
      'operation_status','PRODUCCION_CONTROLADA',
      'production_authorized',true
    ),
    updated_by_execution_id='EXEC-VINCULACION-REGLA-PANTALLA-PROD-PROMOTION-20260914-001',
    updated_at=now()
WHERE execution_id='EXEC-VINCULACION-REGLA-PANTALLA-PROD-PROMOTION-20260914-001';

UPDATE public.lf_operation_execution
SET status='COMPLETED',
    completed_at=now(),
    manifest=manifest||jsonb_build_object(
      'result','RULE_SCREEN_ROUTER_PRODUCTION_MIGRATION_APPLIED',
      'migration','20260914023000_lf_rule_screen_router_production_v1',
      'production_authorized',true
    ),
    updated_by_execution_id='EXEC-ACTUALIZACION-DB-RULE-SCREEN-ROUTER-PROD-20260914-001',
    updated_at=now()
WHERE execution_id='EXEC-ACTUALIZACION-DB-RULE-SCREEN-ROUTER-PROD-20260914-001';
