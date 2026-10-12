-- M10.0 observed preflight defects: keep release and human authority fail-closed.
DO $e$
BEGIN
 IF EXISTS (SELECT 1 FROM public.lf_error_knowledge WHERE codigo IN (
 'IG-M100-INVALID-HUMAN-DECISION-LITERAL-001',
 'IG-M100-FROZEN-BUNDLE-IDENTITY-CONFLICT-001',
 'IG-M100-STALE-M90-M912-SOURCEPACK-001'))
 THEN RAISE EXCEPTION 'M100_EKB_PRESTATE_ALREADY_EXISTS'; END IF;
 INSERT INTO public.lf_error_knowledge
 (codigo,categoria,titulo,causa_raiz,prevencion,validacion,estado,evidencia,lote_origen,source_ref)
 VALUES
 ('IG-M100-INVALID-HUMAN-DECISION-LITERAL-001','GOVERNANCE',
 'M10.0 pedía CUTOVER_AUTHORIZED como valor inválido de human_decisions.decision',
 'Contrato de promoción copió un estado de negocio a columna limitada por CHECK a APPROVE/REJECT; además equiparaba Git head SHA40 con bundle SHA256.',
 'Usar decision=APPROVE, metadata.decision_class=CUTOVER_AUTHORIZED, metadatos de SHA256 congelado, head_sha Git SHA40 y recibo explícito authority_receipt_id; sin auto-aprobación ni activación.',
 'Contrato corregido, SQL exacto con BEGIN/ROLLBACK, bootstrap WAIT_DEPENDENCIES, cero filas human_decisions; no se simula decisión.',
 'VERIFICADO','supabase://programacion.human_decisions#decision_constraint=APPROVE_REJECT;M10.0',
 'IG_CURATOR_VALIDATOR_REFACTOR_V2','programacion.human_decisions'),
 ('IG-M100-FROZEN-BUNDLE-IDENTITY-CONFLICT-001','ENGINEERING_VALIDATION',
 'M9.0 reporta hash de manifiesto distinto del hash en el recibo congelado',
 'M9.0 BUNDLE_MANIFEST_SHA contiene bundle_sha256=1da225e9... y BUNDLE_READBACK ancla el recibo firmado 187 con SHA=db84f4ab...; el recibo 1068 posterior usa otro head. No hay prueba de equivalencia semántica entre estas identidades.',
 'Leer recibo firmado por ancla del checkpoint M9.0 y comparar definición/digest del manifiesto con evidencia; fail-closed sin seleccionar latest ni rearmar bundle ni autorizar release hasta reconciliación.',
 'Preflight: recibo 187 VERIFIED, SHA manifiesto textual distinto; binding no puede pasar aún. Reportar diferencia sin fingir que ambos identificadores son equivalentes.',
 'ACTIVO','supabase://programacion.engineering_work_checkpoints/M9.0/BUNDLE_MANIFEST_SHA+BUNDLE_READBACK;programacion.provenance_receipts/187',
 'IG_CURATOR_VALIDATOR_REFACTOR_V2','programacion.engineering_plan_units M9.0/M10.0'),
 ('IG-M100-STALE-M90-M912-SOURCEPACK-001','ENGINEERING_VALIDATION',
 'M10.0 source_pack arrastró M9.0 BACKLOG y fuente CUTOVER_READY equivocada',
 'Checkpoint M9.0 ya DONE con bundle firmado, pero BUNDLE_M9_BINDING decía no existe; CUTOVER_READY_PRECONDITION consultaba lf_qualification_receipts en vez de programacion.provenance_receipts y REUSE_SADM_AUTHORITY refería workstream externo desactivado.',
 'Reconciliar action_specs+SOURCE_PACK+gobernanza en un lote; fuentes exactas M9.0, M9.12 y registry transversal; sin depender de POST_PASE desactivado.',
 'SQL Git reversible: BUNDLE_M9_BINDING READY pero fail-closed por SHA, M9.12 sigue WAIT_DEPENDENCIES y no se crea recibo ni autorización.',
 'VERIFICADO','supabase://programacion.engineering_plan_units/M10.0;programacion.provenance_receipts',
 'IG_CURATOR_VALIDATOR_REFACTOR_V2','programacion.engineering_plan_units M10.0');
 IF (SELECT count(*) FROM public.lf_error_knowledge WHERE codigo LIKE 'IG-M100-%')<3
 THEN RAISE EXCEPTION 'M100_EKB_WRITES_MISSING'; END IF;
END $e$;