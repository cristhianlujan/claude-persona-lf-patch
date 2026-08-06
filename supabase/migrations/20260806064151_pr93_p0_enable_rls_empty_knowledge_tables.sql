-- PR93 P0: enable deny-by-default RLS on empty public knowledge tables.
-- Applied first to LF_SUPABASE_SANDBOX as migration
-- pr93_p0_enable_rls_empty_knowledge_tables.

begin;

alter table public.lf_error_knowledge enable row level security;
alter table public.lf_prevention_rules enable row level security;
alter table public.lf_best_practices enable row level security;
alter table public.lf_decision_log enable row level security;

revoke all privileges on table public.lf_error_knowledge from anon, authenticated;
revoke all privileges on table public.lf_prevention_rules from anon, authenticated;
revoke all privileges on table public.lf_best_practices from anon, authenticated;
revoke all privileges on table public.lf_decision_log from anon, authenticated;

comment on table public.lf_error_knowledge is
  'PR93 P0: RLS deny-by-default intentional; no anon/authenticated policy. Administrative access only.';
comment on table public.lf_prevention_rules is
  'PR93 P0: RLS deny-by-default intentional; no anon/authenticated policy. Administrative access only.';
comment on table public.lf_best_practices is
  'PR93 P0: RLS deny-by-default intentional; no anon/authenticated policy. Administrative access only.';
comment on table public.lf_decision_log is
  'PR93 P0: RLS deny-by-default intentional; no anon/authenticated policy. Administrative access only.';

commit;
