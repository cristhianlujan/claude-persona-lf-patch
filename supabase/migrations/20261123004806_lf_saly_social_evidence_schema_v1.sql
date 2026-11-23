-- SALY Ventas: candidate multichannel social-source evidence store.
-- Schema ONLY. No data, runtime grants, source activations, or background fetches.
-- Gate: PG17 isolated positive/negative/ROLLBACK + one migration per PR + Merge Train.
-- Source permission and governor operation are checked at the single approved writer,
-- which is NOT installed by this migration. Every table is inaccessible to clients.

CREATE TABLE saly.ventas_social_runs_v1 (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_ref text NOT NULL UNIQUE CHECK (length(btrim(run_ref)) > 0),
  catalog_version text NOT NULL,
  source_id text NOT NULL,
  business_key text NOT NULL CHECK (length(btrim(business_key)) > 0),
  window_start timestamptz NOT NULL,
  window_end timestamptz NOT NULL,
  started_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  status text NOT NULL DEFAULT 'CANDIDATO' CHECK (status IN ('CANDIDATO','BLOQUEADO','EN_EJECUCION','INCOMPLETO','RECONCILIADO','FALLIDO')),
  stop_reason text,
  cursor_checkpoint text,
  pages_read integer NOT NULL DEFAULT 0 CHECK (pages_read>=0),
  fetch_elapsed_ms bigint CHECK (fetch_elapsed_ms>=0),
  oldest_published_at timestamptz,
  rights_evidence_ref text NOT NULL CHECK (length(btrim(rights_evidence_ref))>0),
  source_receipt_sha256 text CHECK (source_receipt_sha256 IS NULL OR source_receipt_sha256 ~ '^[0-9a-f]{64}$'),
  FOREIGN KEY (catalog_version,source_id) REFERENCES saly.ventas_discovery_catalogo(catalog_version,source_id) ON DELETE RESTRICT,
  CHECK (window_start<window_end),
  CHECK (finished_at IS NULL OR finished_at>=started_at)
);

CREATE TABLE saly.ventas_social_eventos_v1 (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_key text NOT NULL CHECK (length(btrim(business_key))>0),
  event_key text NOT NULL CHECK (length(btrim(event_key))>0),
  event_title text NOT NULL CHECK (length(btrim(event_title))>0),
  identity_state text NOT NULL CHECK (identity_state IN ('VALIDADA','POR_REVISAR')),
  match_state text NOT NULL CHECK (match_state IN ('REVISADO','CANDIDATO')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (business_key,event_key)
);

CREATE TABLE saly.ventas_social_publicaciones_v1 (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id uuid NOT NULL REFERENCES saly.ventas_social_runs_v1(id) ON DELETE RESTRICT,
  event_id uuid NOT NULL REFERENCES saly.ventas_social_eventos_v1(id) ON DELETE RESTRICT,
  business_key text NOT NULL CHECK (length(btrim(business_key))>0),
  source_id text NOT NULL,
  external_ref text NOT NULL CHECK (length(btrim(external_ref))>0),
  url text NOT NULL CHECK (url ~ '^https://[^ ]+$'),
  published_at timestamptz NOT NULL,
  source_sha256 text NOT NULL CHECK (source_sha256 ~ '^[0-9a-f]{64}$'),
  summary_non_personal text NOT NULL CHECK (length(btrim(summary_non_personal))>0),
  captured_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (business_key,source_id,external_ref),
  UNIQUE (business_key,source_id,source_sha256)
);

CREATE TABLE saly.ventas_social_afirmaciones_v1 (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES saly.ventas_social_eventos_v1(id) ON DELETE RESTRICT,
  publicacion_id uuid NOT NULL REFERENCES saly.ventas_social_publicaciones_v1(id) ON DELETE RESTRICT,
  source_id text NOT NULL,
  claim_key text NOT NULL CHECK (length(btrim(claim_key))>0),
  claim_state text NOT NULL CHECK (claim_state IN ('ANUNCIADO','REALIZADO','IMPLEMENTADO','NO_DETERMINADO')),
  polarity text NOT NULL DEFAULT 'NEUTRA' CHECK (polarity IN ('FAVORABLE','CONTRARIA','NEUTRA')),
  source_excerpt_hash text CHECK (source_excerpt_hash IS NULL OR source_excerpt_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (event_id,source_id,claim_key,claim_state)
);

CREATE TABLE saly.ventas_social_concurrencias_v1 (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES saly.ventas_social_eventos_v1(id) ON DELETE RESTRICT,
  original_claim_id uuid NOT NULL REFERENCES saly.ventas_social_afirmaciones_v1(id) ON DELETE RESTRICT,
  confirming_source_id text NOT NULL CHECK (length(btrim(confirming_source_id))>0),
  confirming_external_ref text NOT NULL CHECK (length(btrim(confirming_external_ref))>0),
  confirming_url text NOT NULL CHECK (confirming_url ~ '^https://[^ ]+$'),
  relation text NOT NULL CHECK (relation IN ('MISMO_HECHO','COMPLEMENTA','CONTRADICE','POR_REVISAR')),
  match_evidence_sha256 text CHECK (match_evidence_sha256 IS NULL OR match_evidence_sha256 ~ '^[0-9a-f]{64}$'),
  reviewed boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (original_claim_id,confirming_source_id,confirming_external_ref,relation)
);

CREATE TABLE saly.ventas_social_evaluaciones_v1 (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_key text NOT NULL CHECK (length(btrim(business_key))>0),
  eval_ref text NOT NULL UNIQUE CHECK (length(btrim(eval_ref))>0),
  model_ref text NOT NULL CHECK (length(btrim(model_ref))>0),
  prompt_sha256 text NOT NULL CHECK (prompt_sha256 ~ '^[0-9a-f]{64}$'),
  input_manifest_sha256 text NOT NULL CHECK (input_manifest_sha256 ~ '^[0-9a-f]{64}$'),
  output_sha256 text NOT NULL CHECK (output_sha256 ~ '^[0-9a-f]{64}$'),
  window_start timestamptz NOT NULL,
  window_end timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'CANDIDATA' CHECK (status IN ('CANDIDATA','REVISADA','RECHAZADA','VALIDADA_CAMPO')),
  business_pattern text NOT NULL,
  commercial_hypothesis text NOT NULL,
  alternative_hypothesis text,
  qualification text NOT NULL CHECK (qualification IN ('EXPLORATORIA','MEDIA','ALTA_EXPLORATORIA','REQUIERE_REVISION')),
  predictive_probability numeric CHECK (predictive_probability IS NULL),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (window_start<window_end)
);

CREATE TABLE saly.ventas_social_eval_soportes_v1 (
  evaluation_id uuid NOT NULL REFERENCES saly.ventas_social_evaluaciones_v1(id) ON DELETE RESTRICT,
  claim_id uuid NOT NULL REFERENCES saly.ventas_social_afirmaciones_v1(id) ON DELETE RESTRICT,
  role text NOT NULL CHECK (role IN ('SUSTENTO','CONTRADICCION','ALTERNATIVA')),
  PRIMARY KEY (evaluation_id,claim_id,role)
);

-- B6: provenance and quality remain separate. B14: only one canonical event;
-- publications/claims/concurrences are normalized links rather than duplicated facts.
-- No public access, no direct caller INSERT/UPDATE/DELETE, no automatic API enablement.
ALTER TABLE saly.ventas_social_runs_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE saly.ventas_social_eventos_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE saly.ventas_social_publicaciones_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE saly.ventas_social_afirmaciones_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE saly.ventas_social_concurrencias_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE saly.ventas_social_evaluaciones_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE saly.ventas_social_eval_soportes_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE saly.ventas_social_runs_v1, saly.ventas_social_eventos_v1,
  saly.ventas_social_publicaciones_v1, saly.ventas_social_afirmaciones_v1,
  saly.ventas_social_concurrencias_v1, saly.ventas_social_evaluaciones_v1,
  saly.ventas_social_eval_soportes_v1 FROM PUBLIC, anon, authenticated, service_role;
