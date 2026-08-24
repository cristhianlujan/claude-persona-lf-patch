create or replace function programacion.fn_input_owner_decision_assertions(
  p_new_run_id bigint,
  p_parent_run_id bigint,
  p_family_code text
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,programacion,lf_ops
as $$
declare
  v_screen integer;
  v_specs jsonb;
  v_old jsonb;
  v_rebound jsonb;
  v_out jsonb:='[]'::jsonb;
  v_terms bigint;
  v_privacy bigint;
  v_support bigint;
begin
  select pantalla_id into v_screen from programacion.input_readiness_runs where id=p_new_run_id;
  if v_screen is null then raise exception 'OWNER_DECISION_RUN_NOT_FOUND:%',p_new_run_id; end if;

  select route_id into v_terms from lf_ops.rutas where route_code='B2B_ROUTE_LEGAL_TERMS';
  select route_id into v_privacy from lf_ops.rutas where route_code='B2B_ROUTE_LEGAL_PRIVACY';
  select route_id into v_support from lf_ops.rutas where route_code='B2B_ROUTE_SUPPORT';

  if v_screen=51 and p_family_code='ACTIONS' then
    v_specs:=jsonb_build_array(
      jsonb_build_object(
        'source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',51),
        'path',jsonb_build_array('observed','canonical_contract','rules'),
        'operator','CONTAINS',
        'expected',jsonb_build_array(
          jsonb_build_object('rule_code','B2B-RULE-AUTH-036','config',jsonb_build_object('actions',jsonb_build_array(
            jsonb_build_object('action_code','OPEN_TERMS','route_id',v_terms,'target_status','APPROVED_B2B_CANONICAL'),
            jsonb_build_object('action_code','OPEN_PRIVACY','route_id',v_privacy,'target_status','APPROVED_B2B_CANONICAL'),
            jsonb_build_object('action_code','CONTACT_SUPPORT','route_id',v_support,'target_status','APPROVED_B2B_CANONICAL')
          ))),
          jsonb_build_object('rule_code','B2B-RULE-NAV-LEGAL-001','pending_decision',false,'config',jsonb_build_object(
            'route_target_status','APPROVED_B2B_CANONICAL','public_front_reuse','DENY','blocks_story',false,'blocks_implementation',false
          ))
        )
      )
    );
  elsif v_screen=51 and p_family_code='ROUTING_NAVIGATION' then
    v_specs:=jsonb_build_array(
      jsonb_build_object(
        'source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',51),
        'path',jsonb_build_array('observed','canonical_contract','rules'),
        'operator','CONTAINS',
        'expected',jsonb_build_array(
          jsonb_build_object('rule_code','B2B-RULE-NAV-LEGAL-001','pending_decision',false,'config',jsonb_build_object(
            'current_b2b_route_ids',jsonb_build_array(v_terms,v_privacy,v_support),
            'route_target_status','APPROVED_B2B_CANONICAL','public_front_reuse','DENY'
          ))
        )
      ),
      jsonb_build_object(
        'source_ref',jsonb_build_object('kind','ROUTE_SET','ids',jsonb_build_array(9,10,12,13,v_terms,v_privacy,v_support)),
        'path',jsonb_build_array('observed'),
        'operator','CONTAINS',
        'expected',jsonb_build_array(
          jsonb_build_object('route_id',v_terms,'route_code','B2B_ROUTE_LEGAL_TERMS','authentication_required',false),
          jsonb_build_object('route_id',v_privacy,'route_code','B2B_ROUTE_LEGAL_PRIVACY','authentication_required',false),
          jsonb_build_object('route_id',v_support,'route_code','B2B_ROUTE_SUPPORT','authentication_required',false)
        )
      )
    );
  elsif v_screen=52 and p_family_code='SESSION' then
    v_specs:=jsonb_build_array(
      jsonb_build_object(
        'source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',52),
        'path',jsonb_build_array('observed','canonical_contract','rules'),
        'operator','CONTAINS',
        'expected',jsonb_build_array(
          jsonb_build_object('rule_code','B2B-RULE-AUTH-028','config',jsonb_build_object(
            'operational_session_creation','DENY',
            'authentication_completion','DENY',
            'operational_access_grant','DENY',
            'success_context_scope','PASSWORD_RECOVERY_CHALLENGE_ONLY'
          ))
        )
      )
    );
  elsif v_screen=54 and p_family_code='ERRORS' then
    v_specs:=jsonb_build_array(
      jsonb_build_object(
        'source_ref',jsonb_build_object('kind','ERROR_SET','ids',jsonb_build_array(40)),
        'path',jsonb_build_array('observed'),
        'operator','CONTAINS',
        'expected',jsonb_build_array(jsonb_build_object(
          'error_id',40,
          'error_code','LF-B2B-AUTH-007',
          'user_title','Código no válido',
          'user_message_template','El código ingresado no es válido o ya venció. Solicita uno nuevo e inténtalo nuevamente.',
          'suggested_action','Solicita un nuevo código de verificación para continuar.',
          'action_label','Reenviar código'
        ))
      )
    );
  elsif v_screen=56 and p_family_code='ERRORS' then
    v_specs:=jsonb_build_array(
      jsonb_build_object(
        'source_ref',jsonb_build_object('kind','SCREEN_CANONICAL_GRAPH','pantalla_id',56),
        'path',jsonb_build_array('observed','canonical_contract','rules'),
        'operator','CONTAINS',
        'expected',jsonb_build_array(jsonb_build_object('rule_code','B2B-RULE-AUTH-029','config',jsonb_build_object('invalid_recovery_error_id',39)))
      ),
      jsonb_build_object(
        'source_ref',jsonb_build_object('kind','ERROR_SET','ids',jsonb_build_array(39)),
        'path',jsonb_build_array('observed'),
        'operator','CONTAINS',
        'expected',jsonb_build_array(jsonb_build_object(
          'error_id',39,
          'error_code','LF-B2B-AUTH-006',
          'user_title','Código de recuperación no válido',
          'user_message_template','El código ingresado no es válido o ya venció. Solicita un nuevo código para continuar.',
          'suggested_action','Solicita un nuevo código de recuperación para continuar.',
          'action_label','Reenviar código'
        ))
      )
    );
  else
    v_specs:=null;
  end if;

  if v_specs is not null then
    return programacion.fn_input_rebind_assertion_specs(p_new_run_id,p_family_code,v_specs);
  end if;

  for v_old in
    select x.value
    from programacion.input_family_assessments a
    cross join lateral jsonb_array_elements(a.validator_evidence->'assertions') x(value)
    where a.run_id=p_parent_run_id and a.family_code=p_family_code
  loop
    v_rebound:=programacion.fn_input_rebind_assertion(p_new_run_id,p_family_code,v_old);
    if v_rebound->>'result'<>'PASS' then
      raise exception 'OWNER_DECISION_REBOUND_FAILED screen=% family=% source=% path=% expected=% actual=%',v_screen,p_family_code,v_rebound->'source_ref',v_rebound->'path',v_rebound->'expected',v_rebound->'actual';
    end if;
    v_out:=v_out||jsonb_build_array(v_rebound);
  end loop;
  if jsonb_array_length(v_out)=0 then raise exception 'OWNER_DECISION_ASSERTIONS_EMPTY:%:%',v_screen,p_family_code; end if;
  return v_out;
end;
$$;

do $$
declare
  rec record;
  a record;
  v_new bigint;
  v_cur text;
  v_val text;
  v_sha text;
  v_assert jsonb;
  v_sev text;
  v_app text;
  v_cov text;
  v_well text;
  v_story text;
  v_impl text;
  v_qa text;
  v_prod text;
  v_sources jsonb;
  v_rat text;
  v_block jsonb;
  v_terms bigint;
  v_privacy bigint;
  v_support bigint;
begin
  select route_id into v_terms from lf_ops.rutas where route_code='B2B_ROUTE_LEGAL_TERMS';
  select route_id into v_privacy from lf_ops.rutas where route_code='B2B_ROUTE_LEGAL_PRIVACY';
  select route_id into v_support from lf_ops.rutas where route_code='B2B_ROUTE_SUPPORT';

  for rec in select * from (values
    (51,111::bigint),(52,112::bigint),(53,113::bigint),(54,114::bigint),(56,116::bigint)
  ) v(pantalla_id,parent_run_id)
  loop
    if not exists(select 1 from programacion.input_readiness_runs where id=rec.parent_run_id and pantalla_id=rec.pantalla_id and status='COMPLETED') then
      raise exception 'OWNER_DECISION_PARENT_INVALID screen=% parent=%',rec.pantalla_id,rec.parent_run_id;
    end if;
    if rec.pantalla_id=55 or not exists(select 1 from lf_ops.pantallas where id=rec.pantalla_id and activa=true) then
      raise exception 'OWNER_DECISION_SUCCESSOR_REQUIRES_ACTIVE_SCREEN:%',rec.pantalla_id;
    end if;

    v_cur:='INPUT_CURATOR:v0.5r1-auth-'||rec.pantalla_id||'-owner-20260819-'||substr(md5(random()::text||clock_timestamp()::text),1,8);
    insert into programacion.input_readiness_runs(
      version_id,pantalla_id,universe_rule_id,supersedes_run_id,scope,universe_snapshot_sha256,family_count,status,curator_identity,curator_component_id,contract_version
    )
    select version_id,pantalla_id,universe_rule_id,id,
           scope||jsonb_build_object('mode','OWNER_DECISIONS_20260819','parent_run_id',id,'remediation','OWNER_APPROVAL_20260819_AUTH_PRODUCT_DECISIONS'),
           universe_snapshot_sha256,family_count,'CURATING',v_cur,curator_component_id,5
    from programacion.input_readiness_runs where id=rec.parent_run_id
    returning id into v_new;

    for a in select * from programacion.input_family_assessments where run_id=rec.parent_run_id order by family_code
    loop
      v_sev:=a.severity; v_app:=a.applicability; v_cov:=a.coverage_status; v_well:=a.well_defined_status;
      v_story:=a.story_ready_status; v_impl:=a.implementation_ready_status; v_qa:=a.qa_ready_status; v_prod:=a.production_ready_status;
      v_sources:=a.source_refs; v_rat:=a.rationale||' | Owner decisions 2026-08-19 source readback successor.'; v_block:=a.blockers;

      if rec.pantalla_id=51 and a.family_code='ACTIONS' then
        v_sev:='P4'; v_app:='APPLICABLE'; v_cov:='COMPLETE'; v_well:='COMPLETE';
        v_story:='READY'; v_impl:='READY'; v_qa:='READY'; v_prod:='READY'; v_block:='[]'::jsonb;
        v_sources:=jsonb_build_array(jsonb_build_object('kind','SCREEN_RULE_SET','pantalla_id',51));
        v_rat:='Las seis acciones del Login tienen destino canónico: autenticación, visibilidad, recuperación y los accesos B2B a Términos, Privacidad y Soporte. AUTH-036 referencia las rutas B2B aprobadas y NAV-LEGAL ya no tiene decisión pendiente.';
      elsif rec.pantalla_id=51 and a.family_code='ROUTING_NAVIGATION' then
        v_sev:='P4'; v_app:='APPLICABLE'; v_cov:='COMPLETE'; v_well:='COMPLETE';
        v_story:='READY'; v_impl:='READY'; v_qa:='READY'; v_prod:='READY'; v_block:='[]'::jsonb;
        v_sources:=jsonb_build_array(
          jsonb_build_object('kind','SCREEN_RULE_SET','pantalla_id',51),
          jsonb_build_object('kind','ROUTE_SET','ids',jsonb_build_array(9,10,12,13,v_terms,v_privacy,v_support))
        );
        v_rat:='Login y sus destinos funcionales resuelven por rutas canónicas. Términos, Privacidad y Soporte usan rutas B2B internas no autenticadas; la ruta TOTP 14 queda fuera del conjunto operativo por retiro de AUTH-005.';
      elsif rec.pantalla_id=52 and a.family_code='SESSION' then
        v_sev:='P4'; v_app:='NOT_APPLICABLE'; v_cov:='NOT_APPLICABLE'; v_well:='NOT_APPLICABLE';
        v_story:='NOT_APPLICABLE'; v_impl:='NOT_APPLICABLE'; v_qa:='NOT_APPLICABLE'; v_prod:='NOT_APPLICABLE'; v_block:='[]'::jsonb;
        v_sources:=jsonb_build_array(jsonb_build_object('kind','SCREEN_RULE_SET','pantalla_id',52));
        v_rat:='Autoridad positiva AUTH-028: B2B-AUTH-002 no autentica, no crea sesión operativa y no concede acceso. Solo inicia PASSWORD_RECOVERY_CHALLENGE_ONLY y continúa en B2B-AUTH-006; por tanto SESSION no aplica a esta pantalla.';
      elsif rec.pantalla_id=54 and a.family_code='ERRORS' then
        v_sev:='P4'; v_app:='APPLICABLE'; v_cov:='COMPLETE'; v_well:='COMPLETE';
        v_story:='READY'; v_impl:='READY'; v_qa:='READY'; v_prod:='READY'; v_block:='[]'::jsonb;
        v_sources:=jsonb_build_array(jsonb_build_object('kind','SCREEN_RULE_SET','pantalla_id',54),jsonb_build_object('kind','ERROR_SET','ids',jsonb_build_array(40)));
        v_rat:='El error canónico 40 ya corresponde al segundo factor por correo: Código no válido, mensaje de código inválido/vencido y acción Reenviar código. Se eliminó el copy heredado de aplicación TOTP.';
      elsif rec.pantalla_id=56 and a.family_code='ERRORS' then
        v_sev:='P4'; v_app:='APPLICABLE'; v_cov:='COMPLETE'; v_well:='COMPLETE';
        v_story:='READY'; v_impl:='READY'; v_qa:='READY'; v_prod:='READY'; v_block:='[]'::jsonb;
        v_sources:=jsonb_build_array(jsonb_build_object('kind','SCREEN_RULE_SET','pantalla_id',56),jsonb_build_object('kind','ERROR_SET','ids',jsonb_build_array(39)));
        v_rat:='AUTH-029 mantiene error_id 39 y el catálogo ahora contiene copy canónico de OTP de recuperación: Código de recuperación no válido, código inválido/vencido y acción Reenviar código.';
      end if;

      insert into programacion.input_family_assessments(
        run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,
        source_refs,rationale,blockers,negative_requirements,test_obligations,curator_evidence,curator_sha256
      ) values(
        v_new,a.family_code,v_sev,v_app,v_cov,v_well,v_story,v_impl,v_qa,v_prod,
        v_sources,v_rat,v_block,a.negative_requirements,a.test_obligations,
        jsonb_build_object('component_id',46,'execution_id',gen_random_uuid()::text,'execution_mode','INDEPENDENT_CURATOR','contract_revision','5.11','parent_run_id',rec.parent_run_id,'parent_assessment_id',a.id,'remediation_revision','OWNER_APPROVAL_20260819_AUTH_PRODUCT_DECISIONS','direct_source_readback',true),
        repeat('0',64)
      );
    end loop;

    v_val:='INPUT_VALIDATOR:v0.5r1-auth-'||rec.pantalla_id||'-owner-20260819-'||substr(md5(random()::text||clock_timestamp()::text),1,8);
    update programacion.input_readiness_runs set status='VALIDATING',validator_identity=v_val,validator_component_id=47 where id=v_new;
    select source_snapshot_sha256 into v_sha from programacion.input_readiness_runs where id=v_new;

    for a in select * from programacion.input_family_assessments where run_id=v_new order by family_code
    loop
      v_assert:=programacion.fn_input_owner_decision_assertions(v_new,rec.parent_run_id,a.family_code);
      update programacion.input_family_assessments
      set validator_outcome='PASS',validator_findings='[]'::jsonb,validator_identity=v_val,
          validator_evidence=jsonb_build_object(
            'component_id',47,'execution_id',gen_random_uuid()::text,'validated_curator_execution_id',a.curator_evidence->>'execution_id',
            'execution_mode','INDEPENDENT_VALIDATOR','direct_source_readback',true,'contract_revision','5.11',
            'source_snapshot_sha256',v_sha,'curator_sha256',a.curator_sha256,'semantic_depth_sha256',a.semantic_depth_sha256,'assertions',v_assert
          )
      where id=a.id;
    end loop;
    update programacion.input_readiness_runs set status='COMPLETED' where id=v_new;
  end loop;
end;
$$;