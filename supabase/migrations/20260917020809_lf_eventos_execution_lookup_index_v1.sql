-- Canonical performance hardening for execution-scoped LF event readback.
-- Avoids sequential scans when consumers read recent events for one execution.

create index if not exists idx_lf_eventos_created_by_execution_created_at
  on public.lf_eventos using btree (created_by_execution_id, created_at desc);
