-- Canonical source recovered from Supabase migration ledger.
-- Live version: 20260916023642_prepare_assurance_method_and_profile_top_tier_v1
-- Recovery is source-parity only: this migration already exists live and MUST NOT be re-applied there.

create table if not exists public.lf_assurance_claim_catalog (
  claim_code text not null,
  version integer not null default 1 check (version > 0),
  parent_claim_code text null,
  parent_claim_version integer null,
  subject_type text not null check (subject_type in ('CONTROL_PLANE','WORKFLOW','OPERATION','STRATEGY','PROFILE','CARD','ADAPTER','SKILL','CAPABILITY')),
  subject_code text not null,
  claim_class text not null check (claim_class in ('FUNCTIONAL','AUTHORITY','CURRENTNESS','QUALIFICATION','SECURITY','EVIDENCE','DIAGNOSTIC','RECOVERY','STRUCTURAL_COVERAGE','COGNITIVE_QUALITY','TRANSVERSALIZATION','CLOSURE')),
  claim_text text not null,
  criticality text not null check (criticality in ('LOW','MEDIUM','HIGH','CRITICAL')),
  applicability jsonb not null default '{}'::jsonb,
  closure_rule jsonb not null default '{}'::jsonb,
  methodology_version text not null default 'LF_ASSURANCE_METHOD_V1',
  status text not null default 'CANDIDATO' check (status in ('CANDIDATO','ACTIVE','RETIRED')),
  source_ref text null,
  created_by_execution_id text null,
  created_at timestamptz not null default now(),
  primary key (claim_code, version),
  foreign key (parent_claim_code, parent_claim_version)
    references public.lf_assurance_claim_catalog(claim_code, version)
    on update restrict on delete restrict,
  check ((parent_claim_code is null and parent_claim_version is null) or (parent_claim_code is not null and parent_claim_version is not null))
);

create table if not exists public.lf_assurance_obligation_catalog (
  obligation_code text not null,
  version integer not null default 1 check (version > 0),
  claim_code text not null,
  claim_version integer not null default 1,
  requirement_ref text null,
  implementation_ref text null,
  condition_ref text null,
  verification_method text not null check (verification_method in ('INSPECTION','ANALYSIS','TEST','DEMONSTRATION','STRUCTURAL_COVERAGE','INDEPENDENT_REVIEW')),
  positive_test_ref text null,
  negative_test_ref text null,
  adversarial_test_ref text null,
  structural_coverage_mode text not null default 'NONE' check (structural_coverage_mode in ('NONE','BRANCH','CONDITION','MC_DC_LIKE')),
  evidence_contract jsonb not null default '{}'::jsonb,
  failure_taxonomy_code text null,
  required boolean not null default true,
  status text not null default 'CANDIDATO' check (status in ('CANDIDATO','ACTIVE','RETIRED')),
  source_ref text null,
  created_by_execution_id text null,
  created_at timestamptz not null default now(),
  primary key (obligation_code, version),
  foreign key (claim_code, claim_version)
    references public.lf_assurance_claim_catalog(claim_code, version)
    on update restrict on delete restrict
);

create table if not exists public.lf_assurance_defeater_catalog (
  defeater_code text not null,
  version integer not null default 1 check (version > 0),
  claim_code text not null,
  claim_version integer not null default 1,
  obligation_code text null,
  defeater_class text not null check (defeater_class in ('WRONG_EXECUTION','WRONG_OPERATION','WRONG_TARGET','WRONG_REVISION','STALE','REPLAY','SPOOF','BYPASS','CONCURRENCY','TOCTOU','EXPIRED_LEASE','HAPPY_PATH_ONLY','EVIDENCE_WEAK','EVIDENCE_NOT_DURABLE','EVIDENCE_NOT_INDEPENDENT','OBSERVABILITY_GAP','TRACEABILITY_BROKEN','CONDITION_COVERAGE_GAP','CLAIM_OVERREACH','GENERALIZATION_FAILURE','CAPABILITY_MISUSE','VAGUE_OUTPUT','UNSUPPORTED_CLAIM','SILENT_MATERIAL_GAP')),
  description text not null,
  required_counterevidence jsonb not null default '{}'::jsonb,
  zero_effect_required boolean not null default false,
  status text not null default 'CANDIDATO' check (status in ('CANDIDATO','ACTIVE','RETIRED')),
  source_ref text null,
  created_by_execution_id text null,
  created_at timestamptz not null default now(),
  primary key (defeater_code, version),
  foreign key (claim_code, claim_version)
    references public.lf_assurance_claim_catalog(claim_code, version)
    on update restrict on delete restrict
);

create table if not exists public.lf_assurance_subject_bindings (
  binding_code text primary key,
  subject_type text not null check (subject_type in ('WORKFLOW','OPERATION','STRATEGY','PROFILE','CARD','ADAPTER','SKILL','CAPABILITY')),
  subject_code text not null,
  standard_claim_code text not null,
  standard_claim_version integer not null default 1,
  benchmark_suite_code text null,
  activation_condition jsonb not null default '{}'::jsonb,
  required boolean not null default true,
  status text not null default 'CANDIDATO' check (status in ('CANDIDATO','ACTIVE','RETIRED')),
  source_ref text null,
  created_by_execution_id text null,
  created_at timestamptz not null default now(),
  foreign key (standard_claim_code, standard_claim_version)
    references public.lf_assurance_claim_catalog(claim_code, version)
    on update restrict on delete restrict,
  foreign key (benchmark_suite_code)
    references public.lf_test_suites(suite_code)
    on update cascade on delete restrict
);

create table if not exists public.lf_assurance_evaluations (
  evaluation_id uuid primary key default gen_random_uuid(),
  subject_type text not null check (subject_type in ('CONTROL_PLANE','WORKFLOW','OPERATION','STRATEGY','PROFILE','CARD','ADAPTER','SKILL','CAPABILITY')),
  subject_code text not null,
  subject_revision text null,
  claim_code text not null,
  claim_version integer not null default 1,
  obligation_code text null,
  execution_id text null,
  result text not null check (result in ('PASS','FAIL','OPEN','UNPROVEN','FALSE_PASS_RISK','NOT_APPLICABLE')),
  evidence_refs jsonb not null default '[]'::jsonb check (jsonb_typeof(evidence_refs)='array'),
  gate_check_refs jsonb not null default '[]'::jsonb check (jsonb_typeof(gate_check_refs)='array'),
  open_defeaters jsonb not null default '[]'::jsonb check (jsonb_typeof(open_defeaters)='array'),
  closed_defeaters jsonb not null default '[]'::jsonb check (jsonb_typeof(closed_defeaters)='array'),
  failure_type text null,
  evaluator_mode text not null check (evaluator_mode in ('DETERMINISTIC','INDEPENDENT_REVIEW','HYBRID')),
  rationale text null,
  created_by_execution_id text null,
  observed_at timestamptz not null default now(),
  foreign key (claim_code, claim_version)
    references public.lf_assurance_claim_catalog(claim_code, version)
    on update restrict on delete restrict
);

create or replace function public.lf_assurance_reject_mutation_v1()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
begin
  raise exception 'LF_ASSURANCE_APPEND_ONLY:%:%', tg_table_name, tg_op;
end;
$$;

revoke all on function public.lf_assurance_reject_mutation_v1() from public, anon, authenticated;
grant execute on function public.lf_assurance_reject_mutation_v1() to service_role;

drop trigger if exists trg_lf_assurance_claim_append_only on public.lf_assurance_claim_catalog;
create trigger trg_lf_assurance_claim_append_only before update or delete on public.lf_assurance_claim_catalog for each row execute function public.lf_assurance_reject_mutation_v1();
drop trigger if exists trg_lf_assurance_obligation_append_only on public.lf_assurance_obligation_catalog;
create trigger trg_lf_assurance_obligation_append_only before update or delete on public.lf_assurance_obligation_catalog for each row execute function public.lf_assurance_reject_mutation_v1();
drop trigger if exists trg_lf_assurance_defeater_append_only on public.lf_assurance_defeater_catalog;
create trigger trg_lf_assurance_defeater_append_only before update or delete on public.lf_assurance_defeater_catalog for each row execute function public.lf_assurance_reject_mutation_v1();
drop trigger if exists trg_lf_assurance_binding_append_only on public.lf_assurance_subject_bindings;
create trigger trg_lf_assurance_binding_append_only before update or delete on public.lf_assurance_subject_bindings for each row execute function public.lf_assurance_reject_mutation_v1();
drop trigger if exists trg_lf_assurance_evaluation_append_only on public.lf_assurance_evaluations;
create trigger trg_lf_assurance_evaluation_append_only before update or delete on public.lf_assurance_evaluations for each row execute function public.lf_assurance_reject_mutation_v1();

alter table public.lf_assurance_claim_catalog enable row level security;
alter table public.lf_assurance_obligation_catalog enable row level security;
alter table public.lf_assurance_defeater_catalog enable row level security;
alter table public.lf_assurance_subject_bindings enable row level security;
alter table public.lf_assurance_evaluations enable row level security;

revoke all on table public.lf_assurance_claim_catalog from public, anon, authenticated;
revoke all on table public.lf_assurance_obligation_catalog from public, anon, authenticated;
revoke all on table public.lf_assurance_defeater_catalog from public, anon, authenticated;
revoke all on table public.lf_assurance_subject_bindings from public, anon, authenticated;
revoke all on table public.lf_assurance_evaluations from public, anon, authenticated;

revoke all on table public.lf_assurance_claim_catalog from service_role;
revoke all on table public.lf_assurance_obligation_catalog from service_role;
revoke all on table public.lf_assurance_defeater_catalog from service_role;
revoke all on table public.lf_assurance_subject_bindings from service_role;
revoke all on table public.lf_assurance_evaluations from service_role;
grant select, insert on table public.lf_assurance_claim_catalog to service_role;
grant select, insert on table public.lf_assurance_obligation_catalog to service_role;
grant select, insert on table public.lf_assurance_defeater_catalog to service_role;
grant select, insert on table public.lf_assurance_subject_bindings to service_role;
grant select, insert on table public.lf_assurance_evaluations to service_role;

insert into public.lf_assurance_claim_catalog
(claim_code,version,parent_claim_code,parent_claim_version,subject_type,subject_code,claim_class,claim_text,criticality,applicability,closure_rule,status,source_ref)
values
('LF_ASSURANCE_METHOD_V1',1,null,null,'CONTROL_PLANE','*','CLOSURE','No material PASS is accepted unless every required subclaim is traced to implementation, tests and durable evidence and all mandatory defeaters are closed.','CRITICAL','{"scope":"all_material_controls"}'::jsonb,'{"pass_requires":["required_subclaims_pass","mandatory_defeaters_closed","no_open_false_pass_risk"],"open_blocks_parent_pass":true}'::jsonb,'CANDIDATO','USER_AUTHORIZED_ASSURANCE_DESIGN_20260915'),
('WF_DIAGNOSTIC_COMPLETE_V1',1,'LF_ASSURANCE_METHOD_V1',1,'WORKFLOW','validate-lf-packs','DIAGNOSTIC','A workflow failure is deterministically localizable and durably diagnosable down to failing test/check, assertion/error, expected/actual, source revision, owner and repair/resume input.','CRITICAL','{"canary":"validate-lf-packs","applies_when":"test_or_gate_executes"}'::jsonb,'{"required":["test_identity","assertion_or_error","expected_actual","durable_artifact","correlation","owner_repair_resume"]}'::jsonb,'CANDIDATO','github://.github/workflows/validate-lf-packs.yml'),
('STRATEGY_ROUTER_AUTHENTIC_V1',1,'LF_ASSURANCE_METHOD_V1',1,'OPERATION','EJECUCION_ESTRATEGIA_LF','AUTHORITY','No material Strategy effect can occur unless the route is authentic, current, execution-bound, operation-bound, target-bound, replay-resistant and independently verified.','CRITICAL','{"step_id":"router","effect_boundary":"before_material_effect"}'::jsonb,'{"required":["execution_binding","operation_binding","target_binding","revision_binding","producer_authority","freshness","replay_resistance","spoof_resistance","toctou_resistance","zero_effect_on_failure"]}'::jsonb,'CANDIDATO','supabase://EJECUCION_ESTRATEGIA_LF/router'),
('PROFILE_EXPERTISE_TOP_TIER_V1',1,'LF_ASSURANCE_METHOD_V1',1,'PROFILE','*','COGNITIVE_QUALITY','A Profile explicitly designated Top-Tier produces deep, evidence-grounded, non-vague, falsifiable, generalizable and actionable expert reasoning and uses the right capabilities rather than merely producing fluent output.','CRITICAL','{"activation":"EXPLICIT_PROFILE_BINDING_ONLY","not_for_all_profiles":true,"user_shorthand":"Harvard-level"}'::jsonb,'{"no_average_escape":true,"critical_dimensions_all_pass":true,"blind_holdout_required":true,"adversarial_wrong_capability_required":true,"generalization_required":true}'::jsonb,'CANDIDATO','LF_PROFILE_EXPERTISE_TOP_TIER_DESIGN_20260915'),
('PROFILE_TOP_TIER_DEPTH_V1',1,'PROFILE_EXPERTISE_TOP_TIER_V1',1,'PROFILE','*','COGNITIVE_QUALITY','Reasoning demonstrates causal depth and domain-specific mechanisms rather than generic recommendations.','HIGH','{"only_when_parent_applies":true}'::jsonb,'{"dimension_score_min":4,"scale_max":5,"generic_only_output":"FAIL"}'::jsonb,'CANDIDATO','LF_PROFILE_EXPERTISE_TOP_TIER_DESIGN_20260915'),
('PROFILE_TOP_TIER_EVIDENCE_V1',1,'PROFILE_EXPERTISE_TOP_TIER_V1',1,'PROFILE','*','COGNITIVE_QUALITY','Material claims are grounded in current evidence and unsupported major claims are absent.','CRITICAL','{"only_when_parent_applies":true}'::jsonb,'{"unsupported_major_claim_tolerance":0,"stale_material_evidence_tolerance":0}'::jsonb,'CANDIDATO','LF_PROFILE_EXPERTISE_TOP_TIER_DESIGN_20260915'),
('PROFILE_TOP_TIER_ALTERNATIVES_V1',1,'PROFILE_EXPERTISE_TOP_TIER_V1',1,'PROFILE','*','COGNITIVE_QUALITY','When multiple feasible choices exist, the Profile generates genuine alternatives and explicit trade-offs.','HIGH','{"only_when_multiple_feasible_choices":true}'::jsonb,'{"genuine_alternatives_min":2,"tradeoffs_required":true}'::jsonb,'CANDIDATO','LF_PROFILE_EXPERTISE_TOP_TIER_DESIGN_20260915'),
('PROFILE_TOP_TIER_FALSIFICATION_V1',1,'PROFILE_EXPERTISE_TOP_TIER_V1',1,'PROFILE','*','COGNITIVE_QUALITY','The Profile actively challenges its preferred answer, identifies counterevidence and states what would change the conclusion.','CRITICAL','{"only_when_parent_applies":true}'::jsonb,'{"counterexample_required":true,"change_mind_condition_required":true}'::jsonb,'CANDIDATO','LF_PROFILE_EXPERTISE_TOP_TIER_DESIGN_20260915'),
('PROFILE_TOP_TIER_SECOND_ORDER_V1',1,'PROFILE_EXPERTISE_TOP_TIER_V1',1,'PROFILE','*','COGNITIVE_QUALITY','Material second-order and downstream effects are evaluated.','HIGH','{"only_when_parent_applies":true}'::jsonb,'{"silent_material_downstream_gap_tolerance":0}'::jsonb,'CANDIDATO','LF_PROFILE_EXPERTISE_TOP_TIER_DESIGN_20260915'),
('PROFILE_TOP_TIER_ACTIONABILITY_V1',1,'PROFILE_EXPERTISE_TOP_TIER_V1',1,'PROFILE','*','COGNITIVE_QUALITY','Recommendations are executable: exact target, action, acceptance criteria, risks and regression/verification are specified when applicable.','HIGH','{"only_when_action_requested":true}'::jsonb,'{"target_required":true,"action_required":true,"acceptance_required":true}'::jsonb,'CANDIDATO','LF_PROFILE_EXPERTISE_TOP_TIER_DESIGN_20260915'),
('PROFILE_TOP_TIER_GENERALIZATION_V1',1,'PROFILE_EXPERTISE_TOP_TIER_V1',1,'PROFILE','*','COGNITIVE_QUALITY','Quality survives blind holdout and perturbation without memorizing benchmark-specific wording.','CRITICAL','{"only_when_parent_applies":true}'::jsonb,'{"blind_holdout_required":true,"perturbation_required":true}'::jsonb,'CANDIDATO','LF_PROFILE_EXPERTISE_TOP_TIER_DESIGN_20260915'),
('PROFILE_TOP_TIER_CAPABILITY_USE_V1',1,'PROFILE_EXPERTISE_TOP_TIER_V1',1,'PROFILE','*','COGNITIVE_QUALITY','Loaded capabilities are relevant and actually used; stale/wrong capabilities are rejected rather than silently influencing the answer.','CRITICAL','{"only_when_capabilities_loaded":true}'::jsonb,'{"loaded_but_unused_is_fail":true,"wrong_capability_rejection_required":true}'::jsonb,'CANDIDATO','LF_PROFILE_EXPERTISE_TOP_TIER_DESIGN_20260915'),
('PROFILE_TOP_TIER_GAP_DECLARATION_V1',1,'PROFILE_EXPERTISE_TOP_TIER_V1',1,'PROFILE','*','COGNITIVE_QUALITY','Material uncertainty and unresolved information gaps are declared explicitly; no silent material gap is permitted.','CRITICAL','{"only_when_parent_applies":true}'::jsonb,'{"silent_material_gap_tolerance":0}'::jsonb,'CANDIDATO','LF_PROFILE_EXPERTISE_TOP_TIER_DESIGN_20260915')
on conflict (claim_code,version) do nothing;

insert into public.lf_assurance_obligation_catalog
(obligation_code,version,claim_code,claim_version,requirement_ref,implementation_ref,condition_ref,verification_method,positive_test_ref,negative_test_ref,adversarial_test_ref,structural_coverage_mode,evidence_contract,failure_taxonomy_code,status,source_ref)
values
('WF-DIAG-TEST-IDENTITY-V1',1,'WF_DIAGNOSTIC_COMPLETE_V1',1,'failure identifies exact test/check','github://validate-lf-packs','test_failure => exact test identity','TEST','existing failing-test run','missing/ambiguous test identity','same RC from multiple tests','BRANCH','{"required_fields":["workflow_run_id","job_id","step","test_file","test_case_or_check_id","source_sha"]}'::jsonb,'OBSERVABILITY_GAP','CANDIDATO','LF_ASSURANCE_METHOD_V1'),
('WF-DIAG-ASSERTION-V1',1,'WF_DIAGNOSTIC_COMPLETE_V1',1,'failure identifies exact assertion/error','github://validate-lf-packs','test_failure => assertion/error + expected/actual','TEST','known assertion failure','assertion absent','stdout lost','CONDITION','{"required_fields":["error_class","assertion_or_error","expected","actual","rc"]}'::jsonb,'EVIDENCE_NOT_DURABLE','CANDIDATO','LF_ASSURANCE_METHOD_V1'),
('WF-DIAG-DURABLE-V1',1,'WF_DIAGNOSTIC_COMPLETE_V1',1,'failure evidence survives runner/log loss','github://actions artifact or LF_GATE_ERROR_V1','failure => durable artifact/row','DEMONSTRATION','artifact retrievable after run','ephemeral stdout/tmp only','artifact missing/expired without canonical copy','NONE','{"required":["durable_ref","retention_or_canonical_store","correlation"]}'::jsonb,'EVIDENCE_NOT_DURABLE','CANDIDATO','LF_ASSURANCE_METHOD_V1'),
('ROUTER-EXEC-BIND-V1',1,'STRATEGY_ROUTER_AUTHENTIC_V1',1,'route receipt belongs to this execution','supabase://router verifier','receipt.execution_id = execution.execution_id','TEST','same execution receipt','other execution receipt','replayed valid receipt','MC_DC_LIKE','{"expected_actual_required":true,"zero_effect_on_fail":true}'::jsonb,'TRACEABILITY_BROKEN','CANDIDATO','LF_ASSURANCE_METHOD_V1'),
('ROUTER-TARGET-BIND-V1',1,'STRATEGY_ROUTER_AUTHENTIC_V1',1,'route receipt belongs to exact target','supabase://router verifier','receipt.target = execution.target','TEST','same target','other target','target changes after route','MC_DC_LIKE','{"expected_actual_required":true,"zero_effect_on_fail":true}'::jsonb,'EVIDENCE_WEAK','CANDIDATO','LF_ASSURANCE_METHOD_V1'),
('ROUTER-OP-BIND-V1',1,'STRATEGY_ROUTER_AUTHENTIC_V1',1,'route receipt belongs to exact operation','supabase://router verifier','receipt.operation = execution.operation','TEST','same operation','other operation','valid receipt from other operation','MC_DC_LIKE','{"expected_actual_required":true,"zero_effect_on_fail":true}'::jsonb,'EVIDENCE_WEAK','CANDIDATO','LF_ASSURANCE_METHOD_V1'),
('ROUTER-FRESHNESS-V1',1,'STRATEGY_ROUTER_AUTHENTIC_V1',1,'route is current to material revision','supabase://router verifier','receipt.revision = current material revision','TEST','current receipt','stale receipt','TOCTOU revision change','MC_DC_LIKE','{"expected_actual_required":true,"zero_effect_on_fail":true}'::jsonb,'CURRENTNESS_GAP','CANDIDATO','LF_ASSURANCE_METHOD_V1'),
('ROUTER-REPLAY-V1',1,'STRATEGY_ROUTER_AUTHENTIC_V1',1,'route cannot be replayed outside bound context','supabase://router verifier','receipt fingerprint single-context','TEST','first valid use','second use other context','concurrent replay','CONDITION','{"idempotency_and_context_binding_required":true,"zero_effect_on_fail":true}'::jsonb,'REPLAY_GAP','CANDIDATO','LF_ASSURANCE_METHOD_V1'),
('ROUTER-ZERO-EFFECT-V1',1,'STRATEGY_ROUTER_AUTHENTIC_V1',1,'every invalid-route path has zero material effect','supabase://effect guard/readback','invalid route => before_state = after_state','DEMONSTRATION','valid route can proceed to later guarded stage','spoof/stale/wrong target all block','concurrent invalid route','NONE','{"before_after_readback_required":true}'::jsonb,'ASSURANCE_GAP','CANDIDATO','LF_ASSURANCE_METHOD_V1'),
('PROFILE-TOP-TIER-BENCHMARK-V1',1,'PROFILE_EXPERTISE_TOP_TIER_V1',1,'top-tier quality is measured on blind, adversarial and generalization cases','supabase://lf_test_suites/TS-PROFILE-EXPERTISE-TOP-TIER-V1','all critical dimensions pass; no average escape','INDEPENDENT_REVIEW','blind holdout passes','generic/vague answer fails','stale/wrong capability injection','NONE','{"critical_dimensions_all_pass":true,"score_scale":"0..5","dimension_min":4,"independent_review":true}'::jsonb,'COGNITIVE_QUALITY_GAP','CANDIDATO','LF_PROFILE_EXPERTISE_TOP_TIER_DESIGN_20260915')
on conflict (obligation_code,version) do nothing;

insert into public.lf_assurance_defeater_catalog
(defeater_code,version,claim_code,claim_version,obligation_code,defeater_class,description,required_counterevidence,zero_effect_required,status,source_ref)
values
('ROUTER-D-WRONG-EXEC-V1',1,'STRATEGY_ROUTER_AUTHENTIC_V1',1,'ROUTER-EXEC-BIND-V1','WRONG_EXECUTION','A valid receipt from another execution is accepted.','{"test":"other_execution_receipt_must_block"}'::jsonb,true,'CANDIDATO','LF_ASSURANCE_METHOD_V1'),
('ROUTER-D-WRONG-TARGET-V1',1,'STRATEGY_ROUTER_AUTHENTIC_V1',1,'ROUTER-TARGET-BIND-V1','WRONG_TARGET','A valid receipt for another Strategy target is accepted.','{"test":"other_target_receipt_must_block"}'::jsonb,true,'CANDIDATO','LF_ASSURANCE_METHOD_V1'),
('ROUTER-D-STALE-V1',1,'STRATEGY_ROUTER_AUTHENTIC_V1',1,'ROUTER-FRESHNESS-V1','STALE','A receipt bound to an old material revision is accepted.','{"test":"stale_revision_receipt_must_block"}'::jsonb,true,'CANDIDATO','LF_ASSURANCE_METHOD_V1'),
('ROUTER-D-REPLAY-V1',1,'STRATEGY_ROUTER_AUTHENTIC_V1',1,'ROUTER-REPLAY-V1','REPLAY','A receipt is replayed in a new context and accepted.','{"test":"cross_execution_replay_must_block"}'::jsonb,true,'CANDIDATO','LF_ASSURANCE_METHOD_V1'),
('ROUTER-D-SPOOF-V1',1,'STRATEGY_ROUTER_AUTHENTIC_V1',1,null,'SPOOF','Caller supplies plausible route fields/trust assertions without canonical Router production.','{"test":"caller_fabricated_route_must_block"}'::jsonb,true,'CANDIDATO','LF_ASSURANCE_METHOD_V1'),
('ROUTER-D-TOCTOU-V1',1,'STRATEGY_ROUTER_AUTHENTIC_V1',1,'ROUTER-FRESHNESS-V1','TOCTOU','Target/currentness changes after route validation but before material effect.','{"test":"change_after_route_before_effect_must_block"}'::jsonb,true,'CANDIDATO','LF_ASSURANCE_METHOD_V1'),
('WF-D-STDOUT-LOSS-V1',1,'WF_DIAGNOSTIC_COMPLETE_V1',1,'WF-DIAG-DURABLE-V1','EVIDENCE_NOT_DURABLE','Failure can only be reconstructed from ephemeral stdout.','{"test":"diagnostic_retrievable_without_job_log"}'::jsonb,false,'CANDIDATO','LF_ASSURANCE_METHOD_V1'),
('PROFILE-D-VAGUE-V1',1,'PROFILE_EXPERTISE_TOP_TIER_V1',1,'PROFILE-TOP-TIER-BENCHMARK-V1','VAGUE_OUTPUT','Output is fluent/correct but generic, shallow or non-executable.','{"required":"dimension depth/actionability hard fail"}'::jsonb,false,'CANDIDATO','LF_PROFILE_EXPERTISE_TOP_TIER_DESIGN_20260915'),
('PROFILE-D-WRONG-CAPABILITY-V1',1,'PROFILE_EXPERTISE_TOP_TIER_V1',1,'PROFILE-TOP-TIER-BENCHMARK-V1','CAPABILITY_MISUSE','Profile accepts stale/wrong capability and lets it influence the conclusion.','{"test":"wrong_capability_must_be_rejected_or_flagged"}'::jsonb,false,'CANDIDATO','LF_PROFILE_EXPERTISE_TOP_TIER_DESIGN_20260915'),
('PROFILE-D-GENERALIZATION-V1',1,'PROFILE_EXPERTISE_TOP_TIER_V1',1,'PROFILE-TOP-TIER-BENCHMARK-V1','GENERALIZATION_FAILURE','Profile performs on known examples but degrades on blind holdout/perturbation.','{"tests":["blind_holdout","post_update_perturbation"]}'::jsonb,false,'CANDIDATO','LF_PROFILE_EXPERTISE_TOP_TIER_DESIGN_20260915')
on conflict (defeater_code,version) do nothing;

insert into public.lf_test_suites
(suite_code,module_code,name,version,status,execution_policy,metadata,created_by_execution_id)
values
('TS-PROFILE-EXPERTISE-TOP-TIER-V1','PROFILE_QUALITY','Profile Expertise Top-Tier Benchmark','v1','CANDIDATO',
 '{"activation":"EXPLICIT_PROFILE_BINDING_ONLY","independent_review_required":true,"false_pass_tolerance":0,"critical_dimensions_all_pass":true,"dimension_scale":"0..5","dimension_min":4,"no_average_escape":true,"blind_holdout_required":true,"adversarial_required":true,"generalization_required":true}'::jsonb,
 '{"standard_claim":"PROFILE_EXPERTISE_TOP_TIER_V1","user_shorthand":"Harvard-level","not_global":true,"owner_model":"S22 composition + S25 benchmark + S36 independent assurance","enrichment_is_gap_driven":true}'::jsonb,
 'PREP-ASSURANCE-METHOD-20260915')
on conflict (suite_code) do nothing;

insert into public.lf_test_suite_cases
(suite_code,test_code,test_order,title,test_type,execution_mode,severity,preconditions,input_payload,expected_output,prohibited_output,status,metadata,created_by_execution_id)
values
('TS-PROFILE-EXPERTISE-TOP-TIER-V1','PQT-DEPTH-001',10,'Ambiguous expert problem requires causal depth','SEMANTIC','INDEPENDENT_REVIEW','CRITICAL','[{"profile_binding":"explicit_top_tier"}]'::jsonb,'{"case_family":"AMBIGUOUS_EVIDENCE","instruction":"solve without generic checklist"}'::jsonb,'{"dimension":"DEPTH","min_score":4,"must_include":["causal_mechanism","domain_specific_reasoning"]}'::jsonb,'{"forbid":["generic_only","surface_restatement"]}'::jsonb,'CANDIDATO','{"critical":true,"enrichment_action":"strengthen domain rules/research-to-rules and causal reasoning examples"}'::jsonb,'PREP-ASSURANCE-METHOD-20260915'),
('TS-PROFILE-EXPERTISE-TOP-TIER-V1','PQT-EVIDENCE-002',20,'Material claims require current evidence','SEMANTIC','INDEPENDENT_REVIEW','CRITICAL','[{"profile_binding":"explicit_top_tier"}]'::jsonb,'{"case_family":"EVIDENCE_CHALLENGE"}'::jsonb,'{"dimension":"EVIDENCE","unsupported_major_claim_tolerance":0,"stale_material_evidence_tolerance":0}'::jsonb,'{"forbid":["unsupported_major_claim","stale_material_claim"]}'::jsonb,'CANDIDATO','{"critical":true,"enrichment_action":"improve research adapter/freshness policy/evidence grounding"}'::jsonb,'PREP-ASSURANCE-METHOD-20260915'),
('TS-PROFILE-EXPERTISE-TOP-TIER-V1','PQT-ALTERNATIVES-003',30,'Conflicting objectives require alternatives and trade-offs','SEMANTIC','INDEPENDENT_REVIEW','HIGH','[{"multiple_feasible_choices":true}]'::jsonb,'{"case_family":"CONFLICTING_OBJECTIVES"}'::jsonb,'{"dimension":"ALTERNATIVES_TRADEOFFS","genuine_alternatives_min":2,"tradeoffs_required":true}'::jsonb,'{"forbid":["single_option_without_tradeoff"]}'::jsonb,'CANDIDATO','{"critical":true,"enrichment_action":"add alternative generation/contrarian capability rather than more prose"}'::jsonb,'PREP-ASSURANCE-METHOD-20260915'),
('TS-PROFILE-EXPERTISE-TOP-TIER-V1','PQT-FALSIFY-004',40,'Preferred answer must survive adversarial falsification','ADVERSARIAL','INDEPENDENT_REVIEW','CRITICAL','[{"profile_binding":"explicit_top_tier"}]'::jsonb,'{"case_family":"ADVERSARIAL_COUNTEREVIDENCE"}'::jsonb,'{"dimension":"FALSIFICATION","must_include":["counterevidence","change_mind_condition"]}'::jsonb,'{"forbid":["unfalsifiable_confidence"]}'::jsonb,'CANDIDATO','{"critical":true,"enrichment_action":"add adversarial review/falsification capability"}'::jsonb,'PREP-ASSURANCE-METHOD-20260915'),
('TS-PROFILE-EXPERTISE-TOP-TIER-V1','PQT-SECOND-ORDER-005',50,'Second-order effects must be surfaced','SEMANTIC','INDEPENDENT_REVIEW','HIGH','[{"material_downstream_effects_possible":true}]'::jsonb,'{"case_family":"SECOND_ORDER_EFFECTS"}'::jsonb,'{"dimension":"SECOND_ORDER","silent_material_gap_tolerance":0}'::jsonb,'{"forbid":["first_order_only"]}'::jsonb,'CANDIDATO','{"critical":true,"enrichment_action":"add second-order-effects capability/card"}'::jsonb,'PREP-ASSURANCE-METHOD-20260915'),
('TS-PROFILE-EXPERTISE-TOP-TIER-V1','PQT-ACTION-006',60,'Expert output must be executable','SEMANTIC','INDEPENDENT_REVIEW','HIGH','[{"action_requested":true}]'::jsonb,'{"case_family":"ACTIONABILITY"}'::jsonb,'{"dimension":"ACTIONABILITY","must_include":["exact_target","action","acceptance_criteria","risks"]}'::jsonb,'{"forbid":["vague_next_steps"]}'::jsonb,'CANDIDATO','{"critical":true,"enrichment_action":"tighten output/decision contract before adding knowledge"}'::jsonb,'PREP-ASSURANCE-METHOD-20260915'),
('TS-PROFILE-EXPERTISE-TOP-TIER-V1','PQT-HOLDOUT-007',70,'Blind holdout preserves expert quality','QUALIFICATION','INDEPENDENT_REVIEW','CRITICAL','[{"benchmark_case_unseen":true}]'::jsonb,'{"case_family":"BLIND_HOLDOUT"}'::jsonb,'{"dimension":"GENERALIZATION","min_score":4,"memorization_signal":false}'::jsonb,'{"forbid":["benchmark_phrase_copy","case_specific_memorization"]}'::jsonb,'CANDIDATO','{"critical":true,"enrichment_action":"expand underlying rules/capabilities, not benchmark examples"}'::jsonb,'PREP-ASSURANCE-METHOD-20260915'),
('TS-PROFILE-EXPERTISE-TOP-TIER-V1','PQT-PERTURB-008',80,'Perturbation/generalization after update','QUALIFICATION','INDEPENDENT_REVIEW','CRITICAL','[{"base_case_passed":true}]'::jsonb,'{"case_family":"PERTURBATION_GENERALIZATION"}'::jsonb,'{"dimension":"GENERALIZATION","min_score":4,"consistency_required":true}'::jsonb,'{"forbid":["collapse_on_surface_change"]}'::jsonb,'CANDIDATO','{"critical":true,"enrichment_action":"repair causal abstraction/generalization rather than add narrow exception"}'::jsonb,'PREP-ASSURANCE-METHOD-20260915'),
('TS-PROFILE-EXPERTISE-TOP-TIER-V1','PQT-CAPABILITY-009',90,'Wrong/stale capability is rejected and relevant capabilities are actually used','ADVERSARIAL','INDEPENDENT_REVIEW','CRITICAL','[{"capability_composition_present":true}]'::jsonb,'{"case_family":"WRONG_STALE_CAPABILITY"}'::jsonb,'{"dimension":"CAPABILITY_USE","wrong_capability_rejected":true,"loaded_but_unused_tolerance":0}'::jsonb,'{"forbid":["silent_wrong_capability_use","loaded_but_unused"]}'::jsonb,'CANDIDATO','{"critical":true,"enrichment_action":"fix capability selection/composition before adding new profile knowledge"}'::jsonb,'PREP-ASSURANCE-METHOD-20260915'),
('TS-PROFILE-EXPERTISE-TOP-TIER-V1','PQT-GAPS-010',100,'Material uncertainty and gaps are declared','ADVERSARIAL','INDEPENDENT_REVIEW','CRITICAL','[{"material_information_gap_present":true}]'::jsonb,'{"case_family":"MISSING_INFORMATION"}'::jsonb,'{"dimension":"GAP_DECLARATION","silent_material_gap_tolerance":0}'::jsonb,'{"forbid":["fabricated_certainty","silent_material_gap"]}'::jsonb,'CANDIDATO','{"critical":true,"enrichment_action":"improve uncertainty/gap declaration policy; request evidence only when material"}'::jsonb,'PREP-ASSURANCE-METHOD-20260915')
on conflict (suite_code,test_code) do nothing;
