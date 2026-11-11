-- ISOLATED PG17 ONLY: reproduce exact existing operation contract before #3786.
-- This table is NOT created by an LF production migration.
CREATE TABLE public.lf_operation_contracts(
 operation_code text PRIMARY KEY, contract_code text NOT NULL, contract_path text NOT NULL,
 contract_sha text, required_before_write jsonb NOT NULL DEFAULT '[]'::jsonb,
 allowed jsonb NOT NULL DEFAULT '{}'::jsonb,
 blocked jsonb NOT NULL DEFAULT '[]'::jsonb,
 required_after_write jsonb NOT NULL DEFAULT '[]'::jsonb,
 status text NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 created_by_execution_id text NOT NULL,updated_by_execution_id text
);
INSERT INTO public.lf_operation_contracts(
 operation_code,contract_code,contract_path,contract_sha,required_before_write,
 allowed,blocked,required_after_write,status,created_by_execution_id)
VALUES(
 'ACTUALIZACION_REGLA_LF',
 'CONTRACT-ACTUALIZACION_REGLA_LF-v0.1',
 'supabase://public/lf_operation_contracts/ACTUALIZACION_REGLA_LF',
 NULL,
 '["ekb_preflight","rule_classified","existing_checked","destination_validated","execution_bound"]'::jsonb,
 '{"destination":"lf_ops.reglas","single_rule":true,"write_state":"CANDIDATO","relation_mutation":false,"automatic_promotion":false}'::jsonb,
 '{"relation_delete":true,"duplicate_create":true,"production_promotion":true,"missing_update_target":true,"vigente_direct_update":true}'::jsonb,
 '["exact_rule_readback","estado_CANDIDATO","execution_trace","no_promotion"]'::jsonb,
 'ACTIVE_ENFORCEMENT','EXEC-BOOTSTRAP-ACTUALIZACION-REGLA-LF-20260913-001'
);
