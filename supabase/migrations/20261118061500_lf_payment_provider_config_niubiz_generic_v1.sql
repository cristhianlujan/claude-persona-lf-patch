-- PR-C | R-PAY-041 provider value registry (no rule/runtime changes).
-- The only inserted address is reserved .invalid data: FICTICIO is not
-- production-authorized. Production consumers must reject FICTICIO.
-- Applied by the governed Migration Merge Train only.
CREATE TABLE public.payment_provider_config (
    provider text NOT NULL,
    config_key text NOT NULL,
    config_value text NOT NULL,
    value_status text NOT NULL
        CONSTRAINT payment_provider_config_status_check
        CHECK (value_status IN ('FICTICIO', 'REAL')),
    valid_from timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT payment_provider_config_provider_nonempty CHECK (btrim(provider) <> ''),
    CONSTRAINT payment_provider_config_key_nonempty CHECK (btrim(config_key) <> ''),
    CONSTRAINT payment_provider_config_value_nonempty CHECK (btrim(config_value) <> ''),
    CONSTRAINT payment_provider_config_unique_version
        UNIQUE (provider, config_key, valid_from)
);

ALTER TABLE public.payment_provider_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_provider_config FORCE ROW LEVEL SECURITY;

-- Explicitly deny the REST-facing roles, including PUBLIC inherited grants.
-- No RLS policy is created; public client roles cannot read or write values.
REVOKE ALL PRIVILEGES ON TABLE public.payment_provider_config
    FROM PUBLIC, anon, authenticated;

INSERT INTO public.payment_provider_config
    (provider, config_key, config_value, value_status)
VALUES
    ('NIUBIZ', 'NIUBIZ_EMAIL_GENERICO',
     'niubiz-generico@lf-ficticio.invalid', 'FICTICIO');
