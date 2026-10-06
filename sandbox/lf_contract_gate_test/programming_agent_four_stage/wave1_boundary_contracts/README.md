# Programming Agent Wave 1 boundary contracts

Source-only candidate for the complete Wave 1: `A1–A4`, `PG-01`, and `TST-01–TST-05`.

- **A1 / Analysis intake** produces `REQUEST_CONTEXT_V1` without Story, Functional Version, Agent Task, or solution inference.
- **A2 / Change classification** makes change type + `L1/L2/L3` reproducible and resolves specialist requirements/refs dynamically through `CAPABILITY_SELECTOR@CURRENT`; selection is not execution permission.
- **A3 / Targeted evidence** reuses current evidence first, queries only missing/material evidence, blocks duplicate/full-repository discovery without a trigger, and stops at minimum sufficient context.
- **A3 / Existing-target invariant** resolves a hinted target as `EXISTING | NEW | UNKNOWN`. An existing target must be bound to its exact current identity/revision plus AS-IS authorities, implementation, consumers and dependencies before downstream requirements are assembled. A new target requires negative evidence that no compatible canonical asset already exists. `UNKNOWN` cannot silently become greenfield.
- **A4 + TST-05 / Shared impact** consume one transversalized `SHARED_CHANGE_IMPACT_ANALYSIS` core from the existing inventory/dependency surfaces; Testing adds only a test-specific projection. No parallel impact engine is allowed.
- **PG-01 / Programming** consumes `ANALYSIS_IMPLEMENTATION_PACKAGE_V1`; existing Agent Task runtime is extended at the entry boundary rather than duplicated. For an existing target, Programming admission requires an explicit delta against the frozen AS-IS baseline; greenfield redefinition is forbidden.
- **PG-03 ownership** remains the place where the implementation strategy is selected from evidence. The Analysis boundary identifies the target and delta but does not preselect how the LLM/programmer must implement it.
- **TST-01 / Testing admission** supports `DESIGN_ONLY` without a candidate and `EXECUTION` with an exact frozen candidate. Neither mode requires Story identity.
- **TST-02–TST-04 / Testing design pipeline** makes change signals, risks/criticality, and quality objectives explicit and evidence-traceable using the current test-characteristic catalog and existing selectors/admission surfaces.

Brownfield invariant:

```text
REQUEST
  -> RESOLVE EXACT TARGET
  -> EXISTING | NEW | UNKNOWN

EXISTING
  -> freeze current AS-IS evidence
  -> derive requested DELTA only
  -> Programming selects how to implement that delta

NEW
  -> requires bounded negative evidence that no compatible canonical asset exists

UNKNOWN
  -> NEED_MORE_EVIDENCE or REQUIRES_DECISION
  -> never silently becomes a new build
```

Governance:
- `REUSE_OR_TRANSVERSALIZE_BEFORE_BUILD`.
- Existing consumers stay as adapters until qualified cutover.
- Existing assets must not be re-specified as greenfield merely because the request describes their desired behavior.
- Technical implementation strategy remains dynamic and is owned by Programming, not hardcoded by Analysis.
- No runtime or production activation, current-pointer changes, or Story Creator retirement in this PR.
- Existing unit dependencies remain authoritative.

Evidence: `lf_eventos://20315`, `lf_eventos://20333`, `lf_eventos://20334`, `lf_eventos://20335`.

Run:

```bash
python sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/validate_wave1_boundary_contracts_v1.py --self-test
```
