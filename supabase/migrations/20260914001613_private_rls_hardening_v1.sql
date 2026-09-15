-- LF private schema RLS hardening.
-- Scope: 12 internal tables currently without RLS in LF_SUPABASE_SANDBOX.
-- Preserve existing ACLs. Do not FORCE RLS. service_role remains BYPASSRLS.
-- lf_governance_owner_v3 keeps its existing legitimate SELECT path only on
-- private.lf_reconciliation_writer_auth_v5 through an explicit PERMISSIVE policy.

alter table private.__pr93_v10_dryrun_chunks enable row level security;
alter table private.lf_architecture_delivery_config_v6 enable row level security;
alter table private.lf_edge_function_deployment_evidence_v5 enable row level security;
alter table private.lf_edge_function_deployment_evidence_v6 enable row level security;
alter table private.lf_p0_evidence_upload_chunks_v1 enable row level security;
alter table private.lf_p0_external_durable_evidence_v1 enable row level security;
alter table private.lf_p0_human_review_challenges_v1 enable row level security;
alter table private.lf_p0_human_review_decisions_v1 enable row level security;
alter table private.lf_p0_review_evidence_objects_v1 enable row level security;
alter table private.lf_profile_runtime_queue_v1 enable row level security;
alter table private.lf_reconciliation_writer_auth_v5 enable row level security;
alter table private.lf_source_documents enable row level security;

create policy private_reconciliation_writer_auth_governance_owner_select
on private.lf_reconciliation_writer_auth_v5
as permissive
for select
to lf_governance_owner_v3
using (true);
