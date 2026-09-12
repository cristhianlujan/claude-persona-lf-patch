alter table private.lf_p0_review_evidence_objects_v1 set (
  autovacuum_vacuum_scale_factor = 0.05,
  autovacuum_vacuum_threshold = 10,
  autovacuum_analyze_scale_factor = 0.10,
  autovacuum_analyze_threshold = 10,
  toast.autovacuum_vacuum_scale_factor = 0.05,
  toast.autovacuum_vacuum_threshold = 10
);

comment on table private.lf_p0_review_evidence_objects_v1 is
'P0 private evidence store. Retention is bounded by fn_lf_p0_evidence_retention_guard_v1; aggressive table/TOAST autovacuum is configured so deleted evidence space is reusable without manual VACUUM FULL.';
