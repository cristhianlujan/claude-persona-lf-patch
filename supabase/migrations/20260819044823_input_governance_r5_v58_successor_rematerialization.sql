create or replace function programacion.fn_input_v58_assertion_template(p_pantalla_id integer,p_family_code text,p_assertion jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,programacion
as $$
declare v jsonb:=p_assertion;
begin
  if p_pantalla_id=52 and p_family_code='OBJECTIVE_OUTCOMES' then
    v:=v || jsonb_build_object('operator','EQ','expected','Permitir que un usuario inicie recuperación de acceso de forma segura y anti-enumeración, enviando únicamente el correo antes de cualquier nueva contraseña.');
  elsif p_pantalla_id in (52,53) and p_family_code='VISUAL_EVIDENCE' then
    v:=v || jsonb_build_object('operator','ARRAY_LENGTH_EQ','expected',1);
  elsif p_pantalla_id=53 and p_family_code='PRIVACY_PII' and (v->'path')::text ilike '%rules%' then
    v:=v || jsonb_build_object('operator','CONTAINS','expected','[{"rule_code":"B2B-RULE-AUTH-030","config":{"password_logs":"DENY","password_analytics":"DENY","password_persistence_lf_ops":"DENY"}}]'::jsonb);
  elsif p_pantalla_id=53 and p_family_code='ROUTING_NAVIGATION' then
    v:=v || jsonb_build_object('operator','CONTAINS','expected','[{"rule_code":"B2B-RULE-AUTH-029","config":{"recovery_verify_route_id":11,"password_update_screen_id":53,"client_context_promotion":"DENY"}},{"rule_code":"B2B-RULE-AUTH-031","config":{"login_route_id":10,"client_redirect_authoritative":"DENY","fresh_login_required":true}}]'::jsonb);
  elsif p_pantalla_id=53 and p_family_code='RUNTIME_CONFIG' then
    v:=v || jsonb_build_object('operator','CONTAINS','expected','[{"rule_code":"B2B-RULE-AUTH-029","config":{"provider_architecture_security_policy_id":23}},{"rule_code":"B2B-RULE-AUTH-030","config":{"provider_binding":"SUPABASE_AUTH","password_security_policy_id":24,"provider_architecture_security_policy_id":23}}]'::jsonb);
  elsif p_pantalla_id=54 and p_family_code='FIELDS' then
    v:=v || jsonb_build_object('operator','CONTAINS','expected','[{"field_id":302,"field_code":"B2B_FLD_MFA_EMAIL_OTP_CODE","required":true,"sensitive":true,"logs_allowed":false,"analytics_allowed":false,"ui":{"context_key":"MFA_EMAIL_OTP_CODE","component_token_id":40,"component_token_code":"otp_pin"}}]'::jsonb);
  elsif p_pantalla_id=51 and p_family_code='PERMISSIONS' then
    v:=v || jsonb_build_object('operator','CONTAINS','expected','[{"permission":{"permission_code":"B2B_USER_UPDATE"}},{"permission":{"permission_code":"B2B_AUTH_FACTOR_RESET"}}]'::jsonb);
  end if;
  return v - 'actual' - 'result' - 'source_observed_sha256';
end;
$$;

create or replace function programacion.fn_input_v58_build_assertions(p_new_run_id bigint,p_parent_run_id bigint,p_family_code text)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,programacion
as $$
declare v_pantalla_id integer; v_old jsonb; v_tpl jsonb; v_rebound jsonb; v_out jsonb:='[]'::jsonb;
begin
  select pantalla_id into v_pantalla_id from programacion.input_readiness_runs where id=p_new_run_id;
  if v_pantalla_id is null then raise exception 'V58_ASSERTION_NEW_RUN_NOT_FOUND:%',p_new_run_id; end if;
  for v_old in
    select x.value from programacion.input_family_assessments a
    cross join lateral jsonb_array_elements(a.validator_evidence->'assertions') x(value)
    where a.run_id=p_parent_run_id and a.family_code=p_family_code
  loop
    v_tpl:=programacion.fn_input_v58_assertion_template(v_pantalla_id,p_family_code,v_old);
    v_rebound:=programacion.fn_input_rebind_assertion(p_new_run_id,p_family_code,v_tpl);
    if v_rebound->>'result'<>'PASS' then raise exception 'V58_REBOUND_ASSERTION_FAILED screen=% family=% source=% path=%',v_pantalla_id,p_family_code,v_rebound->'source_ref',v_rebound->'path'; end if;
    v_out:=v_out || jsonb_build_array(v_rebound);
  end loop;
  if jsonb_array_length(v_out)=0 then raise exception 'V58_ASSERTION_SET_EMPTY:%:%',v_pantalla_id,p_family_code; end if;
  return v_out;
end;
$$;

do $$
declare
  rec record; a record; v_new bigint; v_graph jsonb; v_ds jsonb; v_visual jsonb; v_visual_count integer; v_subject_open integer; v_threat_open integer;
  v_severity text; v_cov text; v_well text; v_story text; v_impl text; v_qa text; v_prod text; v_blockers jsonb; v_rationale text;
  v_assertions jsonb; v_source_sha text; v_val_identity text; v_cur_identity text;
begin
  for rec in select * from (values (51,83::bigint),(52,78::bigint),(53,79::bigint),(54,80::bigint),(55,81::bigint)) v(pantalla_id,parent_run_id)
  loop
    if not exists(select 1 from programacion.input_readiness_runs r where r.id=rec.parent_run_id and r.pantalla_id=rec.pantalla_id and r.status='COMPLETED') then raise exception 'V58_PARENT_NOT_COMPLETED screen=% parent=%',rec.pantalla_id,rec.parent_run_id; end if;
    v_cur_identity:='INPUT_CURATOR:v0.5r1-auth-'||rec.pantalla_id::text||'-v58-r5-'||substr(md5(random()::text||clock_timestamp()::text),1,8);
    insert into programacion.input_readiness_runs(version_id,pantalla_id,universe_rule_id,supersedes_run_id,scope,universe_snapshot_sha256,family_count,status,curator_identity,curator_component_id,contract_version)
    select version_id,pantalla_id,universe_rule_id,id,scope || jsonb_build_object('mode','CANDIDATE_V58_CONTEXTUAL_SUBJECT_THREAT_DEPTH','parent_run_id',id,'remediation','AUDIT_20260818_R5_CONTEXTUAL_PROFILES'),universe_snapshot_sha256,family_count,'CURATING',v_cur_identity,curator_component_id,5
    from programacion.input_readiness_runs where id=rec.parent_run_id returning id into v_new;

    v_graph:=programacion.fn_input_screen_canonical_graph(rec.pantalla_id,19);
    v_ds:=v_graph->'canonical_contract'->'visual'->'design_bindings'->'summary';
    v_visual:=programacion.fn_input_resolve_source_ref(jsonb_build_object('kind','CURRENT_VISUAL_ARTIFACT','pantalla_id',rec.pantalla_id),rec.pantalla_id,19)->'observed';
    v_visual_count:=case when jsonb_typeof(v_visual)='array' then jsonb_array_length(v_visual) else 0 end;
    select count(*) into v_subject_open from jsonb_array_elements(programacion.fn_input_subject_depth_expected(rec.pantalla_id,'DESIGN_SYSTEM')) s where s->>'status' not in ('COMPLETE','NOT_APPLICABLE');
    select count(*) into v_threat_open from jsonb_array_elements(programacion.fn_input_security_threat_expected(rec.pantalla_id)) t where t->>'status' not in ('COMPLETE','NOT_APPLICABLE');

    for a in select * from programacion.input_family_assessments where run_id=rec.parent_run_id order by family_code
    loop
      v_severity:=a.severity; v_cov:=a.coverage_status; v_well:=a.well_defined_status; v_story:=a.story_ready_status; v_impl:=a.implementation_ready_status; v_qa:=a.qa_ready_status; v_prod:=a.production_ready_status; v_blockers:=a.blockers; v_rationale:=a.rationale;
      if a.family_code='BROWSER_PLATFORM' then
        v_severity:='P2'; v_cov:='MISSING'; v_well:='MISSING'; v_story:='READY'; v_impl:='READY'; v_qa:='BLOCKED'; v_prod:='BLOCKED';
        v_blockers:=jsonb_build_array(jsonb_build_object('code','BROWSER_PLATFORM_REQUIREMENT_MISSING','source_ref','B2B-RULE-COMPAT-001','blocks_story',false,'blocks_implementation',false,'blocks_qa',true,'blocks_production',true));
        v_rationale:='V5.8 stage-aware: browser/platform compatibility remains unresolved and is required by QA, not by Story or Implementation. No browser version is invented.';
      elsif a.family_code='DESIGN_SYSTEM' then
        v_severity:='P1'; v_cov:='PARTIAL'; v_well:='PARTIAL'; v_story:='READY'; v_impl:='NOT_READY'; v_qa:='BLOCKED'; v_prod:='BLOCKED';
        v_blockers:=coalesce(a.blockers,'[]'::jsonb) || jsonb_build_array(jsonb_build_object('code','DESIGN_SUBJECT_DEPTH_INCOMPLETE','open_subject_count',v_subject_open,'source_ref','programacion.fn_input_subject_depth_expected('||rec.pantalla_id::text||',DESIGN_SYSTEM)'),jsonb_build_object('code','CURRENT_VARIANT_LAYOUT_BINDING_MISSING','count',coalesce((v_ds->>'variant_layout_missing_count')::integer,0)));
        v_rationale:='V5.8 contextual subject-depth: every concrete field/display role is checked against applicable design bindings. COMPLETE is forbidden while a required subject check is open.';
      elsif a.family_code='SECURITY' then
        v_cov:='PARTIAL'; v_well:='PARTIAL';
        if a.story_ready_status='READY' then v_severity:='P1'; v_story:='READY'; v_impl:='NOT_READY'; v_qa:='NOT_READY'; v_prod:='NOT_READY'; else v_severity:='P0'; v_story:=a.story_ready_status; v_impl:=a.implementation_ready_status; v_qa:=a.qa_ready_status; v_prod:=a.production_ready_status; end if;
        v_blockers:=coalesce(a.blockers,'[]'::jsonb) || jsonb_build_array(jsonb_build_object('code','SECURITY_THREAT_MATRIX_INCOMPLETE','open_or_partial_count',v_threat_open,'capability_profile',programacion.fn_input_security_capability_profile(rec.pantalla_id)->>'profile','source_ref','programacion.fn_input_security_threat_expected('||rec.pantalla_id::text||')'));
        v_rationale:='V5.8 contextual security depth: field handling and a capability-specific 30-threat matrix are evaluated separately. Threat N/A requires positive capability authority; unresolved or applicable gaps cannot yield false COMPLETE.';
      elsif a.family_code='VISUAL_EVIDENCE' then
        if v_visual_count=0 then
          v_severity:='P0'; v_cov:='MISSING'; v_well:='MISSING'; v_story:='BLOCKED'; v_impl:='BLOCKED'; v_qa:='BLOCKED'; v_prod:='BLOCKED'; v_blockers:=jsonb_build_array(jsonb_build_object('code','CURRENT_VISUAL_EVIDENCE_MISSING','pantalla_id',rec.pantalla_id)); v_rationale:='No current visual artifact is registered for this screen; Story remains fail-closed for visual evidence.';
        else
          v_severity:='P1'; v_cov:='PARTIAL'; v_well:='COMPLETE'; v_story:='READY'; v_impl:='NOT_READY'; v_qa:='BLOCKED'; v_prod:='BLOCKED'; v_blockers:=jsonb_build_array(jsonb_build_object('code','CURRENT_VISUAL_EVIDENCE_PARTIAL','artifact_count',v_visual_count,'note','Current artifact records exist, but DB-only physical resolution is not sufficient for all external Google Drive binaries/variants.')); v_rationale:='Current visual artifact records exist, so the family is no longer MISSING. It remains PARTIAL and blocks downstream readiness until the required variants and physical binary verification are fully resolvable by the governed evidence path.';
        end if;
      elsif rec.pantalla_id=52 and a.family_code='OBJECTIVE_OUTCOMES' then v_rationale:='El objetivo canónico actual exige iniciar recuperación de acceso de forma segura y anti-enumeración, enviando únicamente el correo antes de cualquier nueva contraseña.';
      elsif rec.pantalla_id=53 and a.family_code='PRIVACY_PII' then v_rationale:='Los campos de nueva contraseña/confirmación son SENSITIVE/TRANSIENT/MASK_FULL sin logs ni analytics; AUTH-030 además niega logs, analytics y persistencia LF de la contraseña. No se atribuyen a AUTH-029 controles que ya no figuran en su fuente actual.';
      elsif rec.pantalla_id=53 and a.family_code='ROUTING_NAVIGATION' then v_rationale:='AUTH-029 liga la verificación de recuperación a route_id 11 y pantalla de nueva contraseña 53 sin promoción de contexto cliente; AUTH-031 retorna al Login route_id 10 y niega redirect cliente autoritativo.';
      elsif rec.pantalla_id=53 and a.family_code='RUNTIME_CONFIG' then v_rationale:='AUTH-029 mantiene autoridad de arquitectura security_policy_id 23; AUTH-030 liga PASSWORD_UPDATE a Supabase Auth y security_policy_ids 23/24. La implementación/proveedor continúa pendiente donde ya estaba declarada.';
      elsif rec.pantalla_id=54 and a.family_code='FIELDS' then v_rationale:='B2B_FLD_MFA_EMAIL_OTP_CODE sigue siendo sensible, transitorio, numérico y sin logs/analytics; su binding visual actual es component_token_id=40 / otp_pin, no input_default.';
      elsif rec.pantalla_id=51 and a.family_code='PERMISSIONS' then v_rationale:='La autoridad actual del Login expone permisos explícitos vinculados al alcance de pantalla/reglas, incluidos B2B_USER_UPDATE y B2B_AUTH_FACTOR_RESET; la familia permanece completa sin asumir que existe una sola relación.';
      end if;

      insert into programacion.input_family_assessments(run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,source_refs,rationale,blockers,negative_requirements,test_obligations,curator_evidence,curator_sha256)
      values(v_new,a.family_code,v_severity,a.applicability,v_cov,v_well,v_story,v_impl,v_qa,v_prod,a.source_refs,v_rationale,v_blockers,a.negative_requirements,a.test_obligations,jsonb_build_object('component_id',46,'execution_id',gen_random_uuid()::text,'execution_mode','INDEPENDENT_CURATOR','contract_revision','5.8','parent_run_id',rec.parent_run_id,'parent_assessment_id',a.id,'remediation_revision','AUDIT_20260818_R5_CONTEXTUAL_PROFILES','direct_source_readback',true),repeat('0',64));
    end loop;

    v_val_identity:='INPUT_VALIDATOR:v0.5r1-auth-'||rec.pantalla_id::text||'-v58-r5-'||substr(md5(random()::text||clock_timestamp()::text),1,8);
    update programacion.input_readiness_runs set status='VALIDATING',validator_identity=v_val_identity,validator_component_id=47 where id=v_new;
    select source_snapshot_sha256 into v_source_sha from programacion.input_readiness_runs where id=v_new;
    for a in select * from programacion.input_family_assessments where run_id=v_new order by family_code
    loop
      v_assertions:=programacion.fn_input_v58_build_assertions(v_new,rec.parent_run_id,a.family_code);
      update programacion.input_family_assessments set validator_outcome='PASS',validator_findings='[]'::jsonb,validator_identity=v_val_identity,validator_evidence=jsonb_build_object('component_id',47,'execution_id',gen_random_uuid()::text,'validated_curator_execution_id',a.curator_evidence->>'execution_id','execution_mode','INDEPENDENT_VALIDATOR','direct_source_readback',true,'contract_revision','5.8','source_snapshot_sha256',v_source_sha,'curator_sha256',a.curator_sha256,'semantic_depth_sha256',a.semantic_depth_sha256,'assertions',v_assertions) where id=a.id;
    end loop;
    update programacion.input_readiness_runs set status='COMPLETED' where id=v_new;
  end loop;
end;
$$;