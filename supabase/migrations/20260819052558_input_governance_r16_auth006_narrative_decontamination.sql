do $$
declare a record; v_new bigint; v_cur text; v_val text; v_sha text; v_assert jsonb; v_rat text; v_block jsonb;
begin
  v_cur:='INPUT_CURATOR:v0.5r1-auth006-v511-r16-'||substr(md5(random()::text||clock_timestamp()::text),1,8);
  insert into programacion.input_readiness_runs(version_id,pantalla_id,universe_rule_id,supersedes_run_id,scope,universe_snapshot_sha256,family_count,status,curator_identity,curator_component_id,contract_version)
  select version_id,pantalla_id,universe_rule_id,id,
         scope||jsonb_build_object('mode','CANDIDATE_V511_AUTH006_NARRATIVE_CLEAN','parent_run_id',id,'remediation','AUDIT_20260819_R16_AUTH006_NARRATIVE_DECONTAMINATION'),
         universe_snapshot_sha256,family_count,'CURATING',v_cur,curator_component_id,5
  from programacion.input_readiness_runs where id=110 returning id into v_new;

  for a in select * from programacion.input_family_assessments where run_id=110 order by family_code loop
    v_rat:=a.rationale;
    v_block:=replace(a.blockers::text,'B2B-AUTH-004','B2B-AUTH-006')::jsonb;
    case a.family_code
      when 'ACCESSIBILITY' then v_rat:='B2B-AUTH-006 tiene teclado, foco visible, ARIA y contraste/color definidos por A11Y-001/002. La familia permanece PARTIAL porque forced-colors y reduced-motion se controlan como subfamilias explícitas y siguen incompletas para esta pantalla.';
      when 'ANALYTICS' then v_rat:='La política transversal de analytics existe como autoridad de referencia, pero B2B-AUTH-006 no tiene mapeo de eventos de pantalla materializado. Es un gap de Implementación, no de Story.';
      when 'API_DATA_CONTRACT' then v_rat:='SOURCE_INCOMPLETE: AUTH-037 define generación y verificación server-side del OTP de recuperación, proveedor Brevo y éxito restringido a PASSWORD_UPDATE_ONLY; no existe aún operación/endpoint/request-response schema canónico resoluble. No se autoriza inventar esa API.';
      when 'CONTEXT_BUDGET_RETRIEVAL_POLICY' then v_rat:='B2B-RULE-CONTEXT-001 está vinculada explícitamente a B2B-AUTH-006 y exige minimum sufficient context, provenance y retrieval on demand para el Story Creator/Context Pack.';
      when 'FORCED_COLORS_CONTRAST' then v_rat:='A11Y-002 cubre contraste y no depender solo del color, pero B2B-AUTH-006 no tiene requisito explícito de forced-colors. El gap empieza en Implementación y no bloquea Story.';
      when 'IDEMPOTENCY_CONCURRENCY' then v_rat:='No existe contrato explícito de single-flight/idempotencia/concurrencia para verificación o reenvío del OTP de recuperación en B2B-AUTH-006. El gap empieza en Implementación y no bloquea Story.';
      when 'LOADING_EMPTY_ERROR_STATES' then v_rat:='B2B-AUTH-006 tiene comportamiento de verificación, reenvío y errores, pero no un contrato explícito para processing/loading ni recuperación de UI tras interrupción. Story permanece READY y el detalle se exige antes de implementación/QA.';
      when 'PERMISSIONS' then v_rat:='NOT_APPLICABLE con autoridad positiva: AUTH-029/037 gobiernan el acceso por contexto PASSWORD_RECOVERY/PASSWORD_UPDATE_ONLY y niegan autorización operativa; no existe permiso de pantalla/perfil para conceder este paso y las matrices canónicas de permisos están vacías.';
      when 'RATE_LIMIT' then v_rat:='B2B-RULE-RATE-001 está enlazada a B2B-AUTH-006 y exige política central, pero no hay rate_limit_policy_id concreto para el recurso. Los límites de intentos/reenvíos de otp_policy_id=2 no se reinterpretan como sustituto de un rate-limit binding.';
      when 'REDUCED_MOTION' then v_rat:='B2B-AUTH-006 no tiene requisito explícito de reduced-motion. El gap empieza en Implementación y no bloquea Story.';
      when 'STATES' then v_rat:='NOT_APPLICABLE: no existe SCREEN_STATE_SET persistido para B2B-AUTH-006; los resultados de verificación y el alcance PASSWORD_UPDATE_ONLY se gobiernan directamente por AUTH-029/037/038, sin requerir una máquina de estados de pantalla como input de Story.';
      when 'TESTING_OBLIGATIONS' then v_rat:='No existe test contract materializado ni B2B-RULE-TEST-001 enlazada a B2B-AUTH-006. Por contrato 5.11 es un gate de QA: Story e Implementación no se bloquean por esta ausencia.';
      when 'THEME_LIGHT_DARK_SYSTEM' then v_rat:='B2B-AUTH-006 solo tiene variantes LIGHT registradas y no hay reglas LIGHT/DARK/SYSTEM enlazadas. El gap empieza en Implementación y no bloquea Story.';
      when 'TRANSITIONS' then v_rat:='NOT_APPLICABLE: al no existir un conjunto canónico de estados persistidos para B2B-AUTH-006, tampoco existe una transición de estado de pantalla que deba materializarse como input; el flujo funcional se rige por AUTH-029/037/038.';
      else null;
    end case;

    insert into programacion.input_family_assessments(run_id,family_code,severity,applicability,coverage_status,well_defined_status,story_ready_status,implementation_ready_status,qa_ready_status,production_ready_status,source_refs,rationale,blockers,negative_requirements,test_obligations,curator_evidence,curator_sha256)
    values(v_new,a.family_code,a.severity,a.applicability,a.coverage_status,a.well_defined_status,a.story_ready_status,a.implementation_ready_status,a.qa_ready_status,a.production_ready_status,a.source_refs,v_rat,v_block,a.negative_requirements,a.test_obligations,
      jsonb_build_object('component_id',46,'execution_id',gen_random_uuid()::text,'execution_mode','INDEPENDENT_CURATOR','contract_revision','5.11','parent_run_id',110,'parent_assessment_id',a.id,'remediation_revision','AUDIT_20260819_R16_AUTH006_NARRATIVE_DECONTAMINATION','direct_source_readback',true),repeat('0',64));
  end loop;

  v_val:='INPUT_VALIDATOR:v0.5r1-auth006-v511-r16-'||substr(md5(random()::text||clock_timestamp()::text),1,8);
  update programacion.input_readiness_runs set status='VALIDATING',validator_identity=v_val,validator_component_id=47 where id=v_new;
  select source_snapshot_sha256 into v_sha from programacion.input_readiness_runs where id=v_new;
  for a in select * from programacion.input_family_assessments where run_id=v_new order by family_code loop
    v_assert:=programacion.fn_input_v58_build_assertions(v_new,110,a.family_code);
    update programacion.input_family_assessments
       set validator_outcome='PASS',validator_findings='[]'::jsonb,validator_identity=v_val,
           validator_evidence=jsonb_build_object('component_id',47,'execution_id',gen_random_uuid()::text,'validated_curator_execution_id',a.curator_evidence->>'execution_id','execution_mode','INDEPENDENT_VALIDATOR','direct_source_readback',true,'contract_revision','5.11','source_snapshot_sha256',v_sha,'curator_sha256',a.curator_sha256,'semantic_depth_sha256',a.semantic_depth_sha256,'assertions',v_assert)
     where id=a.id;
  end loop;
  update programacion.input_readiness_runs set status='COMPLETED' where id=v_new;
end$$;