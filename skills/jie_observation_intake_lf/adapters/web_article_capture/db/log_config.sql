-- log_config_keys.sql
-- ADAPTER_JIE_WEB_ARTICLE_CAPTURE_LF_CANDIDATO_V0_2
-- Estado: CANDIDATO / READ_ONLY · Lote 20B
-- NOTA: Ya ejecutado en Supabase el 2026-06-07 (Lote 20B). Evidencia: lf_eventos id=242
-- Incluido aquí como referencia. ON CONFLICT DO NOTHING → idempotente.

insert into public.lf_log_config
  (log_key, descripcion, enabled, target_table, nivel_minimo, retention_days, updated_reason)
values
  (
    'WEB_EXTRACTION_GATE_EVENT',
    'Evento de gate en extracción web. Adapter ADAPTER_JIE_WEB_ARTICLE_CAPTURE_LF_CANDIDATO_V0_2.',
    true,
    'public.lf_log_operativo',
    'INFO',
    90,
    'Lote 20B — candidato aprobado usuario 2026-06-07'
  ),
  (
    'WEB_EXTRACTION_BLOCK',
    'Bloqueo en flujo de extracción web (gate fallido, duplicado, permiso). Adapter JIE Web v0.2.',
    true,
    'public.lf_log_operativo',
    'WARN',
    90,
    'Lote 20B — candidato aprobado usuario 2026-06-07'
  ),
  (
    'WEB_EXTRACTION_ERROR',
    'Error en extracción web: fetch failed, DB write failed, readback failed. Adapter JIE Web v0.2.',
    true,
    'public.lf_log_operativo',
    'ERROR',
    180,
    'Lote 20B — candidato aprobado usuario 2026-06-07'
  ),
  (
    'WEB_EXTRACTION_COMPLETE',
    'Extracción completada y persistida en lf_capture_records. Adapter JIE Web v0.2.',
    true,
    'public.lf_log_operativo',
    'INFO',
    90,
    'Lote 20B — candidato aprobado usuario 2026-06-07'
  ),
  (
    'WEB_EXTRACTION_INJECTION',
    'Prompt injection detectado en contenido web. Instrucción ignorada. Adapter JIE Web v0.2.',
    true,
    'public.lf_log_operativo',
    'WARN',
    180,
    'Lote 20B — candidato aprobado usuario 2026-06-07'
  ),
  (
    'WEB_EXTRACTION_ADMIN_OVERRIDE',
    'Override admin ejecutado. Requiere admin_override_reason. Adapter JIE Web v0.2.',
    true,
    'public.lf_log_operativo',
    'WARN',
    365,
    'Lote 20B — candidato aprobado usuario 2026-06-07'
  )
on conflict (log_key) do nothing;

-- Verificación post-insert:
-- select log_key, enabled, nivel_minimo from public.lf_log_config
-- where log_key like 'WEB_EXTRACTION_%';
