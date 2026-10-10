# PE Orchestration Stress V1 — evidence-only

Status: SELECTOR_FIXTURE_PASS, E2E_BLOCKED.

R3 is a static local-domain four-choice decision benchmark. It does not demonstrate adaptive method execution, nor estimate selector overhead.

- Registry V2: 12 methods, 8 selectable, 4 experimental; execution_permission=false; no per-method runtime binding.
- Selector V3: verified preconditions, typed-signal selection, budget and evidence-bound replan; execution_authorized=false.
- Evolution planner calls the selector but does not dispatch methods. R3 D uses baseline instructions plus a domain addendum.

Run isolated selector probes:

```sh
python3 skills/profile_creator/evals/test_profile_orchestration_stress_v1.py
python3 skills/profile_creator/evals/test_profile_orchestration_stress_v1.py --require-live
```

First command: 12/12 selector fixtures pass, without method execution. Second command: expected exit 3 until live method execution exists. Synthetic evidence references are not live receipts.

The evaluator-only JSON contains eight disruptive tasks: causal contradictions, source authority conflicts, arithmetic, statistical inference, replan on failure, semantic gates, cost budget, and a no-method negative control. Do not expose evaluator expectations to the producer.

Next missing link: typed method execution contracts and invocable handlers; selection/invocation/verification receipts; real replan loop; numerical verification adapters; sealed new holdout, matched resources, independent scoring and assurance.

No production or cutover activation.
