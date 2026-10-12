-- M9.12 EKB: existing generic governance must be reused, not disabled POST_PASE.
DO $ekb$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM public.lf_error_knowledge
 WHERE codigo IN ('IG-M912-POSTPASE-RECEIPT-SOURCE-DRIFT-001','IG-M912-M98-LIVE-READBACK-BLOCKED-001','IG-M912-JSONB-MISSING-ACTION-SPEC-001');
 IF n<>0 THEN RAISE EXCEPTION 'M912_EKB_PREEXISTING_%',n; END IF;
 INSERT INTO public.lf_error_knowledge
 (codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
  severidad,frecuencia,lote_origen,pr,estado,evidencia,lifecycle_phase,
  consumer_role,root_cause_family,detectability,source_context,source_ref)
 VALUES
 ('IG-M912-POSTPASE-RECEIPT-SOURCE-DRIFT-001','GOVERNANCE',
 'M9.12 contrato usa FINAL_EVIDENCE/CLOSURE_GATE desactivados para CUTOVER_READY',
 'Aunque exit_criterion se corrigió, action_spec compilado y SOURCE_PACK aún dependían de artefactos y eventos POST_PASE históricos. CUTOVER_READY requiere ledger IG actual, bundle firmado de M9.0 y prerequisitos vigentes.',
 'Contradicción entre criterio de salida ya actualizado y contrato de checkpoint material; arrastre de workstream externo desactivado.',
 'INACTIVE_WORKSTREAM_IN_IG_RECEIPT_MATERIAL_GATE',
 'Corregir action_spec y SOURCE_PACK juntos; usar EVIDENCE_VERIFIER_V1 y programacion.provenance_receipts de IG, M9.8 readback y bundle M9.0; no añadir motor propio ni inferir activación productiva.',
 'Readback PASS cuando contract.mode=IG_LEDGER_SIGNED_RECEIPT, artefactos externos=0, prereq stale missing=0 y bootstrap=WAIT_DEPENDENCIES por M9.10; sin emitir CUTOVER_READY.',
 'HIGH',1,'IG_CURATOR_VALIDATOR_REFACTOR_V2',NULL,'VERIFICADO',
 'supabase://programacion.engineering_plan_units/M9.12; github://cristhianlujan/claude-persona-lf-patch/supabase/migrations/20261012021000_ig_m912_readiness_ig_owned_contract_v1.sql',
 'CONSTRUCTION',ARRAY['ENGINEERING_EXECUTOR','GOVERNANCE']::text[],
 'R5_EROSION_PROCESO','PROCESS_DEPENDENT','M9.12 contracts-only repair 2026-10-12 UTC',
 'programacion.engineering_plan_units M9.12'),
 ('IG-M912-M98-LIVE-READBACK-BLOCKED-001','ENGINEERING_VALIDATION',
 'M9.8 DONE no implica readback gobernado PASS para M9.12',
 'M9.8 está DONE en el ledger, pero fn_ig_m98_checkpoint_bound_readback_v2(M9.8) devolvió BLOCKED:GOVERNED_EVIDENCE_BINDING_MISSING. Un CHECKPOINT DONE sin vínculo de evidencia current no autoriza CUTOVER_READY.',
 'Se asumía que el estado histórico DONE equivalía a currentness de evidencia de assurance.',
 'DONE_WITH_GOVERNED_READBACK_CURRENTNESS_GAP',
 'El contrato M9.12 debe pedir M9.8 current PASS, evidencias firmadas y match SHA; fail closed mientras el readback real esté BLOCKED; no reabrir ni alterar M9.8 sin análisis separado.',
 'M9.12 NO DONE ni CUTOVER_READY mientras M9.8 governed readback BLOCKED, M9.10 IN_PROGRESS o no haya recibo verificado IG_CUTOVER_READINESS.',
 'HIGH',1,'IG_CURATOR_VALIDATOR_REFACTOR_V2',NULL,'ACTIVO',
 'supabase://programacion.fn_ig_m98_checkpoint_bound_readback_v2#BLOCKED_GOVERNED_EVIDENCE_BINDING_MISSING; PAULO-156 DONE',
 'VALIDATION',ARRAY['ENGINEERING_EXECUTOR','VALIDATOR']::text[],
 'R2_NO_VE','PROCESS_DEPENDENT','M9.12 preflight 2026-10-12 UTC',
 'programacion.fn_ig_m98_checkpoint_bound_readback_v2'),
 ('IG-M912-JSONB-MISSING-ACTION-SPEC-001','ENGINEERING_VALIDATION',
 'PREREQ_RECEIPTS no tiene action_specs_v1 local aunque su spec compila en READBACK_ONCE',
 'Un primer parche en ROLLBACK intentó modificar action_specs_v1.PREREQ_RECEIPTS como objeto local existente; JSONB NULL se propagó y el update falló NOT NULL antes de persistir. Se recuperó usando SOURCE_PACK y el compilador genérico, sin materializar acción local incompleta.',
 'Uso de jsonb_set con replacement NULL sobre path inexistente y suposición de action_spec local donde solo había fallback compilado.',
 'MISSING_LOCAL_SPEC_NULL_PROPAGATION',
 'Preflight verificar existencia del nodo jsonb y usar compiled spec/source_pack como autoridad; no emitir spec incompleto; exigencia NOT NULL de update sirve de fail-closed; probar transaccionalmente sin residuos.',
 'Prueba reversible final de contratos: 4 checkpoints pendientes, cero cambios en ledger, bootstrap WAIT_DEPENDENCIES, migraciones exactas Git en sandbox.',
 'MEDIUM',1,'IG_CURATOR_VALIDATOR_REFACTOR_V2',NULL,'VERIFICADO',
 'supabase://programacion.engineering_plan_units/M9.12; reversible SQL preflight NOT NULL blocked, no residue',
 'VALIDATION',ARRAY['ENGINEERING_EXECUTOR','GOVERNANCE']::text[],
 'R2_NO_VE','PROCESS_DEPENDENT','M9.12 contracts-only repair 2026-10-12 UTC',
 'programacion.engineering_plan_units M9.12 PREREQ_RECEIPTS');
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo IN
 ('IG-M912-POSTPASE-RECEIPT-SOURCE-DRIFT-001','IG-M912-M98-LIVE-READBACK-BLOCKED-001','IG-M912-JSONB-MISSING-ACTION-SPEC-001'))<>3
 THEN RAISE EXCEPTION 'M912_EKB_READBACK_NOT_THREE'; END IF;
END $ekb$;