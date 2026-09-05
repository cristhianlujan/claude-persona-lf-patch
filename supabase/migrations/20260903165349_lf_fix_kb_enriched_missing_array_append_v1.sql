create or replace function public.fn_block_empty_kb_enriched()
returns trigger
language plpgsql
set search_path to 'pg_catalog','public'
as $function$
declare
  v_missing text[] := '{}';
begin
  if new.kb_enriched is null or new.kb_enriched = '{}'::jsonb then
    raise exception 'KB_ENRICHED_VACIO: kb_enriched no puede ser NULL ni vacío.';
  end if;

  if not (new.kb_enriched ? 'identidad') then v_missing := array_append(v_missing, 'identidad'); end if;
  if not (new.kb_enriched ? 'confianza') then v_missing := array_append(v_missing, 'confianza'); end if;
  if not (new.kb_enriched ? 'conversion') then v_missing := array_append(v_missing, 'conversion'); end if;
  if not (new.kb_enriched ? 'uso_semantico') then v_missing := array_append(v_missing, 'uso_semantico'); end if;
  if not (new.kb_enriched ? 'propuesta_comercial') then v_missing := array_append(v_missing, 'propuesta_comercial'); end if;
  if not (new.kb_enriched ? 'riesgo_cumplimiento') then v_missing := array_append(v_missing, 'riesgo_cumplimiento'); end if;

  if array_length(v_missing, 1) > 0 then
    raise exception 'KB_ENRICHED_INCOMPLETO: faltan bloques S5-B obligatorios: %. Completar antes de escribir en lf_knowledge_base.', array_to_string(v_missing, ', ');
  end if;

  if new.source_url is null then
    raise exception 'KB_QUALITY_GATE: source_url no puede ser NULL.';
  end if;

  if new.visible_text is null then
    raise exception 'KB_QUALITY_GATE: visible_text no puede ser NULL.';
  end if;

  if new.summary is null then
    raise exception 'KB_QUALITY_GATE: summary no puede ser NULL.';
  end if;

  if new.summary = new.visible_text then
    raise exception 'KB_QUALITY_GATE: summary no puede ser copia literal de visible_text.';
  end if;

  if new.key_insights is null or jsonb_typeof(new.key_insights) <> 'array' or jsonb_array_length(new.key_insights) < 3 then
    raise exception 'KB_QUALITY_GATE: key_insights debe ser array con mínimo 3 elementos.';
  end if;

  return new;
end;
$function$;