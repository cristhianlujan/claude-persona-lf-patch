# VISUAL_SOURCE_ANALYSIS

## Purpose

`VISUAL_SOURCE_ANALYSIS` is the candidate owner for reusable visual producer execution. It does **not** implement a second visual engine. It delegates to the existing historical P0 v4 analysis loop under `sandbox/story_creator_p0_visual/v1.1/scripts/`.

Its bounded responsibility is:

> Given a source and governed producer inputs, execute the existing visual analysis loop and expose its source-bound convergence receipt to a downstream evidence validator.

## Why this boundary exists

`VISUAL_EVIDENCE_GATE` v1 currently invokes producer regressions, Human Review, durable-state, integration/premerge and P0-5 checks. The evidence-only v2 candidate removes those responsibilities from the gate, but a producer owner must exist before any historical coverage is disconnected.

The existing engine is currently located under a Story Creator/P0 namespace. This candidate separates **logical ownership** from that historical physical location without moving, copying or renaming the engine.

## Reused engine

Existing engine entrypoint:

`sandbox/story_creator_p0_visual/v1.1/scripts/run_p0_visual_quality_loop_v4.py`

The engine already accepts the source, reader, remediation/reread callbacks, code/config identity and proof inputs. `visual_source_analysis_v1.py` calls that function lazily and returns only a non-persistent producer envelope.

## Ownership

| Responsibility | Owner |
|---|---|
| Visual source analysis / producer execution | `VISUAL_SOURCE_ANALYSIS` |
| Producer-side regression coverage | `VISUAL_SOURCE_ANALYSIS` |
| Applicability and path admission | Changeset Governance |
| Validate resulting evidence receipt | `VISUAL_EVIDENCE_GATE` |
| Human Review | Separate Human Review authority |
| Durable evidence persistence/readback | Evidence infrastructure |
| Premerge/release compliance | Release/governance owner |
| P0-5 benchmark annotation | P0-5 owner |
| Runtime/merge/production authorization | Explicit downstream authority |

## Historical coverage split

The mixed legacy bundle contains 24 commands:

- 19 producer/regression commands -> this owner candidate.
- 5 foreign commands -> remain outside this owner and are listed in `REGRESSION_OWNERSHIP_V1.md`.

No historical command is deleted, renamed or rewired in this lot.

## Fail-closed rules

- Historical engine missing/unloadable: block.
- Producer regression inventory not exactly 19 unique safe repository paths: block.
- Any Human Review, integration/premerge, durable-state or P0-5 command entering the producer inventory: block.
- Engine PASS without convergence receipt: block.
- Upstream producer non-PASS: return `BLOCKED` with no evidence receipt.
- This owner does not persist, authenticate humans, decide applicability or authorize production.

## Verification

```bash
python3 sandbox/lf_contract_gate_test/visual_source_analysis/test_visual_source_analysis_v1.py
```

The regression invokes the candidate `self_test()` and exercises PASS/BLOCK/missing-receipt boundaries through an injected engine runner. Default-engine loading remains separately verified against the historical source before any registration or carrier cutover.

`visual_source_analysis_v1.py` is a candidate source only. Registration, current-pointer changes, carrier wiring and activation are separate sequential lots.
