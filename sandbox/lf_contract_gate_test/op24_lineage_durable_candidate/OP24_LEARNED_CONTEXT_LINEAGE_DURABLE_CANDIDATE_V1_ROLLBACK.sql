-- OP24 Learned Context Lineage durable candidate v1 rollback.
-- SOURCE-ONLY. Execute only inside the governed rollback path for the exact forward candidate.

drop function if exists programacion.record_learned_context_lineage_v1(text,text,text,text,text,text,jsonb);
drop trigger if exists trg_lf_lineage_append_only_v1 on programacion.learned_context_lineage;
drop function if exists programacion.lf_lineage_append_only_v1();
drop trigger if exists trg_lf_lineage_guard_v1 on programacion.learned_context_lineage;
drop function if exists programacion.lf_lineage_guard_v1();
drop function if exists programacion.lf_lineage_ref_resolves_v1(text,text);
drop table if exists programacion.learned_context_lineage;
