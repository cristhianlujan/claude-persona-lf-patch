-- LF PE10 gap closure (plan registration only), found by independent review of 2026-10-27.
-- Adds 4 PENDING checkpoints (PE10A_CT07, PE10A_SB06, PE10A_OP09, PE10_C8) to EXISTING units and amends the
-- criteria/reuse direction of 12 EXISTING PENDING checkpoints. No new unit, no new dependency row.
-- 28 units, 144 -> 148 checkpoints, 79 DONE / 3 NOT_APPLICABLE unchanged, PENDING 62 -> 66, 22 dependencies unchanged.
-- PE10_C6/C7 stay PENDING and unmodified. No profile, Edge, runtime or v0.2 activation.
-- Transport: ACTUALIZACION_DB_LF / LF Migration Merge Train only (execution binding is mandatory).
BEGIN;
DO $lf_pe10_gap$
DECLARE
 v_exec text;
 v_parent_id bigint;
 v_unit text;
 v_wid bigint;
 v_meta jsonb;
 v_in jsonb;
 v_spec jsonb;
 v_item jsonb;
 v_code text;
 v_kp text; v_kn text; v_kr text;
 v_expected_seq int;
 v_dep_before integer;
 v_plan text := 'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1';
 -- [unit, code, seq, title, positive, negative, reuses, schema]
 v_new jsonb := '[
  ["PE10A_CONTRACTS","PE10A_CT07",7,"Binding pre-escritura del conjunto completo de archivos del cambio",
   "write_plan enumera cada archivo del pack a cambiar con path y blob SHA al bound_revision; el gate pre-escritura valida el conjunto completo y no solo un target_path; prueba positiva con al menos 2 archivos en un cambio multi-archivo coherente",
   "Una escritura de un archivo fuera del plan, con blob distinto al enlazado, o un plan de un solo archivo cuando el cambio toca varios, se rechaza antes de github_write",
   "PE10A_CT03, PE10A_GH01, PE5A_C2","A"],
  ["PE10A_SUPABASE","PE10A_SB06",6,"Readiness y transiciones respetan dependencias entre work items",
   "fn_engineering_checkpoint_execution_readiness_v1 y la transicion de cierre devuelven NOT_READY con razon tipada de dependencia mientras algun work item requerido no este DONE o NOT_APPLICABLE; PE10_C6 y PE10_C7 dejan de ser READY con PE10A_READY pendiente; readback antes y despues ligado al SHA de la migracion que cambia la funcion",
   "Un checkpoint con todas sus dependencias completas no queda bloqueado; un plan sin filas de dependencia conserva su comportamiento; el cambio no altera el resultado de ningun checkpoint ya DONE",
   "PE10A_SB02, PE10A_PL03, PE10_C6","A"],
  ["PE10A_READY","PE10A_OP09",9,"Ensayo de rollback de autoridad v0.2 a v0.1 antes del cutover",
   "Una transaccion con ROLLBACK demuestra restaurar la politica y autoridad v0.1 desde el estado v0.2 candidato, con readback de pasos activos (15) y recibo ligado a execution_id y SHA; v0.1 queda preservada como ultima version util",
   "Un rollback que deja los pasos 35 y 37 activos bajo v0.1, un juez sin binding o una ejecucion IN_PROGRESS huerfana falla",
   "PE10A_GH06, PE10A_OP06, PE10_C6","A"]
 ]'::jsonb;
 -- [unit, code, schema, append_positive, append_negative, reuse_old, reuse_new, append_reuse]
 v_amend jsonb := '[
  ["PE10A_CONTRACTS","PE10A_CT04","A",
   "; el esquema de evidencia de change_scope y de los pasos 35 y 37 incluye campos tipados para la operacion por nodo (KEEP, ADD, REPLACE, REMOVE, MERGE, SPLIT, REORDER, DEPRECATE, CONDITIONAL, NO_CHANGE) y para los recibos de metodos e investigacion ejecutados",
   "; evidencia de esos pasos sin los campos tipados se rechaza",null,null,null],
  ["PE10A_STRUCTURE","PE10A_ST03","B",
   "; la operacion por nodo se registra en los campos tipados definidos por PE10A_CT04",
   "; una operacion por nodo registrada fuera de esos campos no cuenta como evidencia",null,null,null],
  ["PE10A_SUPABASE","PE10A_SB04","A",
   "; re-ejecuta el invariante de PE10_C4 (cero ejecuciones ACTUALIZACION_PERFIL_LF IN_PROGRESS o BLOCKED sin proxima accion) en el momento del cutover; la lectura del 27-oct-2026 mostro 1 IN_PROGRESS sin pasos (UI-ARCHITECT, 23-oct) y 4 BLOCKED de septiembre por clasificar",
   "; una ejecucion abierta sin clasificar bloquea PE10_C6",null,null,null],
  ["PE10A_STRUCTURE","PE10A_ST09","B",null,null,"PE10A_CT04, PE10A_GH05, PE10A_OP02","PE10A_CT04, PE10A_GH05",null],
  ["PE10A_STRUCTURE","PE10A_ST10","B",null,null,"PE10E_C1, PE10A_OP03, PE10A_OP04","PE10E_C1",null],
  ["PE10A_STRUCTURE","PE10A_ST11","B",null,null,"PE10A_PL06, PE10A_GH06, PE10A_OP06","PE10A_PL06, PE10A_GH06",null],
  ["PE10A_STRUCTURE","PE10A_ST12","B",null,null,"PE10A_SR03, PE10A_SR04, PE10A_OP08","PE10A_SR03, PE10A_SR04",null],
  ["PE10A_READY","PE10A_OP02","A",null,null,null,null,"; agrega los recibos de PE10A_ST09"],
  ["PE10A_READY","PE10A_OP03","A",null,null,null,null,"; agrega los recibos de PE10A_ST10"],
  ["PE10A_READY","PE10A_OP04","A",
   "; agrega los 4 casos reales de PE10A_ST10 y no es un segundo E2E",null,null,null,"; agrega los recibos de PE10A_ST10"],
  ["PE10A_READY","PE10A_OP06","A",null,null,null,null,"; agrega los recibos de PE10A_ST11"],
  ["PE10A_READY","PE10A_OP07","A",null,null,null,null,"; repite PE10A_GH05 con fecha y SHA nuevos"],
  ["PE10A_READY","PE10A_OP08","A",
   "; exige el recibo verde de PE10A_OP09 y los recibos de PE10A_ST12",null,null,null,"; agrega los recibos de PE10A_ST12 y PE10A_OP09"]
 ]'::jsonb;
BEGIN
 SELECT execution_id INTO v_exec FROM public.lf_operation_execution
 WHERE operation_code='ACTUALIZACION_DB_LF' AND target_type='MIGRATION'
  AND target_code LIKE '%lf_pe10_gap_closure_readiness_dependencies_v1'
  AND status='IN_PROGRESS'
 ORDER BY created_at DESC LIMIT 1;
 IF v_exec IS NULL THEN RAISE EXCEPTION 'PE10_GAP_CLOSURE_TRAIN_TRANSPORT_REQUIRED'; END IF;

 SELECT w.id INTO STRICT v_parent_id FROM programacion.engineering_work_items w
 WHERE w.work_code='PEVO-PE10' AND w.status='IN_PROGRESS';

 IF (SELECT count(*) FROM programacion.engineering_plan_units WHERE plan_code=v_plan)<>28
  OR (SELECT count(*) FROM programacion.engineering_work_checkpoints c JOIN programacion.engineering_plan_units u
      ON u.work_item_id=c.work_item_id WHERE u.plan_code=v_plan)<>144
  OR (SELECT count(*) FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_parent_id
      AND checkpoint_code IN ('PE10_C6','PE10_C7') AND status='PENDING')<>2
  OR EXISTS (SELECT 1 FROM programacion.engineering_work_checkpoints
      WHERE checkpoint_code IN ('PE10A_CT07','PE10A_SB06','PE10A_OP09','PE10_C8'))
  OR (SELECT version FROM public.lf_operation_registry WHERE operation_code='ACTUALIZACION_PERFIL_LF')<>'v0.1'
 THEN RAISE EXCEPTION 'PE10_GAP_CLOSURE_PRESTATE_STALE_OR_DUPLICATE'; END IF;

 SELECT count(*) INTO v_dep_before FROM programacion.engineering_work_dependencies d
  JOIN programacion.engineering_plan_units u ON u.work_item_id=d.work_item_id AND u.plan_code=v_plan;

 -- every checkpoint touched must still be PENDING with no evidence or receipt (nothing closed is rewritten)
 IF EXISTS (
   SELECT 1 FROM jsonb_array_elements(v_amend) a
   JOIN programacion.engineering_plan_units u ON u.plan_code=v_plan AND u.unit_code=a->>0
   LEFT JOIN programacion.engineering_work_checkpoints c ON c.work_item_id=u.work_item_id AND c.checkpoint_code=a->>1
   WHERE c.id IS NULL OR c.status<>'PENDING' OR c.evidence_ref IS NOT NULL OR c.assertion_receipt IS NOT NULL)
 THEN RAISE EXCEPTION 'PE10_GAP_CLOSURE_AMEND_TARGET_NOT_PENDING_OR_MISSING'; END IF;

 -- 1) new checkpoints inside existing units
 FOR v_item IN SELECT value FROM jsonb_array_elements(v_new)
 LOOP
  v_unit:=v_item->>0; v_code:=v_item->>1; v_expected_seq:=(v_item->>2)::int;
  SELECT u.work_item_id, u.unit_metadata INTO STRICT v_wid, v_meta
  FROM programacion.engineering_plan_units u WHERE u.plan_code=v_plan AND u.unit_code=v_unit FOR UPDATE;
  IF (SELECT coalesce(max(sequence_no),0)+1 FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_wid)<>v_expected_seq
   THEN RAISE EXCEPTION 'PE10_GAP_CLOSURE_SEQUENCE_MISMATCH_%',v_code; END IF;
  INSERT INTO programacion.engineering_work_checkpoints
   (work_item_id,checkpoint_code,title,sequence_no,weight,required,status,created_by_execution_id)
  VALUES (v_wid,v_code,v_item->>3,v_expected_seq,1,true,'PENDING',v_exec);
  v_in := jsonb_build_object('purpose',v_item->>3,'positive_evidence_required',v_item->>4,
     'negative_evidence_required',v_item->>5,'prior_work_reused',v_item->>6,
     'evidence_mode','REAL_PROVIDER_BOUND_READBACK','source_currentness','EXACT_CURRENT_SHA',
     'no_unqualified_claims',true);
  v_spec := jsonb_build_object('status','BLOCK_PENDING_IMPLEMENTATION_AND_INDEPENDENT_RECEIPT',
     'action_kind','GOVERNED_MATERIAL_VERIFICATION','recipe_mode','EVIDENCE_FIRST',
     'requires_material_execution',true,'positive_test',v_item->>4,'negative_test',v_item->>5,
     'validator_contract_status','EXACT_EXISTING_VALIDATOR_TO_BE_BOUND_PER_CHECKPOINT',
     'closure_route','AUTHORIZED_OPERATION_THEN_TRAIN_AND_POST_READBACK',
     'forbidden',jsonb_build_array('CLAIM_PASS_WITHOUT_EXECUTION','REUSE_STALE_OR_UNSCOPED_RECEIPT',
       'AUTO_ACTIVATE_V02','BYPASS_ROUTER_SRCR_OR_GOVERNED_TRANSPORT'));
  v_meta := jsonb_set(v_meta,'{checkpoint_ordering}',(v_meta->'checkpoint_ordering')||to_jsonb(v_code));
  v_meta := jsonb_set(v_meta,ARRAY['checkpoint_inputs',v_code],v_in,true);
  v_meta := jsonb_set(v_meta,ARRAY['action_specs_v1',v_code],v_spec,true);
  v_meta := jsonb_set(v_meta,'{gap_closure_additions}',coalesce(v_meta->'gap_closure_additions','[]'::jsonb)||to_jsonb(v_code),true);
  UPDATE programacion.engineering_plan_units SET unit_metadata=v_meta WHERE plan_code=v_plan AND unit_code=v_unit;
 END LOOP;

 -- PE10 parent: one post-cutover checkpoint (C6/C7 untouched). Sequence follows C7.
 IF (SELECT max(sequence_no) FROM programacion.engineering_work_checkpoints WHERE work_item_id=v_parent_id)<>8
  THEN RAISE EXCEPTION 'PE10_GAP_CLOSURE_PE10_SEQUENCE_MISMATCH'; END IF;
 INSERT INTO programacion.engineering_work_checkpoints
  (work_item_id,checkpoint_code,title,sequence_no,weight,required,status,created_by_execution_id)
 VALUES (v_parent_id,'PE10_C8','Corrida real post-cutover bajo autoridad v0.2 con retorno verificado',9,1,true,'PENDING',v_exec);

 -- 2) amendments to existing PENDING checkpoints (criteria, reuse direction)
 FOR v_item IN SELECT value FROM jsonb_array_elements(v_amend)
 LOOP
  v_unit:=v_item->>0; v_code:=v_item->>1;
  IF v_item->>2='A' THEN v_kp:='positive_evidence_required'; v_kn:='negative_evidence_required'; v_kr:='prior_work_reused';
  ELSE v_kp:='pass_when'; v_kn:='negative_falsifier'; v_kr:='reuses'; END IF;
  SELECT unit_metadata INTO STRICT v_meta FROM programacion.engineering_plan_units
   WHERE plan_code=v_plan AND unit_code=v_unit FOR UPDATE;
  v_in := v_meta->'checkpoint_inputs'->v_code;
  IF v_in IS NULL THEN RAISE EXCEPTION 'PE10_GAP_CLOSURE_METADATA_MISSING_%',v_code; END IF;
  IF jsonb_typeof(v_item->3)='string' THEN
    v_in := v_in||jsonb_build_object(v_kp,(v_in->>v_kp)||(v_item->>3));
    v_meta := jsonb_set(v_meta,ARRAY['action_specs_v1',v_code,'positive_test'],
      to_jsonb((v_meta->'action_specs_v1'->v_code->>'positive_test')||(v_item->>3)));
  END IF;
  IF jsonb_typeof(v_item->4)='string' THEN
    v_in := v_in||jsonb_build_object(v_kn,(v_in->>v_kn)||(v_item->>4));
    v_meta := jsonb_set(v_meta,ARRAY['action_specs_v1',v_code,'negative_test'],
      to_jsonb((v_meta->'action_specs_v1'->v_code->>'negative_test')||(v_item->>4)));
  END IF;
  IF jsonb_typeof(v_item->5)='string' THEN
    IF v_in->>v_kr IS DISTINCT FROM (v_item->>5) THEN RAISE EXCEPTION 'PE10_GAP_CLOSURE_REUSE_DRIFT_%',v_code; END IF;
    v_in := v_in||jsonb_build_object(v_kr,v_item->>6);
  END IF;
  IF jsonb_typeof(v_item->7)='string' THEN
    v_in := v_in||jsonb_build_object(v_kr,(v_in->>v_kr)||(v_item->>7));
  END IF;
  v_meta := jsonb_set(v_meta,ARRAY['checkpoint_inputs',v_code],v_in);
  v_meta := jsonb_set(v_meta,'{gap_closure_amendments}',coalesce(v_meta->'gap_closure_amendments','[]'::jsonb)||to_jsonb(v_code),true);
  UPDATE programacion.engineering_plan_units SET unit_metadata=v_meta WHERE plan_code=v_plan AND unit_code=v_unit;
 END LOOP;

 -- post-state readback
 IF (SELECT count(*) FROM programacion.engineering_plan_units WHERE plan_code=v_plan)<>28
  OR (SELECT count(*) FROM programacion.engineering_work_checkpoints c JOIN programacion.engineering_plan_units u
      ON u.work_item_id=c.work_item_id WHERE u.plan_code=v_plan)<>148
  OR (SELECT count(*) FROM programacion.engineering_work_checkpoints c JOIN programacion.engineering_plan_units u
      ON u.work_item_id=c.work_item_id WHERE u.plan_code=v_plan AND c.status='PENDING')<>66
  OR (SELECT count(*) FROM programacion.engineering_work_checkpoints c JOIN programacion.engineering_plan_units u
      ON u.work_item_id=c.work_item_id WHERE u.plan_code=v_plan AND c.status='DONE')<>79
  OR (SELECT count(*) FROM programacion.engineering_work_checkpoints c JOIN programacion.engineering_plan_units u
      ON u.work_item_id=c.work_item_id WHERE u.plan_code=v_plan AND c.status='NOT_APPLICABLE')<>3
  OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
      WHERE work_item_id=v_parent_id AND checkpoint_code IN ('PE10_C6','PE10_C7') AND status='PENDING')<>2
  OR (SELECT count(*) FROM programacion.engineering_work_dependencies d
      JOIN programacion.engineering_plan_units u ON u.work_item_id=d.work_item_id AND u.plan_code=v_plan)<>v_dep_before
  OR (SELECT version FROM public.lf_operation_registry WHERE operation_code='ACTUALIZACION_PERFIL_LF')<>'v0.1'
 THEN RAISE EXCEPTION 'PE10_GAP_CLOSURE_POST_REGISTER_FAILED'; END IF;
END $lf_pe10_gap$;
COMMIT;
