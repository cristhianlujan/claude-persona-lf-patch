-- LF PE10 — atomic implementation checkpoints for profile-repair operability.
-- PLAN REGISTRATION ONLY (8 units / 48 PENDING checkpoints; 16 dependencies).
-- Reuse existing PE0-PE10, PE10E, PE10P and PE10_E2 DONE receipts; do not rewrite closures.
-- No profile edits, Edge deployments, method promotion, activation or production cutover.
-- Canonical SQL transport: ACTUALIZACION_DB_LF -> LF Migration Merge Train, with post-merge readback.
BEGIN;
DO $lf_pe10_atomic$
DECLARE
  v_exec text;
  v_stream_id bigint;
  v_parent_id bigint;
  v_plan_event_id bigint;
  v_work_id bigint;
  v_wa bigint;
  v_wb bigint;
  v_n integer:=0;
  v_dep_n integer:=0;
  v_group jsonb;
  v_dep jsonb;
  v_meta jsonb;
  v_prefix text;
  v_groups jsonb:='[{"key":"CONTRACTS","unit":"PE10A_CONTRACTS","prefix":"PE10A_CT","title":"Auditoría atómica de contratos, firmas y compatibilidad","reuse":"PE0, PE5, PE5A, PE6; PE10_C5","deps":[],"checks":[["Inventariar firmas y propietarios canónicos de todas las superficies tocadas","Mapa exact-head de RPC SQL, Edge, Python, contratos, schemas, políticas y consumidores con firma entrada/salida","Una firma obsoleta o sin propietario falla y señala consumidor","PE0_C1, PE5_C1"],["Comparar firma declarada frente a invocaciones reales y tipos de retorno","Paridad de argumentos, tipos, errores y contratos en todos los llamadores involucrados","Firma o enum incompatible es rechazado antes de ejecutar","PE6_C2, PE10P_C1"],["Congelar contrato por ejecución y ruta de decisión","Snapshot v0.2 con UPDATE de 17, NO_CHANGE de 10 y NEEDS_MORE_EVIDENCE no terminal, ligado a ejecución","Rechazar ruta inferida por el modelo o snapshot mutable/obsoleto","PE5_C1, PE6_C2, PE10_C6"],["Homologar esquemas de salida y validadores realmente vinculados","Misma versión/sha de schema y validador perfil-local en generación, actualización y consumo","Ejemplo sin campo required o enum ilegal falla con evidencia","PE5A_C2, PE10P_C2"],["Verificar alcance y compatibilidad de los cambios en dependencias","Cambios en pasos, firmas, políticas, juicios, contratos y fuentes son declarados, delimitados, con consumidores identificados","Cambio que rompa v0.1 o afecte perfil ajeno bloquea","PE6_C4, PE5A_C4"],["Probar lectura actual vs artefactos/declaraciones antiguas","El consumidor resuelve autoridad actual y prohíbe rutas y firmas deprecated en el mismo run","Ref histórica sin admisión actual no produce PASS","PE0_C2, PE10_C5"]]},{"key":"JUDGES","unit":"PE10A_JUDGES","prefix":"PE10A_JD","title":"Auditoría de jueces, bindings y adjudicación independiente","reuse":"PE1B, PE6, PE10_C3","deps":["CONTRACTS"],"checks":[["Inventariar jueces y bindings por cada paso aplicable","Mapa de step_id a judge_code, versiones, estados, entrada, salida, evidencias y política active/candidate","Paso sin juez autorizado o juez de versión distinta bloquea","PE6_C2, PE10_C3"],["Probar mini-juez determinista antes de semántico","Cada resultado y transición se computa sobre evidencia estructural y códigos tipados","PASS declarado por caller sin verificación independiente es rechazado","PE1_C3, PE10P_C2"],["Probar juez semántico con salida funcional material","Calificación reproduce caso real con rubric y RAW vinculados a revisión exacta","Juez no califica documentos como ejecución real ni ignora ambigüedad","PE10E_C2, PE10_C2B"],["Acreditar juez independiente sin autocertificación","Revisor, proveedor, caso, sujeto, SHA y resultado verificables sin reutilizar autoría","Rechaza recibo inventado, caducado o del mismo autor como independiente","PE10_C3, PE10E_C4"],["Garantizar bloqueo, corrección y nueva revisión sin saltos","Caso positivo y negativo por resultado de juez; reintento conserva evidencia de fallo","Un BLOCKED o RETURN no deriva a close ni muta sin nueva verificación","PE6_C3, PE10_C6"]]},{"key":"PIPELINE","unit":"PE10A_PIPELINE","prefix":"PE10A_PL","title":"Pipeline secuencial dinámico y recuperación durable","reuse":"PE5, PE6, PE10_C6; ACT-0001","deps":["CONTRACTS","JUDGES"],"checks":[["Leer ruta inicial autorizada, sin resolver Router por segunda vez","Handoff mantiene negocio, canal, perfil reparador, sujeto, autoridad y versión del pedido","Rechaza reruteo directo del Updater como entrada alternativa no autorizada","PE5_C1, PE10P_C3"],["Calcular secuencia desde política vigente congelada","Muestra next_step desde autoridad, incluyendo bifurcación UPDATE/NO_CHANGE/NEEDS_MORE_EVIDENCE","Rechaza índice hardcodeado, paso omitido o flujo incompatible","PE5_C1, PE10_C6"],["Impedir ejecución fuera de orden, duplicados y replay","No se registra paso n+1 sin PASS limpio n; reintento idempotente y recibos exactos","Intentos de saltar a stage2, aplicar deprecated o duplicar write fallan","PE6_C3, PE10_C6"],["Conservar snapshot y cursor durable en cada transición","Readback de execution_id, policy SHA, decisión, checkpoint y siguiente acción después de reanudar","Cursor inconsistente u origen distinto bloquean en vez de avanzar","PE6_C1, PE10_C4"],["Componer dependencias y transportes existentes sin otra capa","El host usa RPC/runner/Train existentes de acuerdo a capacidad, sin cola polling ni adapter nuevo","Bifurcación hacia función privada o transporte no autorizado falla","PE10P_C3, PE10_C5"],["Recuperar interrupción, lease expirado y bloqueo corregible","Reanudación on-demand conserva idempotencia y ofrece reparación acotada o escalamiento explicable","Ninguna ejecución queda eternamente IN_PROGRESS/BLOCKED sin próxima acción y causa","PE6_C4, PE10_C4"]]},{"key":"METHODS","unit":"PE10A_METHODS","prefix":"PE10A_ME","title":"Selección dinámica y métodos de investigación interna y externa","reuse":"PE1B, PE2, PE2B, PE3, PE3B, PE7B, PE10_E2","deps":["PIPELINE"],"checks":[["Leer catálogo vigente y autoridad de calificación de métodos","Versión, origen, calificación y permisos del catálogo por run; métodos candidate != runtime qualified","Rechaza selección de método experimental/no cualificado aunque esté catalogado","PE2B_C1, PE2B_C2"],["Integrar selector dinámico en Updater con precondición/coste","Selecciona métodos elegibles por problema, presupuesto, riesgo y evidencias reales","Rechaza selección forzada, costo excedido o precondición UNKNOWN","PE3B_C1, PE3B_C2"],["Ejecutar investigación interna selectiva y trazable","Consulta EKB, Supabase, GitHub y dependencias hasta profundidad proporcional a hallazgos","Evidencia histórica, búsqueda textual o referencia sin ejecución no puede ser prueba de efecto","PE1_C3, PE7_C1"],["Ejecutar investigación externa bajo fuentes y permisos verificables","Fuente externa real con consulta, corte temporal, URL/identificador, fecha y lectura material; transporte autorizado","Fuente inventada, anacrónica, no leída o fuera de política no entra a conclusión","PE2B_C4, PE10_E2_C4"],["Contrastar hallazgos internos/externos sin perder causalidad","Distinguir declaración, función, consumidor, lectura, caso y observación; controversias quedan abiertas","La coincidencia léxica, ausencia de resultado o dato ambiguo no se convierte en certeza","PE10_E2_C1, PE10_E2_C2"],["Ejecutar métodos seleccionados mediante host gobernado","Método cualificado invocado realmente, con resultado y recibo sujeto+versión+ejecución; métodos vacíos justificados","No contabilizar método seleccionado como ejecutado ni fabricar evidencia native","PE3_C4, PE10P_C3"],["Replanificar o detener con progreso verificable y presupuesto","Ante bloqueo/meseta cambia estrategia una vez acotada y explica NEEDS_MORE_EVIDENCE / NO_CHANGE","No hay bucle indefinido, repetición de benchmarks ni autopromoción de aprendizaje","PE3B_C3, PE3B_C4"]]},{"key":"SUPABASE","unit":"PE10A_SUPABASE","prefix":"PE10A_SB","title":"Integridad de Supabase, registro y ensayo transaccional","reuse":"PE6, PE10_C4, PE10_C5, PE10_C6","deps":["CONTRACTS","JUDGES","PIPELINE"],"checks":[["Conciliar catálogo de operación, pasos, política y jueces","Conteos y versiones exactos v0.1/v0.2; bloqueos hasta cutover; binding y lifecycle coherentes","Ninguna doble ACTIVE, juez ausente o contrato CANDIDATE se interpreta operativo","PE6_C2, PE10_C7"],["Inspeccionar RPC, permisos, lector/recorder y event ledger","Signaturas de pg_proc, caller RLS/grants, eventos con sujeto/sha y recorder exactos","Acceso privado indebido o recibo solo textual no supera el gate","PE6_C3, PE10_C3"],["Materializar SQL de cambios y ensayar positivo/negativo/rollback","Migración versionada, prueba real DB de aceptación/rechazo y ROLLBACK cero residuos con eventos verificables","No se aplica SQL vía consola directa ni se afirma PASS desde test de fuente","PE10_C6"],["Auditar estado actual de ejecuciones y resolver obsoletos","IN_PROGRESS/BLOCKED con paso real/lease y próxima acción, sin cancelar automáticamente ejecuciones ajenas","Sin paso ni lease válido no puede declararse completado ni ocultarse","PE10_C4, PE6_C4"],["Conservar causalidad EKB/Supabase para nuevas reparaciones","EKB preflight del run, corrección, prevención y prueba ejecutada unidos a evidencia inmutable","Hallazgos sin prueba o repetidos no se convierten en reglas ejecutables","PE7B_C1, PE10_C5"]]},{"key":"GITHUB","unit":"PE10A_GITHUB","prefix":"PE10A_GH","title":"Paridad GitHub–Supabase y despliegue gobernado","reuse":"PE5A, PE6, PE10_C5, PE10_C6; PR #3133","deps":["SUPABASE"],"checks":[["Congelar GitHub main HEAD, archivos y transitivos de import","SHA exacto y manifiesto reproducible de fuentes perfil, scripts, Edge e imports","Un archivo requerido no incluido o ref mutable bloquea","PE5A_C4, PE10_C5"],["Comparar Edge deployed frente a fuentes y archivos GitHub","Hash bytes, versión, inventario de archivos y semántica de llamadas coinciden después de despliegue","La v35 desfasada o archivo required_profile_steps ausente da DRIFT, no APTO","PE10_C6"],["Validar GitHub PR, PASE y Merge Train sin bypass","Write guard preaprobado, CI exact-head verde, train autorizado, recibo de merge","Direct merge, PR sin PASE o aprobación de SHA anterior no habilitan","PE10P_C4, PE10_C5"],["Conciliar migraciones GitHub SQL con Supabase aplicadas","Cada SQL materializado con versión/cambio exacto y readback post-Train del objeto DB","Migration aplicada sin archivo, archivo no aplicado, o versión distinta bloquea","PE6_C3, PE10_C6"],["Ejecutar paridad post-despliegue para cada consumidor afectado","Lecturas vivas de RPC, Edge, caller, profile, imports y contratos coinciden en una revisión","Mismo nombre de endpoint o PR mergeado sin bytes coincidentes no es PASS","PE10_C6"],["Recuperar drift y rollback a última versión conocida buena","Plan de despliegue/rollback gobernado, readback sin residuos y propagación del incidente a EKB","No activa parcialmente ni cierra mientras origen y runtime difieran","PE5_C4, PE6_C4"]]},{"key":"REPAIR","unit":"PE10A_SRCR","prefix":"PE10A_SR","title":"Invocación gobernada desde el Perfil Reparador","reuse":"PE5, PE10P; Router ACT-0001, SRCR","deps":["PIPELINE","METHODS","GITHUB"],"checks":[["Resolver entrada Router→Perfil Reparador preservando la ruta","Recibo de canal/negocio/perfil, identidad y alcance verificables; reparador elegido","No se inicia Updater desde un bypass o reruteo fabricado","PE5_C1, ACT-0001"],["Diagnosticar causa y decidir si procede actualizar perfil","Evidencia causal+EKB clasifica cambio de perfil vs operación/DB/ruta ajena","No invoca Updater por problema externo no atribuible al perfil","PE1_C4, PE7B_C3"],["Crear handoff SRCR→Updater ligado a autoridad y ejecución","Exact target_code/path SHA, scope, caller autorizado, policy snapshot y misma correlación de incidente","No reinicia Router como si fuese nueva intención ni eleva permisos","PE10P_C3, PE10_C5"],["Ejecutar Updater por transporte canónico y devolver resultado","Recibo auténtico de entrada/salida por ejecución, paso y sujeto, retornado a SRCR","Una ejecución sin recibo ni próxima acción vuelve como bloqueo accionable","PE10P_C4, PE10_C6"],["Probar rechazo de cross-business y reparación no autorizada","LF/SALY, escritura GitHub, cambios SQL y efectos respetan permisos y frontera","Una ruta de negocio/acción equivocada falla sin efectos colaterales","PE5_C4, PE6_C4"]]},{"key":"READINESS","unit":"PE10A_READY","prefix":"PE10A_OP","title":"Aptitud operacional, reparación completa y salida útil","reuse":"PE0, PE1B, PE4, PE5A, PE10E, PE10_C6, PE10_C7","deps":["REPAIR","GITHUB","METHODS","SUPABASE"],"checks":[["Medir línea base operacional de perfil real antes del cambio","13 dimensiones S26 más contratos, firmas, validator y ejecución funcional del perfil de origen","No se sustituye ejecución real por completitud documental","PE0_C1, PE4_C3"],["Materializar y aplicar reparación de todas las superficies impactadas","Diff mínimo con dueño de cada cambio: SKILL, procedimientos, firmas, contratos, judges, schemas, imports y bindings","Falta de consumidor o cambio no declarado impide admisión","PE5A_C3, PE5A_C4"],["Validar artefactos y salidas positivas/negativas ejecutadas","S26 post 13/13 + validador perfil-local con ejemplo positivo y contraejemplo real","Un schema mismatch, error de transporte o salida falsa rechaza","PE1B_C3, PE10P_C2"],["Ejecutar tarea real del perfil reparado bajo host autorizado","E2E provider-bound para tarea representativa y holdout, sin saltos y sin regresión crítica","Una simulación, texto autocalificado o ejecución parcial no aprueba","PE10E_C1, PE10E_C4"],["Probar NO_CHANGE y NEEDS_MORE_EVIDENCE sin callejón sin salida","NO_CHANGE verificado sin write, evidencia faltante define adquisición/reanudación y punto exacto","Ningún terminal falso, write imprevisto o interrupción sin próxima acción","PE3B_C3, PE10_C6"],["Probar recuperación y autorreparación acotada conservando última versión útil","Falla detectada, máximo de intentos, rollback, idempotencia y readback sin residuos","Sin loop, avance ficticio o perfil parcialmente aplicado","PE5_C2, PE6_C4"],["Verificar paridad final de GitHub, Supabase y consumidores","Hashes actuales, funciones desplegadas, recibos PASE/Train y autoridad coincidentes","Drift vigente prohíbe APTO aunque el PR esté fusionado","PE10_C6, PE10_C7"],["Emitir aptitud final con recibo independiente y handback SRCR","APTO únicamente tras todos los gates; si no, diagnóstico causal y siguiente paso concreto","No proclamar v0.2 activa ni cerrar sin conformidad independiente","PE10_C3, PE10_C7"]]}]'::jsonb;
  v_dependencies jsonb:='[{"work":"PEVO-PE10A_JUDGES","requires":"PEVO-PE10A_CONTRACTS"},{"work":"PEVO-PE10A_PIPELINE","requires":"PEVO-PE10A_CONTRACTS"},{"work":"PEVO-PE10A_PIPELINE","requires":"PEVO-PE10A_JUDGES"},{"work":"PEVO-PE10A_METHODS","requires":"PEVO-PE10A_PIPELINE"},{"work":"PEVO-PE10A_SUPABASE","requires":"PEVO-PE10A_CONTRACTS"},{"work":"PEVO-PE10A_SUPABASE","requires":"PEVO-PE10A_JUDGES"},{"work":"PEVO-PE10A_SUPABASE","requires":"PEVO-PE10A_PIPELINE"},{"work":"PEVO-PE10A_GITHUB","requires":"PEVO-PE10A_SUPABASE"},{"work":"PEVO-PE10A_SRCR","requires":"PEVO-PE10A_PIPELINE"},{"work":"PEVO-PE10A_SRCR","requires":"PEVO-PE10A_METHODS"},{"work":"PEVO-PE10A_SRCR","requires":"PEVO-PE10A_GITHUB"},{"work":"PEVO-PE10A_READY","requires":"PEVO-PE10A_SRCR"},{"work":"PEVO-PE10A_READY","requires":"PEVO-PE10A_GITHUB"},{"work":"PEVO-PE10A_READY","requires":"PEVO-PE10A_METHODS"},{"work":"PEVO-PE10A_READY","requires":"PEVO-PE10A_SUPABASE"},{"work":"PEVO-PE10","requires":"PEVO-PE10A_READY"}]'::jsonb;
BEGIN
  SELECT execution_id INTO v_exec FROM public.lf_operation_execution
  WHERE operation_code='ACTUALIZACION_DB_LF'
    AND target_type='MIGRATION'
    AND target_code LIKE '%lf_pe10_operability_atomic_plan_v1'
    AND status='IN_PROGRESS'
  ORDER BY created_at DESC LIMIT 1;
  IF v_exec IS NULL THEN RAISE EXCEPTION 'PE10_ATOMIC_PLAN_TRAIN_BINDING_REQUIRED'; END IF;

  SELECT id INTO STRICT v_stream_id FROM programacion.engineering_workstreams
  WHERE stream_code='PROFILE_UPDATER_EVOLUTION_V1' AND status='ACTIVE';
  SELECT id INTO STRICT v_parent_id FROM programacion.engineering_work_items
  WHERE work_code='PEVO-PE10' AND workstream_id=v_stream_id AND status='IN_PROGRESS';
  SELECT plan_event_id INTO STRICT v_plan_event_id FROM programacion.engineering_plan_units
  WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' AND unit_code='PE10'
    AND work_item_id=v_parent_id AND disposition='ASSIGNED';

  IF (SELECT count(*) FROM programacion.engineering_plan_units WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1')<>19
    OR (SELECT count(*) FROM programacion.engineering_work_checkpoints c
         JOIN programacion.engineering_plan_units u ON u.work_item_id=c.work_item_id
         WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1')<>84
    OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
         WHERE work_item_id=v_parent_id AND checkpoint_code IN ('PE10_C6','PE10_C7') AND status='PENDING')<>2
    OR EXISTS (SELECT 1 FROM programacion.engineering_work_items WHERE work_code LIKE 'PEVO-PE10A_%')
    OR EXISTS (SELECT 1 FROM programacion.engineering_plan_units
               WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1' AND unit_code LIKE 'PE10A_%')
  THEN RAISE EXCEPTION 'PE10_ATOMIC_PLAN_PRESTATE_CHANGED_OR_ALREADY_PRESENT'; END IF;

  FOR v_group IN SELECT value FROM jsonb_array_elements(v_groups)
  LOOP
    v_prefix:=v_group->>'prefix';
    IF jsonb_array_length(v_group->'checks')<5
      THEN RAISE EXCEPTION 'PE10_ATOMIC_UNIT_TOO_COARSE_%',v_group->>'key'; END IF;
    INSERT INTO programacion.engineering_work_items
     (work_code,workstream_id,parent_work_item_id,title,objective,expected_result,
      work_type,priority,status,assignee_type,assignee_ref,target_repo,
      target_domain,target_component,source_ref,acceptance_criteria,created_by_execution_id)
    VALUES
     ('PEVO-'||(v_group->>'unit'),v_stream_id,v_parent_id,v_group->>'title',
      'Verify and complete evidence-bound ' || (v_group->>'title'),
      'Each atomic checkpoint has actual source/readback, positive and negative observation, qualified independent receipt; never self-attest completion',
      'QA','P1','BACKLOG','AGENT','PROFILE_EVOLUTION_ORCHESTRATOR',
      'cristhianlujan/claude-persona-lf-patch','LF_PE10',v_group->>'unit',
      'supabase://programacion.engineering_plan_units/PE10',
      jsonb_build_array('Keep previously DONE PE checkpoints immutable',
         'One material verified positive and one negative per atomic checkpoint',
         'One qualified provider/evidence receipt bound to the exact subject and SHA',
         'No runtime activation, direct SQL or direct merge by plan registration',
         'No new adapters, queues or extra profile-updater engine'),
      v_exec)
    RETURNING id INTO v_work_id;

    INSERT INTO programacion.engineering_work_checkpoints
     (work_item_id,checkpoint_code,title,sequence_no,weight,required,status,created_by_execution_id)
    SELECT v_work_id, v_prefix||lpad(ord::text,2,'0'), item->>0,
           ord::integer,1,true,'PENDING',v_exec
    FROM jsonb_array_elements(v_group->'checks') WITH ORDINALITY AS e(item,ord);
    GET DIAGNOSTICS v_n=ROW_COUNT;
    IF v_n<>jsonb_array_length(v_group->'checks')
      THEN RAISE EXCEPTION 'PE10_ATOMIC_CHECKPOINT_INSERT_MISMATCH_%',v_group->>'unit'; END IF;

    SELECT jsonb_build_object(
      'schema','PE10_ATOMIC_OPERABILITY_PLAN_V1',
      'scope','PLAN_ONLY_NO_EXECUTION_OR_CUTOVER',
      'reuses_completed_checkpoints',v_group->>'reuse',
      'required_units_before',v_group->'deps',
      'existing_approvals_immutable',true,
      'unit_checksum_policy','EXACT_CURRENT_SOURCE_AND_PROVIDER_RECEIPT',
      'checkpoint_ordering',(
        SELECT jsonb_agg(v_prefix||lpad(ord::text,2,'0') ORDER BY ord)
        FROM jsonb_array_elements(v_group->'checks') WITH ORDINALITY AS e(item,ord)),
      'checkpoint_inputs',(
        SELECT jsonb_object_agg(v_prefix||lpad(ord::text,2,'0'),
         jsonb_build_object('purpose',item->>0,'positive_evidence_required',item->>1,
           'negative_evidence_required',item->>2,'prior_work_reused',item->>3,
           'evidence_mode','REAL_PROVIDER_BOUND_READBACK',
           'source_currentness','EXACT_CURRENT_SHA',
           'no_unqualified_claims',true))
        FROM jsonb_array_elements(v_group->'checks') WITH ORDINALITY AS e(item,ord)),
      'action_specs_v1',(
        SELECT jsonb_object_agg(v_prefix||lpad(ord::text,2,'0'),
         jsonb_build_object('status','BLOCK_PENDING_IMPLEMENTATION_AND_INDEPENDENT_RECEIPT',
           'action_kind','GOVERNED_MATERIAL_VERIFICATION',
           'recipe_mode','EVIDENCE_FIRST',
           'requires_material_execution',true,
           'positive_test',item->>1,'negative_test',item->>2,
           'validator_contract_status','EXACT_EXISTING_VALIDATOR_TO_BE_BOUND_PER_CHECKPOINT',
           'closure_route','AUTHORIZED_OPERATION_THEN_TRAIN_AND_POST_READBACK',
           'forbidden',jsonb_build_array('CLAIM_PASS_WITHOUT_EXECUTION',
             'REUSE_STALE_OR_UNSCOPED_RECEIPT','AUTO_ACTIVATE_V02',
             'BYPASS_ROUTER_SRCR_OR_GOVERNED_TRANSPORT')))
        FROM jsonb_array_elements(v_group->'checks') WITH ORDINALITY AS e(item,ord))
      ) INTO v_meta;

    INSERT INTO programacion.engineering_plan_units
     (plan_code,unit_code,unit_class,lot_code,lot_from,lot_to,title,exit_criterion,
      plan_event_id,work_item_id,created_by_execution_id,unit_metadata)
    VALUES ('PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1',
       v_group->>'unit','EXECUTION','E10_ATOMIC_'||(v_group->>'key'),10,10,
       v_group->>'title',
       'All atomic checkpoints proven with exact current provider-bound evidence and negative counterexamples; integrated operability, no premature activation',
       v_plan_event_id,v_work_id,v_exec,v_meta);
  END LOOP;

  FOR v_dep IN SELECT value FROM jsonb_array_elements(v_dependencies)
  LOOP
    SELECT id INTO STRICT v_wa FROM programacion.engineering_work_items
      WHERE work_code=v_dep->>'work' AND workstream_id=v_stream_id;
    SELECT id INTO STRICT v_wb FROM programacion.engineering_work_items
      WHERE work_code=v_dep->>'requires' AND workstream_id=v_stream_id;
    INSERT INTO programacion.engineering_work_dependencies
      (work_item_id,depends_on_work_item_id,relation_type,created_by_execution_id)
    VALUES (v_wa,v_wb,'REQUIRES',v_exec);
    v_dep_n:=v_dep_n+1;
  END LOOP;

  IF (SELECT count(*) FROM programacion.engineering_plan_units
      WHERE plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1')<>27
    OR (SELECT count(*) FROM programacion.engineering_work_checkpoints c
      JOIN programacion.engineering_plan_units u ON c.work_item_id=u.work_item_id
      WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1')<>132
    OR (SELECT count(*) FROM programacion.engineering_work_checkpoints c
      JOIN programacion.engineering_plan_units u ON c.work_item_id=u.work_item_id
      WHERE u.plan_code='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1'
        AND u.unit_code LIKE 'PE10A_%' AND c.status='PENDING'
        AND c.evidence_ref IS NULL AND c.assertion_receipt IS NULL)<>48
    OR v_dep_n<>16
    OR (SELECT count(*) FROM programacion.engineering_work_checkpoints
       WHERE work_item_id=v_parent_id AND checkpoint_code IN ('PE10_C6','PE10_C7')
          AND status='PENDING')<>2
    OR (SELECT version FROM public.lf_operation_registry
      WHERE operation_code='ACTUALIZACION_PERFIL_LF')<>'v0.1'
  THEN RAISE EXCEPTION 'PE10_ATOMIC_POST_REGISTER_READBACK_FAILED'; END IF;
END $lf_pe10_atomic$;
COMMIT;
