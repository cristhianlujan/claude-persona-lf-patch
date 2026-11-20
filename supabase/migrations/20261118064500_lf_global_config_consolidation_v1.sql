-- PR-D | One LF global configurations table, replacing PR-C provider-only storage.
-- Scope is strictly public.lf_global_config and public.payment_provider_config.
-- No rule consumer changes; FICTICIO remains a non-production placeholder.
-- Fail closed if the PR-C source differs from the verified single fictitious row.
DO $pre$
DECLARE
    v_count bigint;
BEGIN
    IF to_regclass('public.lf_global_config') IS NOT NULL THEN
        RAISE EXCEPTION 'PR_D_TARGET_PREEXISTS';
    END IF;
    IF to_regclass('public.payment_provider_config') IS NULL THEN
        RAISE EXCEPTION 'PR_D_SOURCE_MISSING';
    END IF;
    SELECT count(*) INTO v_count FROM public.payment_provider_config;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'PR_D_SOURCE_CARDINALITY count=%', v_count;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.payment_provider_config
        WHERE provider = 'NIUBIZ'
          AND config_key = 'NIUBIZ_EMAIL_GENERICO'
          AND config_value = 'niubiz-generico@lf-ficticio.invalid'
          AND value_status = 'FICTICIO'
          AND valid_from IS NOT NULL AND created_at IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'PR_D_SOURCE_UNEXPECTED';
    END IF;
END;
$pre$;

CREATE TABLE public.lf_global_config (
    scope text NOT NULL
        CONSTRAINT lf_global_config_scope_nonempty CHECK (btrim(scope) <> ''),
    config_key text NOT NULL
        CONSTRAINT lf_global_config_key_nonempty CHECK (btrim(config_key) <> ''),
    config_value text NOT NULL
        CONSTRAINT lf_global_config_value_nonempty CHECK (btrim(config_value) <> ''),
    value_type text NOT NULL
        CONSTRAINT lf_global_config_type_check
        CHECK (value_type IN ('TEXT', 'INTEGER', 'DECIMAL', 'BOOLEAN', 'JSON', 'EMAIL')),
    value_status text NOT NULL
        CONSTRAINT lf_global_config_status_check
        CHECK (value_status IN ('FICTICIO', 'REAL')),
    description text,
    valid_from timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT lf_global_config_unique_version
        UNIQUE (scope, config_key, valid_from)
);

ALTER TABLE public.lf_global_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lf_global_config FORCE ROW LEVEL SECURITY;
-- No policies: revoke even inherited client-role privileges.
REVOKE ALL PRIVILEGES ON TABLE public.lf_global_config
    FROM PUBLIC, anon, authenticated;

-- Copy actual persisted value AND version timestamps, never synthesize them.
INSERT INTO public.lf_global_config
    (scope, config_key, config_value, value_type, value_status,
     description, valid_from, created_at)
SELECT
    'PAGOS',
    config_key,
    config_value,
    'EMAIL',
    value_status,
    'Correo generico enviado a Niubiz cuando el correo del cliente empieza con numero (R-PAY-040/041)',
    valid_from,
    created_at
FROM public.payment_provider_config
WHERE provider = 'NIUBIZ'
  AND config_key = 'NIUBIZ_EMAIL_GENERICO'
  AND value_status = 'FICTICIO';

-- Evidence gate inside the same migration, before the authorised table removal.
DO $readback$
DECLARE
    v_count bigint;
BEGIN
    SELECT count(*) INTO v_count FROM public.lf_global_config;
    IF v_count <> 1 THEN
        RAISE EXCEPTION 'PR_D_COPIED_CARDINALITY count=%', v_count;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.lf_global_config dst
        JOIN public.payment_provider_config src
          ON src.provider = 'NIUBIZ'
         AND dst.scope = 'PAGOS'
         AND dst.config_key = src.config_key
         AND dst.config_value = src.config_value
         AND dst.value_status = src.value_status
         AND dst.valid_from = src.valid_from
         AND dst.created_at = src.created_at
        WHERE dst.config_key = 'NIUBIZ_EMAIL_GENERICO'
          AND dst.value_type = 'EMAIL'
          AND dst.value_status = 'FICTICIO'
          AND dst.description =
            'Correo generico enviado a Niubiz cuando el correo del cliente empieza con numero (R-PAY-040/041)'
    ) THEN
        RAISE EXCEPTION 'PR_D_COPY_OR_TIMESTAMP_MISMATCH';
    END IF;
END;
$readback$;

-- Plain DROP: any undiscovered dependent SQL object blocks the migration.
DROP TABLE public.payment_provider_config;
