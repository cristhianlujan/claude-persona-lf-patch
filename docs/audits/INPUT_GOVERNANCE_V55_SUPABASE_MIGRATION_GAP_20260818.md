# Input Governance v5.5 — Supabase → GitHub migration gap

Source checked: `supabase_migrations.schema_migrations` in Supabase project `mhwmirqcgxxukpctffuv`.

This file records the exact migration registry entries that are relevant to the Input Governance Agent and its directly required source normalizations. At audit-branch creation these migration files were present in Supabase but were not found on GitHub `main` by exact migration/function/version search.

## Missing-from-main migration registry

| Version | Migration |
|---|---|
| 20260818060403 | programacion_input_governance_agent_v01 |
| 20260818060526 | programacion_input_governance_insert_separation_hardening |
| 20260818060700 | programacion_input_governance_allow_unresolved_severity |
| 20260818063651 | programacion_input_governance_aud_iga_001_003_hardening_v2_retry |
| 20260818063906 | programacion_input_governance_v2_security_definer_acl_hardening |
| 20260818071617 | programacion_input_governance_v3_specialized_freshness_semantic_assertions |
| 20260818071756 | programacion_input_governance_v3_assessment_insert_guard |
| 20260818073604 | programacion_input_governance_assertion_relevance_v31 |
| 20260818073943 | programacion_input_governance_context_relevance_v32 |
| 20260818074628 | programacion_input_governance_generic_screen_graph_v4 |
| 20260818075054 | programacion_input_governance_empty_collections_and_not_contains_v41 |
| 20260818075147 | programacion_input_governance_rule_messages_v42 |
| 20260818075249 | programacion_input_governance_relevance_generalization_v43 |
| 20260818081742 | input_governance_v44_cross_source_relevance |
| 20260818165722 | input_governance_v50_design_binding_resolver |
| 20260818170211 | input_governance_v50_contract4_guards_and_design_gate |
| 20260818170542 | normalize_auth_email_otp_legacy_references |
| 20260818171534 | normalize_auth004_email_otp_field_binding |
| 20260818172016 | input_governance_v51_applicability_status_invariants |
| 20260818172705 | input_governance_v52_semantic_component_sufficiency |
| 20260818172751 | input_governance_v52_manifest_label_and_version_guard |
| 20260818172958 | normalize_legacy_totp_trace_contract |
| 20260818174137 | input_governance_v53_applicability_source_grounding |
| 20260818175441 | input_governance_v54_api_contract_sufficiency |
| 20260818180652 | input_governance_v54_context_manifest_projection |
| 20260818180951 | programacion_source_rule_authority_multi_source |
| 20260818181314 | input_governance_v54_selective_freshness_delta |
| 20260818181519 | input_governance_v54_jit_handle_resolver |
| 20260818181732 | input_governance_v55_deterministic_stage_hierarchy |
| 20260818182132 | input_governance_v55_context_stage_summary_and_module_health |
| 20260818185139 | input_governance_v55_current_lineage_guard |
| 20260818185300 | input_governance_v55_freshness_lineage_semantics |

## Important

The SQL text itself is recoverable from the authoritative migration registry:

```sql
select version,name,statements,rollback
from supabase_migrations.schema_migrations
where version = '<version>';
```

For audit purposes, Claude should compare the live objects and migration registry against any GitHub export rather than assuming filename parity proves equivalence.

## GitHub baseline observed

Repository: `cristhianlujan/claude-persona-lf-patch`

Observed main HEAD during this check: `265f09201a091c7dac56643c393f6bd19f283417` (`Merge PR #176: classify rejected same-family OCR evidence`), timestamp `2026-08-18T02:54:58Z`.

The Input Governance migrations listed above were applied later in Supabase on 2026-08-18, so GitHub main could not be treated as a complete mirror of this work at the time of the check.

## Audit consequence

- **Supabase direct audit:** sufficient to inspect the operational candidate.
- **GitHub-only audit:** insufficient until migration SQL is synchronized.
- **Cross-source reproducibility audit:** should fail/flag `GITHUB_SUPABASE_SYNC_INCOMPLETE` until the SQL export is committed and compared.
