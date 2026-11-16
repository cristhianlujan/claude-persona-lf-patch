-- LF B2B-CARGA-002: reconciliación documental de tres reglas y un vínculo.
-- Análisis fuente: EXEC-PROFILE-GATE2-808379962BF5ACA150004167 (11/11 COMPLETED).
-- Reparador: EXEC-PROFILE-GATE2-4E7A86DAECA05A09424BA1D1; la selección no concede efecto.
-- Aplicación exclusiva por ACTUALIZACION_DB_LF / LF Migration Merge Train.
-- Preserva estado, valor_config, permisos, transiciones y todos los demás campos.
-- Snapshot actual: regla 581 VIGENTE; reglas 617 y 620 CANDIDATO.
-- Una única sentencia DO garantiza atomicidad incluso sin transacción del caller.
DO $lf_b2b_documentary_reconcile$
DECLARE
  v_patch constant jsonb := $lf_patch${"schema_version":"LF_B2B_CARGA002_DOCUMENTARY_PATCH_V1","source_analysis_execution":"EXEC-PROFILE-GATE2-808379962BF5ACA150004167","repair_execution":"EXEC-PROFILE-GATE2-4E7A86DAECA05A09424BA1D1","source_main":"0780a690ead97cb11df259b16888c37344c67d67","rules":[{"id":581,"code":"B2B-RULE-LOAD-WIZARD-001","state":"VIGENTE","before_sha256":"5683d2c599169bddcd85794e27bf770035014eca38815aa1849bcc1016a80c9d","protected_sha256":"47c0e8ce23813d65948433d8b28125efa9b70e170af55155aee8de769f1a2f4f","after_description":"\nB2B-CARGA-002 organiza la preparación de cartera en tres pasos UI: seleccionar tipo y formato, subir y preparar datos, y validar con resultado. «Cartera preparada» no constituye un cuarto paso UI ni afirma procesamiento definitivo: el resultado del paso 3 conserva la transición de dominio a B2B_LOAD_VALIDADO y ofrece salida a detalle o historial. La carga requiere el formato LF de la modalidad y no admite estructuras arbitrarias de la empresa ni un paso de mapeo de columnas. En Cuotas, el sistema autodetecta EXCEL_COMPLETO o EXCEL_ASISTIDO mediante el contrato versionado; no solicita una selección explícita de canal. Los estados UI no sustituyen estados de UPLOAD_BATCH; las mutaciones siguen gobernadas por lf_ops.estados_transiciones.\n","after_pending":"Pago único cerrado funcional y visualmente. Cuotas opera con EXCEL_COMPLETO o EXCEL_ASISTIDO autodetectados por contrato versionado, sin selección explícita de canal. La evidencia visual anterior Asistente LF recomendado + Excel alternativo está deprecada y requiere una nueva exploración UX. La base temporal de deuda, conciliación exacta y generación gobernada de fechas ya tienen semántica funcional registrada; su mapeo físico, PLAN_ID y configuración empresarial continúan según sus reglas específicas. La activación de planes sin cuota 0 activa permanece PENDING_FUNCTIONAL_DEFINITION. Mapping físico/versionado de B2B_FLD_PROCESSING_SCOPE continúa pendiente de implementación."},{"id":617,"code":"B2B-RULE-INSTALLMENT-PLAN-001","state":"CANDIDATO","before_sha256":"88f68b707b19ec18cd12146426141ddaca7473324c4962547c79bbf5aec160a3","protected_sha256":"aa9c6cc4003b65383a67332f7d602126a96eef8b272538d736a1a849fa1d43f7","after_description":"Cada alternativa de cuotas de una oferta tiene identidad propia. El pago inicial o cuota 0 pertenece al plan y no forma parte del cronograma regular; la cuota 1 es la primera cuota posterior. En Cuotas, offer_amount representa el monto económico total acordado del plan y debe cumplirse exactamente pago inicial + suma del cronograma regular = offer_amount, a 2 decimales. En el Excel Completo estándar V4, la empresa aporta la numeración y los montos del cronograma, que LF preserva y valida sin corrección silenciosa. El estándar no recibe fechas absolutas de vencimiento: LF calcula las fechas regulares server-side desde la configuración gobernada después de PAYMENT_CONFIRMED de una cuota 0 activa y las congela en el snapshot contractual. Esta regla no autoriza inferir la activación de planes sin cuota 0 activa. Cuando LF lo genera mediante Asistente, el residuo de división se absorbe exclusivamente en la última cuota. La cantidad de cuotas elegibles se gobierna por configuración de empresa: el límite base es hasta 12 cuotas, pero cada empresa puede habilitar un conjunto discreto como 1, 3, 6 y 12, o todas las cantidades de 1 a 12. La configuración de empresa puede ampliar el máximo por encima de 12 cuando esté autorizada. El Excel Completo no define libremente un plazo fuera de esa configuración: el número efectivo de cuotas se deriva del cronograma detallado y se valida contra el conjunto habilitado para la empresa. El Asistente LF solo puede proponer cantidades habilitadas por esa misma configuración. El mapeo físico de PLAN_ID y de la configuración empresarial de plazos permanece pendiente. La ventana mínima entre la activación del plan mediante pago confirmado de la cuota 0 y la primera cuota regular no se hardcodea en LF ni en el Excel: la define la empresa mediante configuración gobernada. LF calcula server-side la primera fecha de pago permitida que satisfaga esa ventana; si la próxima fecha permitida queda demasiado cerca, usa el siguiente ciclo permitido. Antes del pago el cronograma es propuesto; después de PAYMENT_CONFIRMED las fechas definitivas se congelan en el snapshot contractual. Aclaración del propietario 2026-10-15: cada alternativa de plan tiene su propia oferta económica y su monto específico. La referencia contenedora o su identificador de oferta vigente NO autoriza agregar los importes de planes alternativos; para descuentos conjuntos solamente se consideran las ofertas económicas seleccionadas y validadas server-side. La identidad física oferta-versión-plan y su cardinalidad final quedan pendientes del modelado y de reconciliar el contrato Cliente sin alterar sus reglas vigentes. Cuota 0 puede venir en el cronograma durante la carga, pero no es obligatoria; solo constituye un pago inicial activo si su monto supera el umbral parametrizado (hoy mayor que 1 en la moneda del plan). Cero no se considera pago inicial activo; para valores iguales o menores al umbral no se inicia cobro de cuota 0. La activación de planes sin cuota 0 activa queda PENDING_FUNCTIONAL_DEFINITION y nunca se presume automática. Fechas y ventanas actuales son sugerencias de diseño; faltan el modelo físico y sus relaciones con oferta, plan, cobro, calendario, ledger y snapshot; no fijar fechas definitivas ni constantes de frontend.","after_pending":"GOVERNED_CANDIDATE_REQUIRES_REVIEW"},{"id":620,"code":"B2B-RULE-INSTALLMENT-ASSISTED-LOAD-001","state":"CANDIDATO","before_sha256":"b8875ace62fa3fbadf29ad8ea4ab2015be0e88251db22bf35a836ba416a792e7","protected_sha256":"282b87f071e7957b581b3bd6dbb885086b125337778b8eec67cda5394501e1be","after_description":"En modalidad Cuotas, ambos caminos parten de un archivo Excel y LF admite únicamente dos contratos versionados y estrictos. EXCEL_ASISTIDO contiene la base común de deuda y sus fechas temporales obligatorias; si cumple exactamente ese contrato, entra al Asistente LF para completar oferta, plan y cronograma. EXCEL_COMPLETO contiene esa misma base más la oferta y el cronograma detallado requerido; si cumple exactamente ese contrato, pasa a validación. No existe un tercer contrato ni combinaciones intermedias. En el EXCEL_COMPLETO estándar V4, el cronograma detallado es la autoridad para la numeración y los montos de las cuotas: CRONOGRAMA contiene REFERENCIA_EMPRESA, PLAN, CUOTA y MONTO. REFERENCIA_EMPRESA + PLAN solo relaciona las hojas del archivo; LF genera las identidades internas. El estándar no recibe fechas absolutas de vencimiento ni IDs externos de oferta o cuota. Las fechas regulares se calculan server-side mediante configuración gobernada después de PAYMENT_CONFIRMED de una cuota 0 activa y se congelan en el snapshot contractual; la activación sin cuota 0 activa permanece PENDING_FUNCTIONAL_DEFINITION conforme B2B-RULE-INSTALLMENT-PLAN-001. B2B_IMP_INSTALLMENT_AMOUNT no es una fuente autoritativa frente a B2B_IMP_SCHEDULE_AMOUNT. LF no corrige silenciosamente el cronograma externo. Los campos físicos de fecha_inicio_mora y fecha_corte_cartera, y el mapeo físico de PLAN_ID, siguen pendientes de materialización gobernada; su semántica funcional ya está definida.","after_pending":"GOVERNED_CANDIDATE_REQUIRES_REVIEW"}],"relation":{"id":9492,"rule_id":581,"screen_id":44,"before":"Flujo de preparación UI aprobado en cuatro estados condicionales. Los estados visuales no equivalen a estados UPLOAD_BATCH; toda mutación debe resolver contra lf_ops.estados_transiciones.","after":"Flujo de preparación UI aprobado en tres pasos: tipo y formato, subir y preparar datos, y validar con resultado. Los estados visuales no equivalen a estados UPLOAD_BATCH; toda mutación debe resolver contra lf_ops.estados_transiciones. Cuotas autodetecta los dos contratos Excel versionados, sin selección explícita de canal."}}$lf_patch$::jsonb;
  v_item jsonb;
  v_row lf_ops.reglas%ROWTYPE;
  v_before jsonb;
  v_protected text;
  v_count integer;
  v_relation lf_ops.reglas_pantallas%ROWTYPE;
  v_relation_before jsonb;
BEGIN
  -- La migración no puede operar con un execution_id inventado por el caller.
  SELECT count(*) INTO v_count
  FROM public.lf_operation_execution e
  JOIN public.lf_operation_execution_steps s USING (execution_id)
  WHERE e.operation_code='ACTUALIZACION_DB_LF'
    AND e.target_type='MIGRATION'
    AND e.target_code ~ '^20[0-9]{12}_lf_b2b_carga002_documentary_reconcile_v1$'
    AND e.target_path='supabase/migrations/'||e.target_code||'.sql'
    AND e.target_repo='cristhianlujan/claude-persona-lf-patch'
    AND e.status='IN_PROGRESS'
    AND e.manifest->>'producer'='lf-migration-merge-train'
    AND e.manifest#>>'{router_authority_receipt,schema_version}'='LF_ROUTER_DOWNSTREAM_AUTHORITY_RECEIPT_V1'
    AND e.manifest#>>'{router_authority_receipt,operation_code}'='ACTUALIZACION_DB_LF'
    AND e.manifest#>>'{router_authority_receipt,target_code}'=e.target_code
    AND s.step_id='preflight' AND s.status='PASS_CLEAN'
    AND s.evidence_payload->>'producer'='lf-migration-merge-train'
    AND s.evidence_payload#>>'{exact_target,target_path}'=e.target_path
    AND s.evidence_payload#>>'{trust_validation,valid}'='true';
  IF v_count<>1 THEN
    RAISE EXCEPTION 'LF_B2B_DOC_TRAIN_AUTHORITY_NOT_BOUND:%',v_count;
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(v_patch->'rules')
                ORDER BY (value->>'id')::integer LOOP
    SELECT * INTO v_row FROM lf_ops.reglas
      WHERE id=(v_item->>'id')::integer AND codigo=v_item->>'code' FOR UPDATE;
    IF NOT FOUND OR v_row.estado IS DISTINCT FROM v_item->>'state' THEN
      RAISE EXCEPTION 'LF_B2B_DOC_IDENTITY_OR_STATE_DRIFT:%',v_item->>'code';
    END IF;
    v_before:=to_jsonb(v_row);
    v_protected:=encode(extensions.digest(convert_to(
      (v_before-'descripcion'-'pendiente_detalle'-'updated_at')::text,'UTF8'),'sha256'),'hex');
    IF v_protected IS DISTINCT FROM v_item->>'protected_sha256' THEN
      RAISE EXCEPTION 'LF_B2B_DOC_PROTECTED_SOURCE_DRIFT:%',v_item->>'code';
    END IF;
    -- Replay idéntico: no vuelve a escribir updated_at ni crea otro efecto.
    IF v_row.descripcion IS NOT DISTINCT FROM v_item->>'after_description'
       AND v_row.pendiente_detalle IS NOT DISTINCT FROM v_item->>'after_pending' THEN
      CONTINUE;
    END IF;
    IF encode(extensions.digest(convert_to(v_before::text,'UTF8'),'sha256'),'hex')
       IS DISTINCT FROM v_item->>'before_sha256' THEN
      RAISE EXCEPTION 'LF_B2B_DOC_PREIMAGE_DRIFT:%',v_item->>'code';
    END IF;
    UPDATE lf_ops.reglas SET
      descripcion=v_item->>'after_description',
      pendiente_detalle=v_item->>'after_pending',updated_at=clock_timestamp()
    WHERE id=v_row.id AND codigo=v_row.codigo;
    GET DIAGNOSTICS v_count=ROW_COUNT;
    IF v_count<>1 THEN RAISE EXCEPTION 'LF_B2B_DOC_WRITE_CARDINALITY'; END IF;
    SELECT * INTO STRICT v_row FROM lf_ops.reglas WHERE id=v_row.id;
    IF v_row.descripcion IS DISTINCT FROM v_item->>'after_description'
       OR v_row.pendiente_detalle IS DISTINCT FROM v_item->>'after_pending'
       OR (to_jsonb(v_row)-'descripcion'-'pendiente_detalle'-'updated_at')
          IS DISTINCT FROM (v_before-'descripcion'-'pendiente_detalle'-'updated_at') THEN
      RAISE EXCEPTION 'LF_B2B_DOC_RULE_READBACK_FAILED:%',v_item->>'code';
    END IF;
  END LOOP;

  SELECT * INTO v_relation FROM lf_ops.reglas_pantallas
    WHERE id=(v_patch#>>'{relation,id}')::integer
      AND regla_id=(v_patch#>>'{relation,rule_id}')::integer
      AND pantalla_id=(v_patch#>>'{relation,screen_id}')::integer FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'LF_B2B_DOC_RELATION_IDENTITY_DRIFT'; END IF;
  v_relation_before:=to_jsonb(v_relation);
  IF v_relation.nota IS DISTINCT FROM v_patch#>>'{relation,after}' THEN
    IF v_relation.nota IS DISTINCT FROM v_patch#>>'{relation,before}' THEN
      RAISE EXCEPTION 'LF_B2B_DOC_RELATION_PREIMAGE_DRIFT';
    END IF;
    UPDATE lf_ops.reglas_pantallas SET nota=v_patch#>>'{relation,after}'
      WHERE id=v_relation.id;
    GET DIAGNOSTICS v_count=ROW_COUNT;
    IF v_count<>1 THEN RAISE EXCEPTION 'LF_B2B_DOC_RELATION_WRITE_CARDINALITY'; END IF;
  END IF;
  SELECT * INTO STRICT v_relation FROM lf_ops.reglas_pantallas
    WHERE id=(v_patch#>>'{relation,id}')::integer;
  IF v_relation.nota IS DISTINCT FROM v_patch#>>'{relation,after}'
     OR (to_jsonb(v_relation)-'nota') IS DISTINCT FROM (v_relation_before-'nota') THEN
    RAISE EXCEPTION 'LF_B2B_DOC_RELATION_READBACK_FAILED';
  END IF;
END
$lf_b2b_documentary_reconcile$;
