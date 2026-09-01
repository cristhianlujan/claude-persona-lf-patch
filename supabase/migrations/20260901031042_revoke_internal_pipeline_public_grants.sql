-- Internal LF pipeline/governance tables are not client-facing.
-- Existing RLS policies explicitly deny anon/authenticated for ALL commands.
-- Remove legacy/default table grants so access is denied at the privilege layer first.
-- Keep service_role privileges and existing RLS policies unchanged.
revoke all privileges on table public.lf_audit_backlog from anon, authenticated;
revoke all privileges on table public.lf_audit_objetivo from anon, authenticated;
revoke all privileges on table public.lf_content_decisions from anon, authenticated;
revoke all privileges on table public.lf_homologated_records from anon, authenticated;
revoke all privileges on table public.lf_knowledge_base from anon, authenticated;
revoke all privileges on table public.lf_knowledge_base_backup_29g from anon, authenticated;
revoke all privileges on table public.lf_pipeline_runs from anon, authenticated;
revoke all privileges on table public.lf_sandbox_runs from anon, authenticated;
revoke all privileges on table public.lf_taxonomia_lf from anon, authenticated;
revoke all privileges on table public.lf_url_queue from anon, authenticated;
