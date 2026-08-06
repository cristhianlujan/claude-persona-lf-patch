-- P0 Visual Reading v1.1 Supabase dry-run. Must be executed inside a transaction and rolled back.
BEGIN;

-- Explicit negative IDs avoid sequence consumption.
INSERT INTO public.lf_strategy_snapshots (id,snapshot_code,snapshot_family,snapshot_type,canonical_name,version,status,project_code,front_code,owner_name,source_kind,storage_policy,metadata,content_payload,visibility,runtime_state,impact_policy,previous_version_code,created_by,updated_by_execution_id)
OVERRIDING SYSTEM VALUE
VALUES (-1000011,'P0_VISUAL_READING_ARCHITECTURE_LF_20260803','P0_VISUAL_READING','ARCHITECTURE','P0 Visual Reading Architecture','v1.1','CANDIDATO_PENDING_ATTESTATION','LF','STORY_CREATOR','Cristhian','CHATGPT', '{"immutable":true}'::jsonb, '{"dry_run":true}'::jsonb, '{"assembly_complete":true,"schema_version":"p0-technical-handoff/v5"}'::jsonb, 'READ_ONLY_INTERNAL','NO_HABILITADO','BLOQUEADO','v1.0','EXEC-BISC-P0-VISUAL-HANDOFF-005','EXEC-BISC-P0-VISUAL-HANDOFF-005');

INSERT INTO public.lf_eventos (id,evento_tipo,entidad_tipo,entidad_codigo,descripcion,severidad,payload,origen,created_by_execution_id,updated_by_execution_id)
OVERRIDING SYSTEM VALUE
VALUES (-10003248,'STRATEGY_SNAPSHOT_CONSOLIDATED','STRATEGY_SNAPSHOT','P0_VISUAL_READING_ARCHITECTURE_LF_20260803','Dry-run v1.1 rollback only','INFO', '{"purpose":"Validate rollback behavior without persistence.","version":"v1.1","producer":"CHATGPT_SUPABASE_CONNECTOR","occurred_at":"2026-08-06T16:25:43Z","execution_id":"EXEC-BISC-P0-VISUAL-HANDOFF-005","evidence_schema_version":"operational-event/v2","runtime_enabled":false,"merge_authorized":false,"production_authorized":false,"acceptance_declared":false}'::jsonb,'CHATGPT_SUPABASE_CONNECTOR','EXEC-BISC-P0-VISUAL-HANDOFF-005','EXEC-BISC-P0-VISUAL-HANDOFF-005');

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.lf_strategy_snapshots WHERE id=-1000011) THEN RAISE EXCEPTION 'DRY_RUN_SNAPSHOT_MISSING'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.lf_eventos WHERE id=-10003248) THEN RAISE EXCEPTION 'DRY_RUN_EVENT_MISSING'; END IF;
END $$;

ROLLBACK;
