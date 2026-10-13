-- EKB append-only lessons from M10.0 engineering CP2/CP3. No promotion authority.
INSERT INTO transversal.error_knowledge
(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,
 severidad,lote_origen,pr,estado,evidencia,lifecycle_phase,root_cause_family,
 detectability,source_context,source_ref)
SELECT e.*
FROM (VALUES
(
 'IG-M100-LEGACY-JUDGE-VS-PINNED-RECEIPT-001',
 'INPUT_GOVERNANCE',
 'La prueba previa de M9.0 no equivale a la identidad firmada del release',
 'M9.0 BUNDLE_MANIFEST_SHA registró 1da225e9; BUNDLE_READBACK fija recibo 187 con db84f4ab. Los dos hechos permanecen conservados y NO se declaran equivalentes. M9.12 recibo 1667 firmado coincide exactamente con 187.',
 'El contrato de M10.0 exigía comparar un digest del test histórico pre-freeze con el recibo final; confundía evidencia de juez con autoridad de un snapshot firmado. Además fn_input_governance_release_bundle_manifest_v1 consulta objetos DB vivos.',
 'GIT_HEAD_SAME_BUT_DB_MANIFEST_MUTABLE; HISTORICAL_JUDGE_DIGEST_NOT_SIGNED_RELEASE_ID',
 'En binding de ingeniería seleccionar por checkpoint DONE M9.0/BUNDLE_READBACK su receipt_id explícito, no latest ni rebuilt; recomputar identidades SHA y 7 digests desde snapshot firmado; mantener diferencia del test histórico visible; exigir currentness y autorización humana separados antes de promoción.',
 '2026-10-12: readback receipt 187 VERIFIED EVIDENCE_VERIFIER_V1, head SHA40 y bundle SHA256 consistentes; 7/7 componentes internos, negativo registry tamper falla, prueba histórica diversa preservada; M9.12 #1667 coincide; PR2309 merged main=201356e57398747849a280dc88807365a508cf87, migración aplicada, CP2 DONE, ledger 35%. No prueba de producción.',
 'HIGH','M10.0','#2309','VERIFICADO',
 'github://cristhianlujan/claude-persona-lf-patch/pull/2309;supabase://programacion.provenance_receipts/187;supabase://programacion.provenance_receipts/1667',
 'ENGINEERING_BINDING','R4_NO_CUESTIONA','PROCESS_DEPENDENT',
 'IG_CURATOR_VALIDATOR_REFACTOR_V2',
 'supabase://programacion.engineering_work_checkpoints/M10.0/BUNDLE_M9_BINDING'
),
(
 'IG-M100-UPSTREAM-RECEIPT-GATE-STALE-001',
 'INPUT_GOVERNANCE',
 'Checkpoint M10.0 continuaba bloqueado tras cerrar M9.12',
 'CUTOVER_READY_PRECONDITION declaraba BLOCK_UPSTREAM_RECEIPT_PENDING aunque M9.12 ya estaba DONE y CUTOVER_READY firmado existía en receipt 1667. Status y action_spec no se reconciliaron tras la transición aguas arriba.',
 'Se trató un estado de fuente anterior como contrato vigente; además la consulta ordenaba por latest en lugar del checkpoint canónico con recibo fijado.',
 'STALE_STATIC_UPSTREAM_BLOCK_WITH_SIGNED_RECEIPT_PRESENT',
 'Al terminar dependencia volver a compilar estado del checkpoint con recibo por ID anclado en CUTOVER_READY_READBACK, comprobando issuer, verification_status, estado de readiness y coincidencia head_sha+bundle_sha256 con recibo M9.0. Actualizar action_spec+source_pack+gobernanza en conjunto. Nunca simular human_decisions.',
 '2026-10-12: M9.12 receipt 1667 VERIFIED CUTOVER_READY EVIDENCE_VERIFIER_V1, misma identidad M9.0 receipt 187; PR2310 merged main=de7465e280a1291471e05565ed4de8f691271914, migración aplicada; bootstrap CONTINUE_CURRENT_CHECKPOINT; CP3 DONE, ledger 50%, CP4 capacidad 3/3 PASS y 60%. Decisión humana sigue ausente.',
 'HIGH','M10.0','#2310','VERIFICADO',
 'github://cristhianlujan/claude-persona-lf-patch/pull/2310;supabase://programacion.provenance_receipts/1667;supabase://programacion.provenance_receipts/187',
 'ENGINEERING_READBACK','R5_EROSION_PROCESO','PROCESS_DEPENDENT',
 'IG_CURATOR_VALIDATOR_REFACTOR_V2',
 'supabase://programacion.engineering_work_checkpoints/M10.0/CUTOVER_READY_PRECONDITION'
)
) AS e(codigo,categoria,titulo,descripcion,causa_raiz,patron,prevencion,validacion,severidad,lote_origen,pr,estado,evidencia,lifecycle_phase,root_cause_family,detectability,source_context,source_ref)
WHERE NOT EXISTS (SELECT 1 FROM transversal.error_knowledge k WHERE k.codigo=e.codigo);