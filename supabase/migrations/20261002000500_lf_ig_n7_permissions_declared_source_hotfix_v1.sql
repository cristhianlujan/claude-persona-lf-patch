-- IG_CURATOR_VALIDATOR_REFACTOR_V2 · N-7 / PAULO-172 closure hotfix
-- Screens 52, 53, 54 and 56 already declare SCREEN_CANONICAL_GRAPH as the
-- governed source for PERMISSIONS and VISUAL_EVIDENCE.
-- Keep strengthened PERMISSIONS semantics on canonical_contract.rules and
-- preserve each prior VISUAL_EVIDENCE assertion instead of introducing an
-- undeclared CURRENT_VISUAL_ARTIFACT authority during rebind.

do $hotfix$
declare
  v_def text := pg_get_functiondef('programacion.fn_input_v512_assertion_template(integer,text,jsonb)'::regprocedure);
  v_new text;
begin
  if md5(v_def) <> '495ce1f56c22c8f10a19ff3ff565bdfa' then
    raise exception 'IG_N7_DECLARED_SOURCE_BASELINE_DRIFT:%', md5(v_def);
  end if;

  v_new := replace(
    v_def,
$old$  if p_family_code='MFA_OTP_SSO' and p_pantalla_id=52 then
$old$,
$new$  if p_family_code='VISUAL_EVIDENCE' and p_pantalla_id in (52,53,54,56) then
    v:=p_assertion;
  elsif p_family_code='MFA_OTP_SSO' and p_pantalla_id=52 then
$new$
  );
  if v_new = v_def then
    raise exception 'IG_N7_DECLARED_SOURCE_VISUAL_ANCHOR_NOT_FOUND';
  end if;
  v_def := v_new;

  v_new := replace(
    v_def,
$old$  elsif p_family_code='PERMISSIONS' and p_pantalla_id=52 then
    v:=jsonb_build_object('source_ref',jsonb_build_object('kind','RULE','codigo','B2B-RULE-AUTH-028'),'path',jsonb_build_array('observed','valor_config'),'operator','CONTAINS','expected','{"operational_access_grant":"DENY","authentication_completion":"DENY","operational_session_creation":"DENY"}'::jsonb);
$old$,
$new$  elsif p_family_code='PERMISSIONS' and p_pantalla_id=52 then
    v:=jsonb_build_object('source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',52),'path',jsonb_build_array('observed','canonical_contract','rules'),'operator','CONTAINS','expected','[{"rule_code":"B2B-RULE-AUTH-028","config":{"operational_access_grant":"DENY","authentication_completion":"DENY","operational_session_creation":"DENY"}}]'::jsonb);
$new$
  );
  if v_new = v_def then
    raise exception 'IG_N7_DECLARED_SOURCE_PERMISSIONS_52_ANCHOR_NOT_FOUND';
  end if;
  v_def := v_new;

  v_new := replace(
    v_def,
$old$  elsif p_family_code='PERMISSIONS' and p_pantalla_id in (53,56) then
    v:=jsonb_build_object('source_ref',jsonb_build_object('kind','RULE','codigo','B2B-RULE-AUTH-029'),'path',jsonb_build_array('observed','valor_config'),'operator','CONTAINS','expected','{"recovery_context_scope":"PASSWORD_UPDATE_ONLY","operational_authorization_before_completion":"DENY"}'::jsonb);
$old$,
$new$  elsif p_family_code='PERMISSIONS' and p_pantalla_id in (53,56) then
    v:=jsonb_build_object('source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',p_pantalla_id),'path',jsonb_build_array('observed','canonical_contract','rules'),'operator','CONTAINS','expected','[{"rule_code":"B2B-RULE-AUTH-029","config":{"recovery_context_scope":"PASSWORD_UPDATE_ONLY","operational_authorization_before_completion":"DENY"}}]'::jsonb);
$new$
  );
  if v_new = v_def then
    raise exception 'IG_N7_DECLARED_SOURCE_PERMISSIONS_5356_ANCHOR_NOT_FOUND';
  end if;
  v_def := v_new;

  v_new := replace(
    v_def,
$old$  elsif p_family_code='PERMISSIONS' and p_pantalla_id=54 then
    v:=jsonb_build_object('source_ref',jsonb_build_object('kind','RULE','codigo','B2B-RULE-AUTH-033'),'path',jsonb_build_array('observed','valor_config'),'operator','CONTAINS','expected','{"mfa_route_full_operational_session_required":false,"mfa_route_direct_navigation_without_challenge":"DENY"}'::jsonb);
$old$,
$new$  elsif p_family_code='PERMISSIONS' and p_pantalla_id=54 then
    v:=jsonb_build_object('source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',54),'path',jsonb_build_array('observed','canonical_contract','rules'),'operator','CONTAINS','expected','[{"rule_code":"B2B-RULE-AUTH-033","config":{"mfa_route_full_operational_session_required":false,"mfa_route_direct_navigation_without_challenge":"DENY"}}]'::jsonb);
$new$
  );
  if v_new = v_def then
    raise exception 'IG_N7_DECLARED_SOURCE_PERMISSIONS_54_ANCHOR_NOT_FOUND';
  end if;

  execute v_new;
end;
$hotfix$;

comment on function programacion.fn_input_v512_assertion_template(integer,text,jsonb) is
  'N-7 closure hotfix: screens 52/53/54/56 preserve declared SCREEN_CANONICAL_GRAPH authority; VISUAL_EVIDENCE keeps its prior canonical evidence assertion and PERMISSIONS asserts strengthened rule semantics through canonical_contract.rules.';
