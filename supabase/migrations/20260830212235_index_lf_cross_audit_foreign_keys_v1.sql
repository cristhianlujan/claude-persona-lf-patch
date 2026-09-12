create index if not exists idx_system_audit_runs_work_id on lf_ops.system_audit_runs(work_id);
create index if not exists idx_system_audit_runs_supersedes_run_id on lf_ops.system_audit_runs(supersedes_run_id);
create index if not exists idx_system_audit_queue_parent_work_id on lf_ops.system_audit_queue(parent_work_id);
create index if not exists idx_system_audit_findings_work_id on lf_ops.system_audit_findings(work_id);
create index if not exists idx_system_audit_findings_source_run_id on lf_ops.system_audit_findings(source_run_id);
create index if not exists idx_system_audit_messages_work_id on lf_ops.system_audit_messages(work_id);
create index if not exists idx_system_audit_human_decisions_work_id on lf_ops.system_audit_human_decisions(work_id);
create index if not exists idx_system_audit_human_decisions_finding_id on lf_ops.system_audit_human_decisions(finding_id);