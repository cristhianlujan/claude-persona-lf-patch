-- IG 11:25: source-bound Step40 READ_ONLY IG blocked findings must explicitly
-- carry NO security clearance. Do not change reporting gates or historical RUNs.
-- Applied only by LF Migration Merge Train; tests use BEGIN/ROLLBACK.
BEGIN;
DO $fix$
DECLARE d text; old text;
BEGIN
 d:=pg_get_functiondef('public.lf_profile_native_bridge_prepare_v1(text,text,text,text)'::regprocedure);
 old:=d;
 d:=replace(d,
 $a$      'production_authorized',false,'promotion_authorized',false,
      'mutation_authorized',$a$,
 $b$      'production_authorized',false,'promotion_authorized',false,
      'ig_security_clearance',false,
      'mutation_authorized',$b$);
 IF d=old OR position($k$'ig_security_clearance',false$k$ IN d)=0 THEN
   RAISE EXCEPTION 'LF_IG1125_CLEARANCE_TRANSPORT_PATCH_NOT_APPLIED';
 END IF;
 EXECUTE d;
END $fix$;

DO $ekb$
DECLARE
 v_code text:='LF-PROFILE-STEP80-IG-CLEARANCE-OMITTED-20261116-001';
BEGIN
 IF EXISTS(SELECT 1 FROM public.lf_error_knowledge WHERE codigo=v_code) THEN
   RAISE EXCEPTION 'LF_IG1125_CLEARANCE_EKB_DUPLICATE';
 END IF;
 INSERT INTO public.lf_error_knowledge(
  id,codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,frecuencia,primera_vez,ultima_vez,lote_origen,pr,estado,evidencia,
  lifecycle_phase,consumer_role,root_cause_family,detectability,source_context,source_ref,
  created_at,updated_at)
 VALUES(
  gen_random_uuid(),v_code,'PROFILE_EXECUTION',
  'Step40 omite ig_security_clearance requerido por Step80',
  'Step80 exige literal false al reportar hallazgos IG bloqueados pero Step40 no escribe la clave.',
  'Contratos de productor y consumidor no alineados; NULL no equivale a false en SQL.',
  'REQUIRED_BOOLEAN_NOT_TRANSPORTED',
  'Persistir false explicito en Step40 READ_ONLY; mantener fail-closed de Step80.',
  'PG17/18 BEGIN/ROLLBACK + CI; readback EKB/migracion y Step40 en un RUN nuevo por ruta oficial.',
  'HIGH',1,clock_timestamp(),clock_timestamp(),
  'LF_IG1125_PROFILE_LOGIN_SESSION','PR_DRAFT','CANDIDATO',
  'readback SQL del contrato; pendiente test completo E2E sin corrida real',
  'PROFILE_EXECUTION',ARRAY['PRODUCT_DIRECTOR','ROUTER']::text[],
  'R5_EROSION_PROCESO','LOUD_LATE',
  'IG 11:25 2026-11-16 fuente pg_get_functiondef current, sin RN ni promociones',
  'https://github.com/cristhianlujan/claude-persona-lf-patch/pull/4056',
  clock_timestamp(),clock_timestamp());
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo=v_code)<>1 THEN
   RAISE EXCEPTION 'LF_IG1125_CLEARANCE_EKB_COUNT_INVALID';
 END IF;
END $ekb$;
COMMIT;
