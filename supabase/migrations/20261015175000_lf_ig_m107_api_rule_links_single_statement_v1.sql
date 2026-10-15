-- M10.7 A4: single-statement materialized effective links for API resolution.
-- Exact pinned source; transactional fail-closed parity and EKB.
DO $a4$
DECLARE
 v_source text; v_new_source text;
 v_from integer; v_to integer;
 v_screen integer; v_original jsonb; v_result jsonb;
 v_old jsonb:='{}'::jsonb; v_negative_original jsonb; v_negative_new jsonb;
 v_error_old text; v_error_new text;
 v_millis numeric; v_timestart timestamptz; v_samples jsonb:='[]'::jsonb;
 v_acl text; v_evidence jsonb;
 v_code constant text:='IG-M107-A4-API-LINKS-ONE-STATEMENT-017';
BEGIN
 v_source:=pg_get_functiondef('programacion.fn_input_api_contract_resolution(integer)'::regprocedure);
 IF md5(v_source)<>'2e85e4de84938d42f17688101f5ab476' THEN
   RAISE EXCEPTION 'IG_M107_A4_SOURCE_DRIFT';
 END IF;
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code) THEN
   RAISE EXCEPTION 'IG_M107_A4_ALREADY_RECORDED';
 END IF;
 SELECT proacl::text INTO v_acl FROM pg_proc
 WHERE oid='programacion.fn_input_api_contract_resolution(integer)'::regprocedure;
 IF v_acl IS DISTINCT FROM '{postgres=X/postgres}' THEN
   RAISE EXCEPTION 'IG_M107_A4_ACL_DRIFT';
 END IF;
 v_from:=strpos(v_source,'  with rr as (');
 v_to:=strpos(v_source,'  return jsonb_build_object(');
 IF v_from<1 OR v_to<=v_from OR
   (length(v_source)-length(replace(v_source,'fn_input_effective_rule_links_v1',''))) / length('fn_input_effective_rule_links_v1')<>2 THEN
   RAISE EXCEPTION 'IG_M107_A4_SOURCE_STRUCTURE_DRIFT';
 END IF;
 FOREACH v_screen IN ARRAY ARRAY[1,43,53,55,58] LOOP
   v_timestart:=clock_timestamp();
   v_original:=programacion.fn_input_api_contract_resolution(v_screen);
   v_millis:=round((extract(epoch from (clock_timestamp()-v_timestart))*1000)::numeric,3);
   v_old:=jsonb_set(v_old,ARRAY[v_screen::text],v_original,true);
   v_samples:=v_samples||jsonb_build_array(jsonb_build_object('screen',v_screen,'phase','original','ms',v_millis));
 END LOOP;
 v_negative_original:=NULL; v_error_old:=NULL;
 BEGIN
   v_negative_original:=programacion.fn_input_api_contract_resolution(2147483647);
 EXCEPTION WHEN OTHERS THEN v_error_old:=SQLSTATE||':'||SQLERRM; END;
 -- Replace only the two original API-local queries, keeping the original return body.
 v_new_source:=substring(v_source from 1 for v_from-1) || $newblock$
  WITH effective_links AS MATERIALIZED (
    SELECT r.id,r.codigo,r.titulo,r.descripcion,r.valor_config,
           r.pendiente_decision,r.pendiente_detalle,r.estado
    FROM programacion.fn_input_effective_rule_links_v1(p_pantalla_id,'INPUT_GOVERNANCE') rp
    JOIN lf_ops.reglas r ON r.id=rp.regla_id
    WHERE rp.pantalla_id=p_pantalla_id
  ), rr AS (
    SELECT * FROM effective_links r
    WHERE r.valor_config ?| array[
        'gateway','method','provider_operation_alias','consumer_contract',
        'required_logical_inputs','required_fields','server_side_generation',
        'server_side_verification','provider_binding','api_contract_id',
        'operation_contract_id','request_schema_contract_id','response_schema_contract_id'
      ] OR r.descripcion ILIKE '%API_GATEWAY%'
        OR r.valor_config::text ILIKE '%operation_alias%'
  ), behavioral AS (
    SELECT count(*) cnt,coalesce(jsonb_agg(jsonb_build_object(
      'rule_id',id,'rule_code',codigo,'title',titulo,'description',descripcion,
      'config',valor_config,'pending_decision',pendiente_decision,
      'pending_detail',pendiente_detalle,'status',estado
    ) ORDER BY codigo),'[]'::jsonb) rules
    FROM rr
  ), candidate_refs AS (
    SELECT r.codigo rule_code,e.key ref_key,e.value ref_value
    FROM effective_links r
    CROSS JOIN LATERAL jsonb_each_text(coalesce(r.valor_config,'{}'::jsonb)) e
    WHERE e.key IN (
      'api_contract_id','operation_contract_id',
      'request_schema_contract_id','response_schema_contract_id'
    ) AND e.value ~ '^[0-9]+$'
  ), resolved AS (
    SELECT c.rule_code,c.ref_key,c.ref_value::bigint contract_id,
      pc.id IS NOT NULL resolved,pc.tipo,pc.estado,pc.fail_closed,pc.especificacion,
      CASE WHEN pc.id IS NULL THEN NULL ELSE jsonb_build_object(
        'contract_id',pc.id,'contract_code',pc.contrato_codigo,
        'type',pc.tipo,'state',pc.estado,'fail_closed',pc.fail_closed,
        'logical_contract_only',coalesce((pc.especificacion->>'logical_contract_only')::boolean,false),
        'runtime_activation',coalesce((pc.especificacion->>'runtime_activation')::boolean,
          CASE WHEN pc.especificacion ? 'runtime_activation' THEN false ELSE true END)
      ) END contract
    FROM candidate_refs c LEFT JOIN programacion.contratos pc ON pc.id=c.ref_value::bigint
  ), aggregated AS (
    SELECT count(*) FILTER(WHERE resolved) materialized_count,
      count(*) FILTER(WHERE NOT resolved) broken_count,
      count(*) FILTER(WHERE resolved AND estado='defined' AND fail_closed) defined_count,
      count(*) FILTER(WHERE resolved AND estado='defined' AND fail_closed
        AND coalesce((especificacion->>'logical_contract_only')::boolean,false)
        AND jsonb_typeof(especificacion->'request_schema')='object'
        AND jsonb_typeof(especificacion->'response_schema')='object') logical_count,
      count(*) FILTER(WHERE resolved AND estado='defined' AND fail_closed
        AND NOT coalesce((especificacion->>'logical_contract_only')::boolean,false)
        AND coalesce((especificacion->>'runtime_activation')::boolean,true)) executable_count,
      coalesce(jsonb_agg(jsonb_build_object(
        'rule_code',rule_code,'ref_key',ref_key,'contract_id',contract_id,
        'resolved',resolved,'contract',contract
      ) ORDER BY rule_code,ref_key),'[]'::jsonb) refs
    FROM resolved
  )
  SELECT b.cnt,b.rules,a.materialized_count,a.broken_count,a.defined_count,
         a.logical_count,a.executable_count,a.refs
    INTO v_behavior_count,v_rules,v_materialized_count,v_broken_count,
         v_defined_fail_closed_count,v_logical_count,v_executable_count,v_refs
    FROM behavioral b CROSS JOIN aggregated a;

$newblock$ || substring(v_source from v_to);
 EXECUTE v_new_source;
 IF (length(pg_get_functiondef('programacion.fn_input_api_contract_resolution(integer)'::regprocedure)) -
     length(replace(pg_get_functiondef('programacion.fn_input_api_contract_resolution(integer)'::regprocedure),
     'fn_input_effective_rule_links_v1',''))) / length('fn_input_effective_rule_links_v1')<>1 THEN
   RAISE EXCEPTION 'IG_M107_A4_RESOLVER_NOT_ONCE';
 END IF;
 IF (SELECT proacl::text FROM pg_proc
       WHERE oid='programacion.fn_input_api_contract_resolution(integer)'::regprocedure) IS DISTINCT FROM v_acl
    OR has_function_privilege('anon','programacion.fn_input_api_contract_resolution(integer)','EXECUTE')
    OR has_function_privilege('authenticated','programacion.fn_input_api_contract_resolution(integer)','EXECUTE')
    OR has_function_privilege('service_role','programacion.fn_input_api_contract_resolution(integer)','EXECUTE') THEN
   RAISE EXCEPTION 'IG_M107_A4_ACL_REGRESSION';
 END IF;
 FOREACH v_screen IN ARRAY ARRAY[1,43,53,55,58] LOOP
   v_timestart:=clock_timestamp();
   v_result:=programacion.fn_input_api_contract_resolution(v_screen);
   v_millis:=round((extract(epoch from (clock_timestamp()-v_timestart))*1000)::numeric,3);
   IF v_result IS DISTINCT FROM v_old->(v_screen::text)
      OR programacion.fn_v09_sha256_jsonb(v_result)
         IS DISTINCT FROM programacion.fn_v09_sha256_jsonb(v_old->(v_screen::text)) THEN
     RAISE EXCEPTION 'IG_M107_A4_PARITY_FAILED_SCREEN_%',v_screen;
   END IF;
   v_samples:=v_samples||jsonb_build_array(jsonb_build_object('screen',v_screen,'phase','new','ms',v_millis));
 END LOOP;
 v_negative_new:=NULL;v_error_new:=NULL;
 BEGIN
   v_negative_new:=programacion.fn_input_api_contract_resolution(2147483647);
 EXCEPTION WHEN OTHERS THEN v_error_new:=SQLSTATE||':'||SQLERRM; END;
 IF v_negative_new IS DISTINCT FROM v_negative_original OR v_error_new IS DISTINCT FROM v_error_old THEN
   RAISE EXCEPTION 'IG_M107_A4_NEGATIVE_CHANGED';
 END IF;
 v_evidence:=jsonb_build_object('schema','IG_M107_API_LINKS_ONCE_V1',
   'screens',jsonb_build_array(1,43,53,55,58),
   'old_md5','2e85e4de84938d42f17688101f5ab476',
   'new_md5',md5(pg_get_functiondef('programacion.fn_input_api_contract_resolution(integer)'::regprocedure)),
   'before_resolver_calls',2,'after_resolver_calls',1,
   'parity_json_sha',true,'negative_equal',true,'acl_preserved',true,
   'intercall_cache',false,'triggers_changed',false,'cp3_closed',false,
   'validator_p90_proven',false,'timings',v_samples);
 INSERT INTO public.lf_error_knowledge
   (id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,
    validacion,severidad,frecuencia,primera_vez,ultima_vez,lote_origen,
    estado,evidencia,created_at,updated_at,lifecycle_phase,root_cause_family,
    detectability,source_context,source_ref)
 VALUES
   (gen_random_uuid(),v_code,'GOVERNANCE',
    'A4: un resolvedor de reglas efectivo por función API',
    'Dos consultas de vínculos consolidadas mediante CTE MATERIALIZED en una sentencia, 5 equivalencias JSON/SHA y negativo; misma autoridad y permisos.',
    'fn_input_api_contract_resolution invocaba dos veces el mismo resolvedor.',
    'INCALL_API_RULE_RESOLUTION_ONCE',
    'Conservar currentness y comprobaciones de vigencia; no reutilizar entre llamadas hasta G2B.',
    'PR/Train con preflight MD5, 5 paridades, negativo y ACL; microtiempos no prueban p90.',
    'HIGH',1,clock_timestamp(),clock_timestamp(),
    'IG_CURATOR_VALIDATOR_REFACTOR_V2/M10.7','ACTIVO',
    v_evidence::text,clock_timestamp(),clock_timestamp(),'PREFLIGHT',
    'R4_NO_CUESTIONA','LOUD_EARLY','A4 atomic API resolver optimization',
    'programacion.fn_input_api_contract_resolution(integer)');
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=v_code)<>1 THEN
   RAISE EXCEPTION 'IG_M107_A4_EKB_READBACK_FAILED';
 END IF;
END $a4$;
