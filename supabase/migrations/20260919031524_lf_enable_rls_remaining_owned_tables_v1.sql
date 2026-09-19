-- Router: ACT-0001
-- Operation: ACTUALIZACION_DB_LF (MIGRATION / UPDATE)
-- Scope: enable RLS only on LF/Saly-owned tables currently lacking it.
-- Excluded as platform/system-owned: net._http_response, net.http_request_queue,
-- supabase_migrations.schema_migrations.
-- Rollback (only if required): DISABLE ROW LEVEL SECURITY on the 42 listed tables
-- and DROP POLICY private.pol_lf_reconciliation_writer_auth_v5_read.
-- Existing grants are preserved. The only non-BYPASSRLS external grant found is
-- SELECT on private.lf_reconciliation_writer_auth_v5 to lf_governance_owner_v3;
-- the policy below preserves that exact access and does not broaden it.

begin;

alter table lf_knowledge.decisiones_producto enable row level security;
alter table lf_knowledge.user_stories enable row level security;

alter table lf_proto.checkout_pricing_quotes enable row level security;
alter table lf_proto.proto_home_sections enable row level security;
alter table lf_proto.proto_home_tasks enable row level security;
alter table lf_proto.proto_offers enable row level security;
alter table lf_proto.proto_onboarding enable row level security;
alter table lf_proto.proto_sessions enable row level security;
alter table lf_proto.proto_simulations enable row level security;

alter table overall_design.niubiz_action_code_map enable row level security;
alter table overall_design.regulatory_references enable row level security;
alter table overall_design.retry_lockout_matrix enable row level security;
alter table overall_design.screen_area_task_display_codes enable row level security;
alter table overall_design.task_regulatory_reference_links enable row level security;

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

drop policy if exists pol_lf_reconciliation_writer_auth_v5_read
  on private.lf_reconciliation_writer_auth_v5;
create policy pol_lf_reconciliation_writer_auth_v5_read
  on private.lf_reconciliation_writer_auth_v5
  for select
  to lf_governance_owner_v3
  using (true);

alter table saly.conversation_events enable row level security;
alter table saly.conversation_threads enable row level security;
alter table saly.costos enable row level security;
alter table saly.decisiones enable row level security;
alter table saly.documentos enable row level security;
alter table saly.escenarios enable row level security;
alter table saly.evento_costos enable row level security;
alter table saly.evento_decisiones enable row level security;
alter table saly.evento_escenarios enable row level security;
alter table saly.evento_evidencias enable row level security;
alter table saly.evento_supuestos enable row level security;
alter table saly.evidencia_documentos enable row level security;
alter table saly.evidencias enable row level security;
alter table saly.historicos_operativos_mensuales enable row level security;
alter table saly.proyecto enable row level security;
alter table saly.supuestos_financieros enable row level security;

commit;
