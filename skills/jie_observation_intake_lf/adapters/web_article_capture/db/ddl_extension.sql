-- ddl_lf_capture_records_extension.sql
-- ADAPTER_JIE_WEB_ARTICLE_CAPTURE_LF_CANDIDATO_V0_2
-- Estado: CANDIDATO / READ_ONLY · Lote 20B
-- NOTA: Esta migración ya fue aplicada en Supabase el 2026-06-07 (Lote 20B)
-- Migration name: extend_lf_capture_records_web_columns_v0_2
-- Evidencia: lf_eventos id=242

-- ⚠️ NO VOLVER A EJECUTAR — ya aplicada. Incluida aquí como referencia de schema.
-- Para re-aplicar en otro proyecto: usar ADD COLUMN IF NOT EXISTS (idempotente).

alter table public.lf_capture_records
  -- URL tracking
  add column if not exists url_solicitada text,
  add column if not exists redireccion_detectada boolean not null default false,

  -- Autoría y metadatos declarados (solo si visibles en página)
  add column if not exists autor_declarado text,            -- NOT_FOUND si no visible
  add column if not exists fecha_publicacion_declarada text, -- NOT_FOUND si no visible
  add column if not exists meta_description text,
  add column if not exists tiempo_lectura_declarado text,
  add column if not exists lead_literal text,               -- primer párrafo literal

  -- Extracción estructurada (arrays JSON)
  -- Estructura claims: [{texto_literal, fuente_en_pagina, tipo, verificado_fuente_primaria: false, nota}]
  add column if not exists claims_json jsonb not null default '[]',

  -- Estructura ctas: [{texto, url_destino, posicion}]
  add column if not exists ctas_json jsonb not null default '[]',

  -- Señales de confianza: menciones regulatorias, certificaciones, datos de respaldo
  add column if not exists senales_confianza_json jsonb not null default '[]',

  -- Antipatrones: clickbait, urgencia artificial, claims sin fuente
  add column if not exists antipatrones_json jsonb not null default '[]',

  -- Productos mencionados con contexto
  add column if not exists producto_mencionado_json jsonb,

  -- Control de truncamiento
  add column if not exists truncado_en text,               -- posición aprox de corte
  add column if not exists campos_truncados_json jsonb not null default '[]',

  -- Seguridad
  add column if not exists prompt_injection_detectado boolean not null default false,
  add column if not exists prompt_injection_fragmento text, -- primeros 200 chars del fragmento

  -- Contexto de ejecución
  add column if not exists modo_ejecucion text,            -- mode del input_contract
  add column if not exists actor_id text,                  -- actor_id del input_contract
  add column if not exists actor_role text,                -- actor_role del input_contract

  -- Estado específico de extracción web (separado de record_status del sistema)
  -- Valores: COMPLETA | EXTRACCION_PARCIAL | BLOCKED_*
  add column if not exists estado_extraccion_web text,

  -- Revisión programada
  -- 30d: precios/tasas · 90d: claims regulatorios · 180d: educativo estable
  add column if not exists fecha_proxima_revision date;

-- Comentarios de columnas
comment on column public.lf_capture_records.url_solicitada
  is 'URL original recibida como input. Puede diferir de url (url_final) si hubo redirección. Adapter JIE Web v0.2.';

comment on column public.lf_capture_records.claims_json
  is 'Claims literales extraídos. Estructura: [{texto_literal, fuente_en_pagina, tipo, verificado_fuente_primaria: false, nota}]. Adapter JIE Web v0.2.';

comment on column public.lf_capture_records.ctas_json
  is 'CTAs literales. Estructura: [{texto, url_destino, posicion}]. Adapter JIE Web v0.2.';

comment on column public.lf_capture_records.senales_confianza_json
  is 'Señales de confianza: menciones SBS/BCRP/SMV, certificaciones, datos de respaldo. Adapter JIE Web v0.2.';

comment on column public.lf_capture_records.antipatrones_json
  is 'Antipatrones: clickbait, urgencia artificial, claims sin fuente, promesas sin respaldo. Adapter JIE Web v0.2.';

comment on column public.lf_capture_records.estado_extraccion_web
  is 'Estado específico de la extracción web. Separado de record_status del sistema LF. Valores: COMPLETA, EXTRACCION_PARCIAL, BLOCKED_*. Adapter JIE Web v0.2.';

comment on column public.lf_capture_records.prompt_injection_detectado
  is 'True si se detectó instrucción maliciosa en el contenido. La instrucción es ignorada; extracción continúa. Adapter JIE Web v0.2.';

comment on column public.lf_capture_records.fecha_proxima_revision
  is '30d si precios/tasas en ctas_json. 90d si claims regulatorios. 180d si educativo estable. Adapter JIE Web v0.2.';
