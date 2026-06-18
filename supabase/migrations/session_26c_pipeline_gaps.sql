-- =============================================================================
-- MIGRATION: session_26c_pipeline_gaps
-- Fecha: 2026-06-18 | Sesión: 26 lote 26C | Evento: 416
-- G1: trigger consumer_ready automático
-- G2: estados queue + url_tipo + curación URLs comerciales
-- G3: artículos educativos específicos en queue
-- G4: fn_restock_url_queue
-- G5: content_flag en lf_capture_records
-- =============================================================================

-- G1: Trigger consumer_ready automático
CREATE OR REPLACE FUNCTION public.fn_auto_consumer_ready()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.quality_score >= 0.70
     AND NEW.grounding_status = 'GROUNDED'
     AND (NEW.consumer_ready = FALSE OR NEW.consumer_ready IS NULL)
  THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.lf_content_decisions
      WHERE decision_id = NEW.decision_id AND hitl_required = TRUE
    ) THEN
      NEW.consumer_ready := TRUE;
      NEW.reviewed_by   := COALESCE(NEW.reviewed_by, 'AUTO_QUALITY_GATE');
      NEW.reviewed_at   := COALESCE(NEW.reviewed_at, NOW());
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_auto_consumer_ready
BEFORE INSERT OR UPDATE ON public.lf_knowledge_base
FOR EACH ROW EXECUTE FUNCTION public.fn_auto_consumer_ready();

-- G2a: Ampliar estados válidos de lf_url_queue
ALTER TABLE public.lf_url_queue DROP CONSTRAINT IF EXISTS lf_url_queue_estado_check;
ALTER TABLE public.lf_url_queue ADD CONSTRAINT lf_url_queue_estado_check
  CHECK (estado = ANY (ARRAY['PENDIENTE','PROCESADO','FALLIDO','DESCARTADO','SKIP']));

-- G2b: Columna url_tipo
ALTER TABLE public.lf_url_queue ADD COLUMN IF NOT EXISTS url_tipo TEXT DEFAULT 'EDUCATIVO'
  CHECK (url_tipo = ANY (ARRAY['EDUCATIVO','COMERCIAL','REGULATORIO','COMPETENCIA','INDICE','OTRO']));

-- G2c: Columna skip_reason
ALTER TABLE public.lf_url_queue ADD COLUMN IF NOT EXISTS skip_reason TEXT;

-- G2d: Descartar URLs comerciales/onboarding
UPDATE public.lf_url_queue
SET estado = 'DESCARTADO', url_tipo = 'COMERCIAL',
    skip_reason = 'Página de conversión/onboarding sin contenido educativo accionable'
WHERE url IN (
  'https://finanty.com/unete',
  'https://finanty.com/procedimientos-pagos',
  'https://finanty.com/'
);

-- G3: Artículos educativos específicos de reevalua.com
INSERT INTO public.lf_url_queue (url, fuente, keyword_target, url_tipo, estado, created_by)
VALUES
  ('https://reevalua.com/blog/como-salir-de-infocorp-con-datos-reales',
   'DESCUBIERTO_PIPELINE','salir de Infocorp','EDUCATIVO','PENDIENTE','AGENT_GOV'),
  ('https://reevalua.com/blog/subir-score-de-credito-historial-crediticio',
   'DESCUBIERTO_PIPELINE','score crediticio','EDUCATIVO','PENDIENTE','AGENT_GOV'),
  ('https://reevalua.com/blog/cuanto-tiempo-demora-salir-de-infocorp',
   'DESCUBIERTO_PIPELINE','salir de Infocorp','EDUCATIVO','PENDIENTE','AGENT_GOV'),
  ('https://reevalua.com/blog/beneficios-de-un-buen-historial-crediticio',
   'DESCUBIERTO_PIPELINE','historial crediticio','EDUCATIVO','PENDIENTE','AGENT_GOV'),
  ('https://reevalua.com/blog/las-deudas-en-el-sistema-financiero-si-prescriben-en-el-peru-esto-dice-la-ley',
   'DESCUBIERTO_PIPELINE','prescripcion deuda','REGULATORIO','PENDIENTE','AGENT_GOV'),
  ('https://reevalua.com/blog/como-acceder-a-un-prestamo-si-fui-rechazado',
   'DESCUBIERTO_PIPELINE','prestamos sin historial','EDUCATIVO','PENDIENTE','AGENT_GOV')
ON CONFLICT (url) DO NOTHING;

-- G4: fn_restock_url_queue
CREATE OR REPLACE FUNCTION public.fn_restock_url_queue(
  p_urls TEXT[],
  p_fuente TEXT DEFAULT 'RESTOCK_AUTONOMO',
  p_keyword TEXT DEFAULT 'rehabilitacion crediticia'
)
RETURNS TABLE(inserted_url TEXT, queue_id UUID)
LANGUAGE plpgsql AS $$
DECLARE v_url TEXT;
BEGIN
  FOREACH v_url IN ARRAY p_urls LOOP
    INSERT INTO public.lf_url_queue (url, fuente, keyword_target, url_tipo, estado, created_by)
    VALUES (v_url, p_fuente, p_keyword, 'EDUCATIVO', 'PENDIENTE', 'AGENT_GOV')
    ON CONFLICT (url) DO NOTHING
    RETURNING url, lf_url_queue.queue_id INTO inserted_url, queue_id;
    IF FOUND THEN RETURN NEXT; END IF;
  END LOOP;
END;
$$;

-- G5: content_flag en lf_capture_records
ALTER TABLE public.lf_capture_records
  ADD COLUMN IF NOT EXISTS content_flag TEXT DEFAULT 'NINGUNO'
  CHECK (content_flag = ANY (ARRAY[
    'NINGUNO','COMERCIAL_DETECTADO','PROMESA_GARANTIZADA',
    'DATOS_INCOMPLETOS','FUENTE_DUDOSA','CONTENIDO_DUPLICADO'
  ]));
ALTER TABLE public.lf_capture_records ADD COLUMN IF NOT EXISTS content_flag_reason TEXT;

-- =============================================================================
-- FIN MIGRATION session_26c_pipeline_gaps | Evento 416
-- =============================================================================
