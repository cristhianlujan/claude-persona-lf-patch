# Score Rubric — LF Profile Creator

## PRODUCER ACCEPTANCE

- Router/source authority is explicit and conflicts are not silently resolved.
- Supplied material context is reused rather than re-asked.
- The created candidate is exact and resolvable.
- The candidate defines an executable worker trajectory and failure behavior, not just a populated package.
- `skills/profile_creator/validators/validate_candidate_readiness.py` passes on the exact artifact.
- Producer-depth and cross-artifact-consistency component gates both PASS.
- The output discriminator is closed but not hardcoded to the field name `status`.
- SKILL/contract, schema, examples, eval expected outputs, rubric, mini-judge and handoff are mutually consistent.
- A profile-local executable `validators/validate_pack.py` exists and is declared in the manifest.
- Positive, negative, adversarial and Router/direct equivalence eval coverage contains observable assertions.
- When score taxonomy exists, schema criteria and evidence-by-criterion match the rubric.
- Adapters, when present, are profile-bound invocation contracts with caller, trigger, compact context and failure return; they are not alternate standalone workers.
- User-facing candidates protect internal orchestration metadata.
- Fixture/deterministic evidence is not mislabeled as RAW behavioral execution.
- Runtime and automatic impact remain blocked as governed.

## RETURN_TO_WORKER

- A required worker behavior, contract, schema, judge, validator, eval, evidence or handoff component is missing or nominal.
- Output modes/discriminators disagree across schema, examples or eval expectations.
- Rubric/score taxonomy is stale relative to the schema.
- Router/direct material-equivalence coverage is absent.
- An adapter lacks governed caller/trigger/context/failure binding.
- The aggregate readiness gate was not executed against the exact deliverable.

## BLOCK

- Authority is contradictory and a value is selected anyway.
- Evidence is fabricated or only asserted generically.
- A domain-specific reference profile is copied as universal authority.
- Internal metadata leaks into a declared user-facing payload.
- Runtime, production, VALIDATED status or automatic impact is enabled by producer assertion.
- Deterministic fixtures/validators are presented as independent semantic or behavioral PASS.
- Router/profile governance is bypassed through direct unbound adapter invocation.

`DEPTH_READY_FOR_SEMANTIC_REVIEW` is a deterministic readiness ceiling. Independent semantic Quality Pack review remains required, and behavioral PASS additionally requires separate RAW execution evidence.
