-- PE10 IG Reparador A/B: governed PREPARATION-only native chat handoffs (13 stages).
-- Prior PE10 precedent: 20261015001500_lf_pe10_c3_chrome_browser_handoffs_v1.sql.
-- Router ACT-0001 -> ACTUALIZACION_DB_LF -> MIGRATION_VIA_MERGE_TRAIN.
-- Append-only data events, NO execution claims, no checkpoints, no production/runtime, no agent provisioning.
BEGIN;
DO $pe10_ig_ab_handoff$
DECLARE
  v_rows jsonb := $stage_packets$[{"task_code":"COORDINATOR","step_order":0,"role":"CLAUDE_COORDINATOR","dependencies":[],"instructions_for_gpt":"CLAUDE: coordina este piloto sin sustituir a GPT Native. Lee el caso P0 y las instrucciones operativas. Verifica acceso real a Chrome/Claude-in-Chrome y Supabase READ_ONLY; si no existe no inventes sesiones ni RAW. Ejecuta etapas en orden por dependencies. Abre chats independientes de GPT para brazo A, 5 especialistas de B, integrador B, crítico B y juez. No compartas A con B ni el holdout con productores. Cada etapa deja RAW y hash en evento nuevo por Operation/Migration→Train, no SQL Editor. Si no hay vía autorizada, conserva fuente RAW con hash y registra bloqueo real; continúa trabajo seguro. Reporta por paso execution_id, event ID y pruebas; no marques DONE por solo preparar eventos.","source_doc":"docs/profile_updater/experiments/pe10_ig_reparador_ab_20261017/P0_CASE_AND_PROTOCOL.md","judge_doc":null},{"task_code":"FREEZE","step_order":1,"role":"CLAUDE_COORDINATOR","dependencies":["COORDINATOR"],"instructions_for_gpt":"Congela byte a byte P0_CASE_AND_PROTOCOL.md, el inventario exacto del evento 20161 y los dos EKB anteriores al corte 2026-10-15T00:00Z; registra SHA256 y fuente/hora. Verifica que todos los productores reciben exactamente el mismo paquete. Evita lectura posterior de main como sistema histórico. No entregar JUDGE_ONLY.md a productores. Registra recibo PREPARED_TO_RUN, sin declarar captura de GPT.","source_doc":"docs/profile_updater/experiments/pe10_ig_reparador_ab_20261017/P0_CASE_AND_PROTOCOL.md","judge_doc":null},{"task_code":"A_PRODUCER","step_order":2,"role":"GPT_NATIVE_SINGLE","dependencies":["FREEZE"],"instructions_for_gpt":"En CHAT NUEVO GPT Native aislado: actúa como Reparador LF V0.7R1 individual usando método dinámico + razonamiento causal y estadística. Lee SOLO P0_CASE_AND_PROTOCOL.md y fuentes P0, no informes posteriores ni outputs B/juez. Produce JSON contractual íntegro; clasifica hechos/hypotheses/unknowns, propone reparación/falsificador y registra RAW exacto, SHA, URL y tiempos medidos. No actualices runtime.","source_doc":"docs/profile_updater/experiments/pe10_ig_reparador_ab_20261017/P0_CASE_AND_PROTOCOL.md","judge_doc":null},{"task_code":"B_ARCH","step_order":3,"role":"GPT_NATIVE_SPECIALIST","dependencies":["FREEZE"],"instructions_for_gpt":"En CHAT NUEVO GPT Native aislado, investiga SOLO desde P0 arquitectura/cableado: grafo SQL y Edge, callers directos/transitivos, clasificación legacy, caminos alternativos y dependencias. No ver brazo A/otros B/holdout. Devuelve finding/evidence_or_unknown/falsifier/consequence/cross_role_dependency; captura RAW.","source_doc":"docs/profile_updater/experiments/pe10_ig_reparador_ab_20261017/P0_CASE_AND_PROTOCOL.md","judge_doc":null},{"task_code":"B_PERF","step_order":4,"role":"GPT_NATIVE_SPECIALIST","dependencies":["FREEZE"],"instructions_for_gpt":"En CHAT NUEVO GPT Native aislado, investiga SOLO desde P0 rendimiento y estadística: fases, coste de solicitud integral, colas, N+1, repetición de cálculo, comparabilidad de muestras, restricciones de atribución, falsificadores y reversibilidad. No inventar p90, tiempos ni parámetros. Devuelve finding/evidence_or_unknown/falsifier/consequence/cross_role_dependency.","source_doc":"docs/profile_updater/experiments/pe10_ig_reparador_ab_20261017/P0_CASE_AND_PROTOCOL.md","judge_doc":null},{"task_code":"B_AUTH","step_order":5,"role":"GPT_NATIVE_SPECIALIST","dependencies":["FREEZE"],"instructions_for_gpt":"En CHAT NUEVO GPT Native aislado, investiga SOLO desde P0 autoridad/gobernanza: EKB, vigencia de fuente/versión, ACL, autoridad de operación/checkpoint, identificación de Curator vs Validator y independencia material. No convertir 42501 en FAIL funcional. Devuelve finding/evidence_or_unknown/falsifier/consequence/cross_role_dependency.","source_doc":"docs/profile_updater/experiments/pe10_ig_reparador_ab_20261017/P0_CASE_AND_PROTOCOL.md","judge_doc":null},{"task_code":"B_COVER","step_order":6,"role":"GPT_NATIVE_SPECIALIST","dependencies":["FREEZE"],"instructions_for_gpt":"En CHAT NUEVO GPT Native aislado, investiga SOLO desde P0 descubrimiento transversal de omisiones y recurrencias de segundo orden: fronteras, consumidores, retries, invalidación, receipts, gates y riesgos todavía no considerados. No checklist infinito ni supuestos sin evidencia. Devuelve finding/evidence_or_unknown/falsifier/consequence/cross_role_dependency.","source_doc":"docs/profile_updater/experiments/pe10_ig_reparador_ab_20261017/P0_CASE_AND_PROTOCOL.md","judge_doc":null},{"task_code":"B_INNOV","step_order":7,"role":"GPT_NATIVE_SPECIALIST","dependencies":["FREEZE"],"instructions_for_gpt":"En CHAT NUEVO GPT Native aislado, busca desde P0 alternativa innovadora de reparación: eliminar trabajo, simplificar mecanismo, usar una sola lectura segura/contexto por run, mover control a primera frontera o componer reuso; compara novedad versus valor real y garantías de concurrency/currentness/independencia. No inventes sistemas nuevos. Devuelve finding/evidence_or_unknown/falsifier/consequence/cross_role_dependency.","source_doc":"docs/profile_updater/experiments/pe10_ig_reparador_ab_20261017/P0_CASE_AND_PROTOCOL.md","judge_doc":null},{"task_code":"B_DRAFT","step_order":8,"role":"GPT_NATIVE_REPAIR_INTEGRATOR","dependencies":["B_ARCH","B_PERF","B_AUTH","B_COVER","B_INNOV"],"instructions_for_gpt":"En CHAT NUEVO GPT Native Reparador V0.7R1 integrador de B: recibe solo RAW congelados de cinco especialistas B y P0; no ve A, juez ni holdout. Reconciliar contradicciones, distinguir evidencia de hipótesis, priorizar causa sistémica, reparación mínima suficiente, innovación justificada y falsificadores. Emite DRAFT JSON contractual y RAW. Conserva el mismo chat para B_FINAL.","source_doc":"docs/profile_updater/experiments/pe10_ig_reparador_ab_20261017/P0_CASE_AND_PROTOCOL.md","judge_doc":null},{"task_code":"B_CRITIC","step_order":9,"role":"GPT_NATIVE_ADVERSARIAL","dependencies":["B_DRAFT"],"instructions_for_gpt":"En CHAT NUEVO GPT Native adversarial, recibe P0 y borrador B, nunca A ni juez/holdout. Intenta refutar comparador de hashes, exactitud del grafo, validez estadística, autoridad, permisos, independencia AUD-045, riesgo de cachés/replay y alcance de la solución. Devuelve objeciones concretas, falsificador y hallazgo nuevo sustentado o UNKNOWN. No se permite aceptar soluciones por consenso.","source_doc":"docs/profile_updater/experiments/pe10_ig_reparador_ab_20261017/P0_CASE_AND_PROTOCOL.md","judge_doc":null},{"task_code":"B_FINAL","step_order":10,"role":"GPT_NATIVE_REPAIR_INTEGRATOR","dependencies":["B_CRITIC"],"instructions_for_gpt":"Volver AL MISMO CHAT GPT integrador B_DRAFT, enviar SOLO el RAW del crítico, corregir/equilibrar solución sin leer A ni juez. Congelar B_FINAL JSON bajo el mismo contrato que A, RAW exacto, SHA, refs, duración y tokens solo si medidos. La integración no atribuye ejecución real a 6 GPT si los chats independientes no existieron.","source_doc":"docs/profile_updater/experiments/pe10_ig_reparador_ab_20261017/P0_CASE_AND_PROTOCOL.md","judge_doc":null},{"task_code":"JUDGE","step_order":11,"role":"GPT_NATIVE_INDEPENDENT_JUDGE","dependencies":["A_PRODUCER","B_FINAL"],"instructions_for_gpt":"Luego de congelar ambas salidas, en CHAT NUEVO GPT Native juez separado: recibir A y B anonimizados sin labels ni arquitectura, caso P0 y JUDGE_ONLY.md (nunca lo vieron productores). Comparar fuente P0 vs predicción falsable vs holdout posterior; puntuar seis dimensiones 0-3; medir valor marginal y coste observado. Emitir B_SUPERIOR, A_SUPERIOR, EMPATE o NO_DEMOSTRADO, no declarar significancia poblacional en n=1; capturar RAW/hash.","source_doc":"docs/profile_updater/experiments/pe10_ig_reparador_ab_20261017/P0_CASE_AND_PROTOCOL.md","judge_doc":"docs/profile_updater/experiments/pe10_ig_reparador_ab_20261017/JUDGE_ONLY.md"},{"task_code":"DECISION","step_order":12,"role":"CLAUDE_COORDINATOR","dependencies":["JUDGE"],"instructions_for_gpt":"Consolida event IDs y RAW SHA de todos los pasos, mide sesiones reales, no inventes tokens/tiempo, verifica ausencia de contaminación e independencia. Devuelve tabla A vs B, hallazgos exclusivos, falsos críticos, valor marginal, costos, opciones de PE10. Documenta riesgos EKB nuevos vía vía autorizada, no actives subagentes ni cambies checkpoints/producción. Encamina PR de evidencia por CI→PASE→Train→POST-PASE si aplica, sin merge directo. Si juez NO_DEMOSTRADO, mantén método actual sin campaña artificial. Evento de decisión no implica aprobación automática.","source_doc":"docs/profile_updater/experiments/pe10_ig_reparador_ab_20261017/P0_CASE_AND_PROTOCOL.md","judge_doc":null}]$stage_packets$::jsonb;
  v_row jsonb;
  v_code text;
  v_exec text;
  v_subject constant text := 'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1/PE10_IG_REPAIR_AB';
  v_set constant text := 'PE10_IG_REPAIR_AB_20261017_V1';
  v_payload jsonb;
  v_found jsonb;
  v_count integer := 0;
BEGIN
  FOR v_row IN SELECT value FROM jsonb_array_elements(v_rows) ORDER BY (value->>'step_order')::int LOOP
    v_code := v_row->>'task_code';
    v_exec := v_set || '|' || v_code;
    v_payload := jsonb_build_object(
      'evidence_schema_version','operational-event/v2',
      'execution_id',v_exec,
      'producer','PE10_IG_REPAIR_AB_CLAUDE_COORDINATOR_V1',
      'purpose','Prepared governed handoff for blinded IG Reparador A/B research; no GPT Native execution certified.',
      'occurred_at',to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"+00:00"'),
      'subject_ref',v_subject,
      'coordination_set',v_set,
      'task_code',v_code,
      'step_order',(v_row->>'step_order')::int,
      'role',v_row->>'role',
      'dependencies',v_row->'dependencies',
      'source_doc',v_row->>'source_doc',
      'judge_doc',v_row->'judge_doc',
      'frozen_source_event_id',20161,
      'p0_cutoff','2026-10-15T00:00:00+00:00',
      'source_sha256_required',true,
      'instructions_for_gpt',v_row->>'instructions_for_gpt',
      'status','PREPARED_NOT_EXECUTED',
      'acceptance_declared',false,
      'provider_attested',false,
      'raw_runtime_receipt',false,
      'independent_execution_verified',false,
      'checkpoint_transition_performed',false,
      'production_authorized',false,
      'evidence_tier','OWNER_APPROVED_BROWSER_NATIVE_UNATTESTED');
    IF NOT EXISTS (
      SELECT 1 FROM public.lf_eventos
      WHERE evento_tipo='HANDOFF_DEEP_CONTEXT' AND created_by_execution_id=v_exec
    ) THEN
      INSERT INTO public.lf_eventos(
        evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,created_by_execution_id,payload
      ) VALUES(
        'HANDOFF_DEEP_CONTEXT','PROGRAM_PLAN',
        'PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1.PE10_IG_AB.'||v_code,
        'PE10 IG A/B step handoff prepared; no execution/acceptance claimed.',
        'INFO','DERIVE_FROM_EXECUTION_ID',v_exec,v_payload
      );
    END IF;
    SELECT count(*),min(payload::text)::jsonb INTO v_count,v_found
    FROM public.lf_eventos
    WHERE evento_tipo='HANDOFF_DEEP_CONTEXT' AND created_by_execution_id=v_exec
      AND entidad_codigo='PROFILE_UPDATER_EVOLUTION_IMPLEMENTATION_V1.PE10_IG_AB.'||v_code;
    IF v_count <> 1 OR v_found->>'instructions_for_gpt' IS DISTINCT FROM v_row->>'instructions_for_gpt'
      OR v_found->>'status' IS DISTINCT FROM 'PREPARED_NOT_EXECUTED'
      OR v_found->>'acceptance_declared' IS DISTINCT FROM 'false'
      OR v_found->'dependencies' IS DISTINCT FROM v_row->'dependencies'
      OR v_found->>'subject_ref' IS DISTINCT FROM v_subject
    THEN RAISE EXCEPTION 'PE10_IG_AB_HANDOFF_EVENT_MISMATCH:%',v_code;
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM public.lf_eventos WHERE evento_tipo='HANDOFF_DEEP_CONTEXT'
    AND created_by_execution_id LIKE v_set || '|%') <> 13
  THEN RAISE EXCEPTION 'PE10_IG_AB_HANDOFF_COUNT_INCOMPLETE'; END IF;
END
$pe10_ig_ab_handoff$;
COMMIT;
