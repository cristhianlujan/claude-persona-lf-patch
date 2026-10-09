-- T-REMED performance: indexes for the lookups the layers and undo perform.
create index if not exists t_remed_change_log_subject_idx on programacion.t_remed_change_log (subject_kind, subject_id, layer, created_at);
create index if not exists t_remed_change_log_target_idx on programacion.t_remed_change_log (target_table, pk_value) where reverted_at is null;
create index if not exists t_remed_links_subject_idx on programacion.t_remed_links (subject_kind, subject_id, status);
