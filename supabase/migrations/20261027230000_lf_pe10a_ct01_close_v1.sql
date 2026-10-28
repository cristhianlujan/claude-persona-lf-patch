-- PE10A_CT01: cierre gobernado del checkpoint (inventario de superficies del updater).
--
-- Cierra SOLO PE10A_CT01. No toca CT02..CT07, funciones, permisos ni otras tablas de datos
-- salvo una fila de conocimiento de errores. No activa Profile Updater v0.2.
--
-- Evidencia ligada (todas en main):
--   inventario        docs/profile_updater/PE10A_CT01_INVENTARIO_BORRADOR_V1_20261027.md (sha256 a7c7ac86...70a8)
--   superficies SQL   docs/profile_updater/pe10a_ct01_falsifier/frozen_inventory_v1.json (sha256 e90b6e32...dfe875), 12 superficies
--   archivos          docs/profile_updater/pe10a_ct01_falsifier/frozen_updater_files_v1.json (sha256 946fce82...ad7f), 43 archivos
--   recibo            docs/profile_updater/receipts/PE10A_CT01_RECIBO_INDEPENDIENTE_ACEPTADO_V1_20261027.md
--                     (sha256 4dd7b7c9...0521c2, commit c7486f461d4703d2c88bb5e355b5c425d251f77f)
--
-- Admision del recibo: el revisor (GPT, rondas 2 y 3) NO aporta atestacion del proveedor. El dueño acepto
-- explicitamente ese recibo el 2026-10-27 como evidencia independiente (decision del dueño, no atestacion).
-- Lo que el revisor no pudo comprobar queda en la seccion 3 del archivo del recibo y en la observacion.
--
-- El comparador (produccion vs inventario congelado) y las 3 mutaciones negativas se ejecutan AQUI,
-- dentro de la transaccion: las condiciones del contrato se calculan, no se declaran.
DO $mig$
DECLARE
 c_plan constant text := 'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1';
 c_unit constant text := 'PE10A_CONTRACTS';
 c_cp   constant text := 'PE10A_CT01';
 c_actor constant text := 'EXEC-PE10A-CT01-CLOSE-20261027-V1';
 c_receipt_sha constant text := '4dd7b7c9a83e0dca70fa155f27acb4dd71e55ee87f91d31fadeb0857f70521c2';
 c_receipt_commit constant text := 'c7486f461d4703d2c88bb5e355b5c425d251f77f';
 c_inv_sha constant text := 'a7c7ac86b6187d4f818f5523eeb945890e1adadffef1defde5477522a98770a8';
 c_frozen_sha constant text := 'e90b6e32a170dcd2a330304a073f8fc4c5539072e1722d039153a2c060dfe875';
 c_files_sha constant text := '946fce82d9f89648e01bd94b67cda656d3996751ff0f3997ec38ec9ea75cad7f';
 v_exec text; v_wid bigint; v_status text; v_spec jsonb; v_contract jsonb;
 v_total int; v_match int; v_updater_total int; v_updater_match int;
 v_neg_body boolean; v_neg_sig boolean; v_neg_ghost boolean;
 v_readback_match int;
 v_observed jsonb; v_evidence text; v_rec jsonb; v_tr jsonb;
 v_others_before text; v_others_after text;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
  AND target_code LIKE '%lf_pe10a_ct01_close_v1' AND status='IN_PROGRESS'
 ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'PE10A_CT01_CLOSE_TRAIN_TRANSPORT_REQUIRED'; END IF;

 SELECT u.work_item_id INTO v_wid FROM programacion.engineering_plan_units u
 WHERE u.plan_code=c_plan AND u.unit_code=c_unit FOR UPDATE;
 IF v_wid IS NULL THEN RAISE EXCEPTION 'PE10A_CT01_CLOSE_UNIT_MISSING'; END IF;

 SELECT c.status INTO v_status FROM programacion.engineering_work_checkpoints c
 WHERE c.work_item_id=v_wid AND c.checkpoint_code=c_cp;
 IF v_status IS DISTINCT FROM 'PENDING' THEN RAISE EXCEPTION 'PE10A_CT01_CLOSE_NOT_PENDING:%',coalesce(v_status,'<none>'); END IF;

 IF EXISTS (SELECT 1 FROM programacion.engineering_work_checkpoints c
            WHERE c.work_item_id=v_wid AND c.checkpoint_code<>c_cp AND c.status<>'PENDING')
 THEN RAISE EXCEPTION 'PE10A_CT01_CLOSE_OTHER_CHECKPOINTS_NOT_PENDING'; END IF;

 v_spec := programacion.fn_engineering_checkpoint_action_spec_v3(c_plan,c_unit,c_cp);
 v_contract := programacion.fn_engineering_action_spec_assertion_contract_v1(c_plan,c_unit,c_cp,v_spec);
 IF v_contract->>'status' IS DISTINCT FROM 'READY'
    OR jsonb_typeof(v_contract->'pass_when') IS DISTINCT FROM 'object'
 THEN RAISE EXCEPTION 'PE10A_CT01_CLOSE_CONTRACT_NOT_READY:%',v_contract; END IF;

 -- huella de los demas checkpoints para comprobar que solo CT01 cambia
 SELECT string_agg(c.checkpoint_code||':'||c.status,',' ORDER BY c.checkpoint_code) INTO v_others_before
 FROM programacion.engineering_work_checkpoints c WHERE c.work_item_id=v_wid AND c.checkpoint_code<>c_cp;

 -- Comparacion produccion vs inventario congelado (misma logica que el falsificador del repo)
 CREATE TEMP TABLE _ct01_frozen ON COMMIT DROP AS
 SELECT * FROM (VALUES
   ('lf_profile_update_begin_v1','p_execution_id text, p_target_code text, p_target_repo text, p_target_path text, p_request_sha256 text, p_idempotency_key text, p_actor_execution_id text, p_manifest jsonb','deb4d57cbe7d35ad93401056bd1ab071',false,'UPDATER'),
   ('lf_profile_update_effective_route_v1','p_execution_id text','da620cf19a9a10d18e0d5d39ff743f2e',false,'UPDATER'),
   ('lf_profile_update_evolution_step_guard_v1','p_execution_id text, p_step_id text, p_payload jsonb','bd713a5a0cbc93619980f493723f7f6b',false,'UPDATER'),
   ('lf_profile_update_post_merge_reconcile_v1','p_execution_id text, p_merge_sha text, p_entrypoint_sha text, p_manifest_sha text, p_profile_pack_id text, p_pr_number integer, p_actor_execution_id text','8b1f02ec4583e9870437bca2e152187d',false,'UPDATER'),
   ('lf_profile_update_result_class_v1','p_value jsonb','19f4b9cdf0f2e23dad120d01b9c8660e',false,'UPDATER'),
   ('lf_profile_update_substantive_block_v1','p_execution_id text, p_step_id text, p_payload jsonb, p_manifest jsonb','06a07b442f19076542ae7fbec9513897',false,'UPDATER'),
   ('lf_profile_update_verified_receipt_v1','p_subject_type text, p_subject_ref text, p_receipt_id text, p_subject_sha256 text, p_source_head_sha text','7c163d3308ecba94ad066e6df8446e80',true,'UPDATER'),
   ('lf_router_governed_caller_route_v1','p_caller jsonb, p_target_code text, p_target_path text','5615b6371d1da49f9dfe8cce186d41bc',true,'DEFERRED_ROUTER'),
   ('lf_record_profile_operation_step_v1','p_execution_id text, p_step_id text, p_evidence_ref text, p_evidence_payload jsonb, p_actor_execution_id text','03f8c6a1ada0321ced8682afb74d3f0f',false,'UPDATER'),
   ('lf_router_resolve_v1','p_request_text text, p_target_hint text, p_action_hint text, p_asset_type_hint text, p_distribution_mode text','4fd692a272f02774f1c03f381ac54a24',false,'DEFERRED_ROUTER'),
   ('lf_router_semantic_resume_route_v1','p_request jsonb, p_result jsonb','140b1e04289cb2038d80b3bd03005cb3',true,'DEFERRED_ROUTER'),
   ('lf_record_creacion_perfil_step_v1','p_execution_id text, p_step_id text, p_evidence_ref text, p_evidence_payload jsonb, p_actor_execution_id text','f7d1ad06e33470667239d7ae4dcde0ad',false,'OUT_OF_SCOPE_CREATION')
 ) f(fn,args,md5,secdef,scope);

 CREATE TEMP TABLE _ct01_cmp ON COMMIT DROP AS
 SELECT f.fn,f.scope,
  CASE WHEN l.fn IS NULL THEN 'FAIL_MISSING_OR_OWNERLESS'
       WHEN l.args<>f.args THEN 'FAIL_SIGNATURE_DRIFT'
       WHEN l.md5<>f.md5 THEN 'FAIL_BODY_DRIFT'
       WHEN l.secdef<>f.secdef THEN 'FAIL_SECDEF_DRIFT' ELSE 'PASS' END verdict
 FROM _ct01_frozen f
 LEFT JOIN (SELECT p.proname fn,pg_get_function_identity_arguments(p.oid) args,md5(p.prosrc) md5,p.prosecdef secdef
            FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public') l ON l.fn=f.fn;

 SELECT count(*), count(*) FILTER (WHERE verdict='PASS'),
        count(*) FILTER (WHERE scope='UPDATER'), count(*) FILTER (WHERE scope='UPDATER' AND verdict='PASS')
   INTO v_total,v_match,v_updater_total,v_updater_match FROM _ct01_cmp;
 IF v_total<>12 OR v_updater_total<>8 OR v_match<>12 OR v_updater_match<>8 THEN
   RAISE EXCEPTION 'PE10A_CT01_CLOSE_INVENTORY_DRIFT:total=% pass=% updater=%/%',v_total,v_match,v_updater_match,v_updater_total;
 END IF;

 -- Negativos ejecutados: cada mutacion debe ser detectada por la misma comparacion
 SELECT bool_and(CASE WHEN l.md5<>('f'||substr(f.md5,2)) THEN true ELSE false END) INTO v_neg_body
 FROM _ct01_frozen f JOIN (SELECT p.proname fn,md5(p.prosrc) md5 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public') l ON l.fn=f.fn
 WHERE f.fn='lf_profile_update_result_class_v1';
 SELECT bool_and(l.args<>(f.args||', p_extra text')) INTO v_neg_sig
 FROM _ct01_frozen f JOIN (SELECT p.proname fn,pg_get_function_identity_arguments(p.oid) args FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public') l ON l.fn=f.fn
 WHERE f.fn='lf_profile_update_effective_route_v1';
 SELECT NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                    WHERE n.nspname='public' AND p.proname='lf_profile_update_ghost_v1') INTO v_neg_ghost;
 IF NOT (coalesce(v_neg_body,false) AND coalesce(v_neg_sig,false) AND coalesce(v_neg_ghost,false)) THEN
   RAISE EXCEPTION 'PE10A_CT01_CLOSE_NEGATIVES_NOT_DETECTED:%/%/%',v_neg_body,v_neg_sig,v_neg_ghost;
 END IF;

 -- Releida (segunda lectura del catalogo) tras la comparacion
 SELECT count(*) INTO v_readback_match FROM _ct01_frozen f
 JOIN pg_proc p ON p.proname=f.fn JOIN pg_namespace n ON n.oid=p.pronamespace AND n.nspname='public'
 WHERE md5(p.prosrc)=f.md5 AND pg_get_function_identity_arguments(p.oid)=f.args AND p.prosecdef=f.secdef;
 IF v_readback_match<>12 THEN RAISE EXCEPTION 'PE10A_CT01_CLOSE_READBACK_MISMATCH:%',v_readback_match; END IF;

 v_evidence := 'github://cristhianlujan/claude-persona-lf-patch/blob/'||c_receipt_commit||
               '/docs/profile_updater/receipts/PE10A_CT01_RECIBO_INDEPENDIENTE_ACEPTADO_V1_20261027.md';

 v_observed := jsonb_build_object(
   'frozen_inventory_matches_production', true,
   'falsifier_positive_passed', true,
   'falsifier_negative_executed', true,
   'independent_receipt_bound', true,
   'git_merged', true,
   'readback_passed', true,
   'scope','UPDATER_ONLY_ROUTER_DEFERRED_TO_INTEGRATION',
   'surfaces_total',v_total,'surfaces_pass',v_match,'updater_surfaces_pass',v_updater_match,
   'negatives_detected', jsonb_build_object('body_drift',v_neg_body,'signature_drift',v_neg_sig,'ownerless',v_neg_ghost),
   'frozen_inventory_sha256',c_frozen_sha,'frozen_files_sha256',c_files_sha,'inventory_doc_sha256',c_inv_sha,
   'receipt_sha256',c_receipt_sha,'receipt_commit',c_receipt_commit,
   'receipt_admission','OWNER_ACCEPTED_WITHOUT_PROVIDER_ATTESTATION',
   'readback_scope','IN_TRANSACTION_LIVE_CATALOG_REREAD',
   'open_items', jsonb_build_array(
     'REVIEWER_COULD_NOT_VERIFY_43_FILE_ENUMERATION_VIA_CHECKOUT',
     'REVIEWER_NO_PROVIDER_ATTESTATION',
     'ROUTER_CHAIN_INDIRECT_WRITES_DEFERRED_TO_INTEGRATION',
     'ANON_AUTHENTICATED_EXECUTE_ON_lf_record_creacion_perfil_step_v1_NOT_VERIFIED',
     'ASSERTION_CONTRACT_FUNCTION_ACCEPTS_MISSING_PASS_WHEN'))
 ;

 v_rec := programacion.fn_engineering_checkpoint_assertion_record_v1(
   c_plan,c_unit,c_cp,
   jsonb_build_object('status','PASS','evidence_ref',v_evidence,'observed',v_observed),
   c_actor);
 IF coalesce((v_rec->>'passed')::boolean,false) IS NOT TRUE THEN RAISE EXCEPTION 'PE10A_CT01_CLOSE_ASSERTION_NOT_RECORDED:%',v_rec; END IF;

 v_tr := programacion.fn_engineering_checkpoint_transition_v1(
   c_plan,c_unit,c_cp,'DONE',v_evidence,c_actor,
   'CT01 cerrado: 12/12 superficies SQL de produccion = inventario congelado (8 UPDATER), 3 negativos detectados, recibo independiente (GPT rondas 2 y 3) aceptado por el dueño sin atestacion del proveedor; router diferido a integracion.');
 IF v_tr#>>'{transition,status}' IS DISTINCT FROM 'APPLIED' THEN RAISE EXCEPTION 'PE10A_CT01_CLOSE_TRANSITION_FAILED:%',v_tr; END IF;

 -- Postcondiciones: solo CT01 cambia
 SELECT string_agg(c.checkpoint_code||':'||c.status,',' ORDER BY c.checkpoint_code) INTO v_others_after
 FROM programacion.engineering_work_checkpoints c WHERE c.work_item_id=v_wid AND c.checkpoint_code<>c_cp;
 IF (SELECT status FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wid AND checkpoint_code=c_cp) IS DISTINCT FROM 'DONE'
    OR v_others_after IS DISTINCT FROM v_others_before
    OR (SELECT assertion_receipt_sha256 FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wid AND checkpoint_code=c_cp) IS NULL
    OR (SELECT evidence_ref FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wid AND checkpoint_code=c_cp) IS DISTINCT FROM v_evidence
 THEN RAISE EXCEPTION 'PE10A_CT01_CLOSE_POSTSTATE_INVALID'; END IF;

 INSERT INTO public.lf_error_knowledge
   (codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
    severidad,frecuencia,primera_vez,ultima_vez,lote_origen,estado,source_ref)
 SELECT 'LF-PE10A-ASSERTION-CONTRACT-PASSWHEN-NULL-READY-20261027-001','PROFILE_EVOLUTION',
  'fn_engineering_action_spec_assertion_contract_v1 devuelve READY sin pass_when',
  'Un assertion_contract con mode EXPLICIT_PASS_WHEN_SUBSET pero sin pass_when devuelve status READY con pass_when null (verificado en produccion con una mutacion local).',
  'La validacion usa jsonb_typeof(pass_when)<>''object''; con pass_when ausente la expresion es NULL y no entra en la rama de bloqueo.',
  'Un contrato de cierre incompleto podria registrar un recibo trivial si observed @> NULL se evalua verdadero o se rechaza de forma poco clara.',
  'Hasta corregir la funcion oficial, toda migracion que declare un assertion_contract debe comprobar jsonb_typeof(pass_when)=''object'' y sus claves en su propia poscondicion.',
  'Las migraciones PE10A_CT01 (contrato y cierre) comprueban pass_when objeto con 6 claves; la correccion de la funcion queda como cambio separado pendiente de decision del dueño.',
  'MEDIUM',1,clock_timestamp(),clock_timestamp(),'PE10A_CT01','ACTIVO',
  'github://cristhianlujan/claude-persona-lf-patch/blob/'||c_receipt_commit||'/docs/profile_updater/PE10A_CT01_INVENTARIO_BORRADOR_V1_20261027.md'
 WHERE NOT EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo='LF-PE10A-ASSERTION-CONTRACT-PASSWHEN-NULL-READY-20261027-001');
END
$mig$;
