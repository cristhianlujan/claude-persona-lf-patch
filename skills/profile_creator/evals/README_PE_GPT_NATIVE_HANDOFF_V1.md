# Profile Evolution — GPT-native governed handoff V1

**Status:** `CANDIDATE_TEST_ONLY` · PR #2089 · no authority activation.

This lot replaces the earlier **Llama execution path for future Profile Evolution work** with LF's existing `GPT_NATIVE` runtime lane. Earlier Llama trials and negative judge-calibration evidence remain historical only; they do not qualify the updater.

## Canonical components reused

- `profile_execution_contract.py`: `build_execution_contract` and validation with `executor_mode=GPT_NATIVE`.
- `validate_profile_execution.py`: canonical execution-receipt structure, source/input/RAW hashes and provenance checks.
- `semantic_obligation_manifest.py`: prebound, complete enumeration of the **five obligations scoped to this specific synthetic calibration**; **not a claim of complete Profile Updater expertise coverage**.
- `GPT_RUNTIME_WITH_SUPABASE_CONTEXT`: declared canonical resolver boundary. Its **observed runtime binding still requires an execution receipt**.
- `profiles/quality_pack/contracts/independent_chat_semantic_review_contract.md` and `validate_semantic_quality.py`: existing independent-review path. Distinct clean context and real reviewer competence/receipt must be demonstrated. No separate provider model is required by this mode.

## Tested preparation

```bash
python3 skills/profile_creator/evals/test_profile_evolution_gpt_native_handoff_v1.py
python3 skills/profile_creator/evals/prepare_profile_evolution_gpt_native_v1.py --check-placeholder-receipt --output /tmp/pe-gpt-native-handoff.json
```

The generated handoff includes 12 contract-bound runs for four **previously seen synthetic cases**, each in D1 static / D2 selector-only / D3 typed-method condition. For D3 the method output is labelled **candidate, test-only, not admitted**. For D2 no method is executed. All responses are `PENDING_GPT_NATIVE_EXECUTION`, reviewer results `PENDING_INDEPENDENT_CHAT_CONTEXT`; **zero GPT model calls** have occurred in this lot.

## Pending actual execution

1. Have the existing governed GPT-native executor consume these precise source/contract/input references; it must return authentic model output, runtime attestation and `PROFILE_EXECUTION_RECEIPT_V1` with independent verifier evidence. A Python script or JSON field cannot impersonate that receipt.
2. Derive a complete check bundle from the prebound scoped manifest and actual RAW. Resolve deterministic controls before sending genuinely semantic questions to the clean independent review context. Do not give its producer conversation, target scores or expected verdicts.
3. Bind Quality Pack review to the producer's exact manifest/RAW/receipts and run `validate_semantic_quality.py`; only then consider status changes for the scoped calibration.
4. Prior to any broader expertise admission, enumerate all required profile obligations; freeze a **new, independent, sufficiently powered** D1/D2/D3 benchmark and ensure comparable budgets/cost receipts.

**No merge, cutover, production activation, method admission, paid inference, or semantic PASS is authorized by this candidate.**

## Follow-on: blinded causal review and exact materialized producer bundle

- Exact materialized twelve-run producer handoff:
  `skills/profile_creator/evals/results/pe_gpt_native_12_run_handoff_v1.json`,
  SHA-256 `2accf05d47739560556c2fd36e0cd08ad9c976b0974f6e6f77f6cc94ef12c11a`.
- Domain-specific causal review rubric:
  `skills/profile_creator/contracts/profile_evolution_causal_semantic_review_v1.md`.
  The existing Quality Pack 25-point visual rubric must **not** be interpreted
  as sufficient causal expertise or semantic accuracy.
- Generic review handoff:
  `skills/profile_creator/evals/prepare_profile_evolution_gpt_review_v1.py`.
  Only after independently verified native runtime execution can it produce a
  reviewer-facing view, stripped of D1/D2/D3 arm, expected verdict and method
  target answer. The producer binding remains in a separate private envelope.
- Fail-closed review-handoff tests:
  `skills/profile_creator/evals/test_profile_evolution_gpt_review_handoff_v1.py`.
  Explicitly synthetic positive does **not** represent a native GPT model run.
- Both native and review transport tests reproduced from clean checkout of
  PR branch at commit `891f5a35b51e9dae760d300ae30243c758bfae45`,
  with no worktree drift.

**Executor state remains PENDING.** No model output is invented, no Llama
execution, no admitted semantic judge, no 12-run statistical result. The existing
GPT runtime is an operational boundary, not a callable model dispatcher made
available to this sandbox Python process. A genuine native dispatch and
independent context remain necessary to produce the next receipts.
