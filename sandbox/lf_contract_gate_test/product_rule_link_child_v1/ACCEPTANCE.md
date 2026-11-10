# LF #3774 — RULE_LINK_APPLY | exact-source acceptance gate

**Status:** CANDIDATE / NOT_TESTED end-to-end. Source patch only, no production deployment.

## Scope
- Reuses existing `RULE_LINK_APPLY` -> `VINCULACION_REGLA_PANTALLA_LF`.
- Parent `PERFIL-PRODUCT-DIRECTOR-LF` stays `EJECUCION_PERFIL_LF` read-only.
- Child owns only `lf_ops.reglas_pantallas` relation insert, through `lf_regla_pantalla_link_v1`.
- No Router changes, no new profile, no new skill, no state/permission/policy promotion.
- Only a source rule `VIGENTE`, `pendiente_decision=false`, can pass this **Product-owned entrypoint**. The canonical relation operation remains unchanged.

## Required Product output and call
After the **same** parent RUN records `execute_profile`, `output_validate`, and `semantic_judge`, with genuine evidence, the output's `deliverable_created` may carry:

```json
{
  "governed_rule_link": {
    "change_kind": "LINK_EXISTING_RULE",
    "rule_code": "<EXISTING_VIGENTE_RULE_CODE>",
    "screen_code": "<CURRENT_SELECTED_SCREEN_CODE>"
  }
}
```

This object must be exactly equal to `p_input.link_intent`; `p_input.decision_id` must equal `product_decision.decision_id`. Current `product_decision.source_refs` must name **the exact** canonical rule and screen:
- `supabase://lf_ops.reglas/<RULE_CODE>`
- `supabase://lf_ops.pantallas/<SCREEN_ID>`

The invoker request also requires `regla_codigo`, `pantalla_id`, `target_type=REGLA_PANTALLA_RELATION`, `target_code=<RULE_CODE>@<SCREEN_ID>`, and an exact `analysis_snapshot_sha256` of the current rule. A self-asserted output is not a router or profile authority receipt.

## POSITIVE cases (must be **executed** in isolated PG17, not assumed)
1. New exact link from an approved VIGENTE rule; same parent, matched decision, output validation, semantic judge; `lf_skill_invoke_v1('RULE_LINK_APPLY', ...)` must record **one** child `COMPLETED`, **five** distinct `PASS_CLEAN` steps and **one** link. Verify `effect_verified=true` and child receipt `APPLIED_VERIFIED`.
2. An already existing exact link must return the canonical `RULE_SCREEN_RELATION_ALREADY_EXISTS` result with one relation, and not change the rule/screen.
3. Exact replay (same parent+skill+input SHA) must reuse the same child, not create duplicates, and must re-read the canonical relation before claiming effect.
4. `BEGIN; ... ROLLBACK;` must restore all child steps and relations and leave no residue.

## NEGATIVE cases (must fail closed **without** a durable child effect)
- Wrong profile or profile-operation authority removed.
- No Router profile-execution receipt, incorrect original request SHA, or completed/stale parent.
- Different screen than the *server-selected* parent screen, changed source snapshot, wrong `target_code`.
- CANDIDATO, pending decision, unknown or missing rule.
- Invalid `input_validate` applicability/source, missing or forged `governed_rule_link`; unchanged semantic proposal with unrelated target.
- Missing `output_validate`, semantic `FAIL/BLOCKED`, unsupported claims, or mismatched judge/output SHA.
- Missing exact authoritative rule/screen source refs.
- Broken operation/contract/judge, changed canonical link helper hash, duplicate replay history, or shifted rule after link.
- Attempt to promote VIGENTE, edit rule/policy/screen, delete link, or activate runtime.

## Gates before production
1. Frozen source readback: current live hashes and both invoker patch anchors checked.
2. SQL parse and apply in isolated PostgreSQL 17 with current canonical schema. Record PostgreSQL execution receipt and exact 5-step results.
3. Negative tests above + rollback and zero residue.
4. Frozen HEAD / merge-train contract + required CI; compare Supabase schema/function/ACL readback and source parity.
5. No automatic production effect before an explicitly authorized controlled rollout.

**Known unclosed item:** `RULE_CREATE_APPLY` remains `READY` with no opener, pending separate implementation in #3774; do not mark task 4 done. Promotion to VIGENTE is likewise outside this patch.
