-- Hands the frozen A1Q_C2 packet to GPT Native as an operational event (HANDOFF_DEEP_CONTEXT).
-- Data only: no action spec, checkpoint or assertion changes. The event carries a pointer to the packet
-- in unit_metadata plus its hashes and the instructions text. It declares no acceptance.
-- Tier: OWNER_APPROVED_GPT_NATIVE_IN_CHAT_EQUIVALENT (not provider-attested).
BEGIN;
DO $a1q_c2_hand$
DECLARE
 v_plan constant text := 'PROGRAMMING_AGENT_ANALYSIS_REMEDIATION_V1';
 v_exec constant text := 'ANALYSIS_QUAL_C2_GPT_HANDOFF_V1|A1Q_C2';
 v_packet_sha constant text := '1cbe8daa96f35a3a37b194659c690fcbd9437407c465d32987c956a5eef10b4a';
 v_packet jsonb; v_id bigint; v_p jsonb; v_cps_before text; v_cps_after text;
BEGIN
 SELECT unit_metadata#>'{gpt_native_packets_v1,A1Q_C2}' INTO v_packet FROM programacion.engineering_plan_units
  WHERE plan_code=v_plan AND unit_code='A1Q' AND work_item_id=1111;
 IF v_packet IS NULL OR v_packet->>'packet_sha256' IS DISTINCT FROM v_packet_sha THEN RAISE EXCEPTION 'A1Q_C2_HANDOFF_PACKET_MISSING_OR_DRIFT'; END IF;
 IF (SELECT status FROM programacion.engineering_work_checkpoints WHERE work_item_id=1111 AND checkpoint_code='A1Q_C2') IS DISTINCT FROM 'PENDING'
  THEN RAISE EXCEPTION 'A1Q_C2_HANDOFF_NOT_PENDING'; END IF;
 IF EXISTS (SELECT 1 FROM public.lf_eventos WHERE evento_tipo='HANDOFF_DEEP_CONTEXT' AND created_by_execution_id=v_exec) THEN RETURN; END IF;
 SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) INTO v_cps_before FROM programacion.engineering_work_checkpoints WHERE work_item_id=1111;
 INSERT INTO public.lf_eventos(evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,origen,created_by_execution_id,payload)
 VALUES('HANDOFF_DEEP_CONTEXT','PROGRAM_PLAN',v_plan||'.A1Q_C2.GPT_NATIVE_HANDOFF',
  'Frozen A1Q_C2 packet handed to GPT Native for a producer run; no acceptance declared.','INFO','DERIVE_FROM_EXECUTION_ID',v_exec,
  jsonb_build_object(
   'evidence_schema_version','operational-event/v2','execution_id',v_exec,
   'producer','ANALYSIS_QUAL_C2_GPT_HANDOFF_V1',
   'purpose','Hand the frozen A1Q_C2 packet to GPT Native so it can produce the stage output in its own chat.',
   'occurred_at',to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"+00:00"'),
   'acceptance_declared',false,
   'subject_ref',v_packet->>'subject_ref','checkpoint','A1Q_C2','work_item_id',1111,
   'packet_location','supabase://programacion.engineering_plan_units/A1Q#unit_metadata.gpt_native_packets_v1.A1Q_C2',
   'packet_sha256',v_packet_sha,'request_sha256',v_packet->>'request_sha256',
   'input_sha256',v_packet#>>'{input,input_sha256}','producer_mode','GPT_NATIVE',
   'evidence_tier',v_packet->>'evidence_tier','provider_attested',false,
   'instructions_for_gpt',v_packet->>'prompt_for_gpt',
   'return_instructions','Reply in the same chat with ONLY the JSON object, unedited. Keep the chat link; the verifier needs the RAW JSON, the chat link and the transcript SHA-256. Do not claim provider attestation.',
   'limits_note','Owner-approved GPT Native in-chat equivalent. Not a provider receipt and not an independent review. The checkpoint stays pending until a captured output is verified.'))
 RETURNING id INTO v_id;
 SELECT payload INTO v_p FROM public.lf_eventos WHERE id=v_id;
 IF v_p->>'packet_sha256' IS DISTINCT FROM v_packet_sha OR v_p->>'instructions_for_gpt' IS DISTINCT FROM v_packet->>'prompt_for_gpt'
  THEN RAISE EXCEPTION 'A1Q_C2_HANDOFF_READBACK_MISMATCH'; END IF;
 SELECT string_agg(checkpoint_code||':'||status,',' ORDER BY sequence_no) INTO v_cps_after FROM programacion.engineering_work_checkpoints WHERE work_item_id=1111;
 IF v_cps_after IS DISTINCT FROM v_cps_before THEN RAISE EXCEPTION 'A1Q_C2_HANDOFF_CHECKPOINTS_CHANGED'; END IF;
END
$a1q_c2_hand$;
COMMIT;
