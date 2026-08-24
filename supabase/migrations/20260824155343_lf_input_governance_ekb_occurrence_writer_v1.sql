-- Governed EKB occurrence writer for INPUT_GOVERNANCE_AGENT execution checkpoints.
update programacion.contratos
set especificacion = especificacion || jsonb_build_object(
  'ekb_occurrence_writer','programacion.fn_input_governance_record_ekb_occurrence(text,text,text,integer,bigint,text,jsonb)',
  'ekb_write_policy',jsonb_build_object(
    'RECURRENCE','UPDATE_EXISTING_FREQUENCY_LAST_SEEN_EVIDENCE',
    'NEW_ERROR','INSERT_ONLY_WITH_COMPLETE_VERIFIED_METADATA',
    'SUSPICION','NO_WRITE_PROPOSAL_OR_BLOCKER',
    'NO_ERROR','NO_WRITE'
  )
)
where version_id=19 and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT' and estado='defined';

create or replace function programacion.fn_input_governance_record_ekb_occurrence(
  p_classification text,
  p_error_code text,
  p_phase text,
  p_pantalla_id integer,
  p_run_id bigint,
  p_evidence text,
  p_details jsonb default '{}'::jsonb
) returns jsonb
language plpgsql volatile security definer
set search_path to 'pg_catalog','public','programacion','lf_ops','transversal'
as $f$
declare
  v_class text:=upper(btrim(coalesce(p_classification,'')));
  v_before integer;
  v_after integer;
  v_receipt jsonb;
  v_roles text[];
  v_source_context text;
  v_source_ref text;
begin
  if not exists(select 1 from programacion.contratos where version_id=19 and contrato_codigo='INPUT_GOVERNANCE_EXECUTION_CONTRACT' and estado='defined' and fail_closed) then
    raise exception 'INPUT_GOVERNANCE_EXECUTION_CONTRACT_NOT_RESOLVABLE';
  end if;
  if not exists(select 1 from lf_ops.pantallas where id=p_pantalla_id) then
    raise exception 'INPUT_GOVERNANCE_SCREEN_NOT_FOUND:%',p_pantalla_id;
  end if;
  if p_phase not in ('PRE_EXECUTION','PRE_CURATOR','PRE_VALIDATOR','PRE_STORY_GATE','PRE_CONTEXT_MANIFEST','CLOSE_EKB') then
    raise exception 'INPUT_GOVERNANCE_EKB_PHASE_NOT_DEFINED:%',coalesce(p_phase,'<NULL>');
  end if;
  if p_run_id is not null and not exists(select 1 from programacion.input_readiness_runs where id=p_run_id and pantalla_id=p_pantalla_id) then
    raise exception 'INPUT_GOVERNANCE_EKB_RUN_SCREEN_MISMATCH:run=% screen=%',p_run_id,p_pantalla_id;
  end if;

  if v_class='NO_ERROR' then
    v_receipt:=jsonb_build_object('schema_version',1,'classification',v_class,'write_performed',false,'outcome','NO_WRITE','phase',p_phase,'pantalla_id',p_pantalla_id,'run_id',p_run_id,'observed_at',now());
    return v_receipt||jsonb_build_object('receipt_sha256',programacion.fn_v09_sha256_jsonb(v_receipt));
  end if;
  if v_class='SUSPICION' then
    v_receipt:=jsonb_build_object('schema_version',1,'classification',v_class,'write_performed',false,'outcome','PROPOSAL_OR_BLOCKER_REQUIRED','phase',p_phase,'pantalla_id',p_pantalla_id,'run_id',p_run_id,'error_code',nullif(btrim(coalesce(p_error_code,'')),''),'evidence',nullif(btrim(coalesce(p_evidence,'')),''),'observed_at',now());
    return v_receipt||jsonb_build_object('receipt_sha256',programacion.fn_v09_sha256_jsonb(v_receipt));
  end if;
  if v_class not in ('RECURRENCE','NEW_ERROR') then
    raise exception 'INPUT_GOVERNANCE_EKB_CLASSIFICATION_NOT_ALLOWED:%',coalesce(p_classification,'<NULL>');
  end if;
  if nullif(btrim(coalesce(p_error_code,'')),'') is null or p_error_code !~ '^[A-Z0-9][A-Z0-9_-]{2,63}$' then
    raise exception 'INPUT_GOVERNANCE_EKB_ERROR_CODE_INVALID';
  end if;
  if nullif(btrim(coalesce(p_evidence,'')),'') is null then
    raise exception 'INPUT_GOVERNANCE_EKB_VERIFIED_EVIDENCE_REQUIRED';
  end if;

  if v_class='RECURRENCE' then
    select frecuencia into v_before from transversal.error_knowledge where codigo=p_error_code and estado='activo' for update;
    if v_before is null then raise exception 'INPUT_GOVERNANCE_EKB_RECURRENCE_CODE_NOT_FOUND:%',p_error_code; end if;
    update transversal.error_knowledge
    set frecuencia=frecuencia+1,
        ultima_vez=now(),
        evidencia=concat_ws(E'\n',evidencia,format('[INPUT_GOVERNANCE %s screen=%s run=%s] %s',p_phase,p_pantalla_id,coalesce(p_run_id::text,'NONE'),p_evidence)),
        updated_at=now()
    where codigo=p_error_code and estado='activo'
    returning frecuencia into v_after;
    v_receipt:=jsonb_build_object('schema_version',1,'classification',v_class,'write_performed',true,'outcome','UPDATED_EXISTING','error_code',p_error_code,'frequency_before',v_before,'frequency_after',v_after,'phase',p_phase,'pantalla_id',p_pantalla_id,'run_id',p_run_id,'observed_at',now());
    return v_receipt||jsonb_build_object('receipt_sha256',programacion.fn_v09_sha256_jsonb(v_receipt));
  end if;

  if exists(select 1 from transversal.error_knowledge where codigo=p_error_code) then
    raise exception 'INPUT_GOVERNANCE_EKB_NEW_ERROR_CODE_ALREADY_EXISTS:%',p_error_code;
  end if;
  if not (p_details ?& array['categoria','titulo','descripcion','prevencion','validacion','severidad','lifecycle_phase','root_cause_family','detectability']) then
    raise exception 'INPUT_GOVERNANCE_EKB_NEW_ERROR_METADATA_INCOMPLETE';
  end if;
  if nullif(btrim(coalesce(p_details->>'titulo','')),'') is null
     or nullif(btrim(coalesce(p_details->>'prevencion','')),'') is null
     or nullif(btrim(coalesce(p_details->>'validacion','')),'') is null
     or nullif(btrim(coalesce(p_details->>'root_cause_family','')),'') is null then
    raise exception 'INPUT_GOVERNANCE_EKB_NEW_ERROR_METADATA_EMPTY';
  end if;
  if p_details->>'root_cause_family' not in ('R1_NO_SABE','R2_NO_VE','R3_NO_PRIORIZA','R4_NO_CUESTIONA','R5_EROSION_PROCESO','UNCLASSIFIED_WITH_REASON') then
    raise exception 'INPUT_GOVERNANCE_EKB_ROOT_CAUSE_FAMILY_INVALID';
  end if;
  if p_details->>'detectability' not in ('LOUD_EARLY','LOUD_LATE','SILENT','PROCESS_DEPENDENT') then
    raise exception 'INPUT_GOVERNANCE_EKB_DETECTABILITY_INVALID';
  end if;
  if jsonb_typeof(coalesce(p_details->'consumer_role','["Architect","Builder","Judge","Auditor"]'::jsonb))<>'array' then
    raise exception 'INPUT_GOVERNANCE_EKB_CONSUMER_ROLE_INVALID';
  end if;
  select coalesce(array_agg(value),'{}'::text[]) into v_roles from jsonb_array_elements_text(coalesce(p_details->'consumer_role','["Architect","Builder","Judge","Auditor"]'::jsonb));
  v_source_context:=coalesce(nullif(btrim(p_details->>'source_context'),''),format('INPUT_GOVERNANCE_AGENT/%s',p_phase));
  v_source_ref:=coalesce(nullif(btrim(p_details->>'source_ref'),''),case when p_run_id is null then format('screen://%s',p_pantalla_id) else format('input-readiness-run://%s',p_run_id) end);

  insert into transversal.error_knowledge(
    codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,frecuencia,
    primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,lifecycle_phase,consumer_role,
    root_cause_family,detectability,source_context,source_ref
  ) values (
    p_error_code,p_details->>'categoria',p_details->>'titulo',p_details->>'descripcion',p_details->>'causa_raiz',p_details->>'patron',p_details->>'prevencion',p_details->>'validacion',p_details->>'severidad',1,
    now(),now(),p_details->>'lote_origen',p_details->>'pr','activo',format('[INPUT_GOVERNANCE %s screen=%s run=%s] %s',p_phase,p_pantalla_id,coalesce(p_run_id::text,'NONE'),p_evidence),p_details->>'lifecycle_phase',v_roles,
    p_details->>'root_cause_family',p_details->>'detectability',v_source_context,v_source_ref
  );
  v_receipt:=jsonb_build_object('schema_version',1,'classification',v_class,'write_performed',true,'outcome','INSERTED_NEW_VERIFIED_ERROR','error_code',p_error_code,'frequency_after',1,'phase',p_phase,'pantalla_id',p_pantalla_id,'run_id',p_run_id,'observed_at',now());
  return v_receipt||jsonb_build_object('receipt_sha256',programacion.fn_v09_sha256_jsonb(v_receipt));
end;$f$;

revoke all on function programacion.fn_input_governance_record_ekb_occurrence(text,text,text,integer,bigint,text,jsonb) from public,anon,authenticated;
grant execute on function programacion.fn_input_governance_record_ekb_occurrence(text,text,text,integer,bigint,text,jsonb) to service_role;
comment on function programacion.fn_input_governance_record_ekb_occurrence(text,text,text,integer,bigint,text,jsonb) is 'Governed EKB writer for INPUT_GOVERNANCE_AGENT: verified recurrence updates existing; verified new error requires full metadata; suspicion/no-error never write.';

do $check$
declare b_count bigint; a_count bigint; b_freq integer; a_freq integer; r jsonb;
begin
  select count(*) into b_count from transversal.error_knowledge;
  r:=programacion.fn_input_governance_record_ekb_occurrence('NO_ERROR',null,'CLOSE_EKB',51,183,null,'{}');
  if coalesce((r->>'write_performed')::boolean,true) then raise exception 'EKB_NO_ERROR_WROTE'; end if;
  r:=programacion.fn_input_governance_record_ekb_occurrence('SUSPICION','GOV-010','PRE_CURATOR',51,183,'selftest suspicion','{}');
  if coalesce((r->>'write_performed')::boolean,true) or r->>'outcome'<>'PROPOSAL_OR_BLOCKER_REQUIRED' then raise exception 'EKB_SUSPICION_WROTE'; end if;
  select count(*) into a_count from transversal.error_knowledge;
  if a_count<>b_count then raise exception 'EKB_NO_WRITE_SELFTEST_CHANGED_CARDINALITY'; end if;

  select frecuencia into b_freq from transversal.error_knowledge where codigo='GOV-010';
  begin
    r:=programacion.fn_input_governance_record_ekb_occurrence('RECURRENCE','GOV-010','PRE_EXECUTION',51,183,'rollback-only recurrence selftest','{}');
    select frecuencia into a_freq from transversal.error_knowledge where codigo='GOV-010';
    if a_freq<>b_freq+1 then raise exception 'EKB_RECURRENCE_INCREMENT_FAILED'; end if;
    raise exception 'ROLLBACK_RECURRENCE_SELFTEST';
  exception when others then
    if sqlerrm<>'ROLLBACK_RECURRENCE_SELFTEST' then raise; end if;
  end;
  select frecuencia into a_freq from transversal.error_knowledge where codigo='GOV-010';
  if a_freq<>b_freq then raise exception 'EKB_RECURRENCE_SELFTEST_PERSISTED'; end if;

  begin
    r:=programacion.fn_input_governance_record_ekb_occurrence(
      'NEW_ERROR','ZZZ-INPUT-GOV-SELFTEST','PRE_EXECUTION',51,183,'rollback-only new-error selftest',
      jsonb_build_object('categoria','SELFTEST','titulo','Rollback-only selftest','descripcion','Must never persist','prevencion','No persistence','validacion','Row absent after rollback','severidad','Low','lifecycle_phase','testing','root_cause_family','UNCLASSIFIED_WITH_REASON','detectability','LOUD_EARLY','consumer_role',jsonb_build_array('Builder'))
    );
    if not exists(select 1 from transversal.error_knowledge where codigo='ZZZ-INPUT-GOV-SELFTEST') then raise exception 'EKB_NEW_ERROR_INSERT_FAILED'; end if;
    raise exception 'ROLLBACK_NEW_ERROR_SELFTEST';
  exception when others then
    if sqlerrm<>'ROLLBACK_NEW_ERROR_SELFTEST' then raise; end if;
  end;
  if exists(select 1 from transversal.error_knowledge where codigo='ZZZ-INPUT-GOV-SELFTEST') then raise exception 'EKB_NEW_ERROR_SELFTEST_PERSISTED'; end if;
end;$check$;
