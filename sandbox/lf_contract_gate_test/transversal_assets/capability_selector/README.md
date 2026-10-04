# CAPABILITY_SELECTOR v1.0.0

Transversal, domain-agnostic capability selector extracted from the M5.4 design direction and benchmark architecture anchored at `event://20170` / transversalization `event://20265`.

## Contract

Input is exactly three arguments:

- `signals`: typed signal records `{type, value, status?}`. Optional confidence metadata is tolerated but does not grant authority.
- `catalog`: data mapping typed signal/value matches to capability codes, with optional rank and availability state.
- `policy`: consumer-owned policy. `fallback_capabilities` is mandatory; other consumer metadata is opaque to the selector.

Output has exactly three keys:

- `selected_capabilities`
- `reasons`
- `fallback_state`

`fallback_state` is deterministically one of `CLEAR`, `MULTI`, `NO_SIGNAL`, `CONTRADICTORY`, `CAPABILITY_FAILURE`.

## Safety boundary

- Multi-label selection is allowed.
- Matching is driven only by typed signals and catalog data.
- `NO_SIGNAL`, `CONTRADICTORY`, and `CAPABILITY_FAILURE` return the fallback configured by the consumer.
- Rank affects deterministic ordering only. Confidence is not used to authorize anything.
- This capability performs selection only. Admission/permission remains a separate responsibility; it does not implement `SAFE_CHANGE_ADMISSION` rules such as authority, materiality, or reversibility.
- Provider source contains no IG, screen, family, model, method, or consumer-specific routing branch.

## Consumers proved by the same contract

- `non_ig_consumer_fixture_v1.json`: document-pipeline fixture, intentionally non-IG.
- `ig_consumer_binding_v1.json`: M5.4 consumer policy. It references `TYPED_EVIDENCE_REGISTRY`, `CURRENTNESS_AUTHORITY`, and the benchmark fallback `FULL_SAFE_MIX_V1_CANDIDATE`; none of those names are embedded in provider branching.

## Qualification

Run:

```bash
python sandbox/lf_contract_gate_test/transversal_assets/capability_selector/test_capability_selector_v1.py
```

Expected terminal line:

`PASS_CAPABILITY_SELECTOR_V1 checks=17 states=5 consumers=2 domain_branches=0`

The capability is repository-bound and has no active IG runtime cutover in T-SELECT. Therefore R17 is not triggered by this unit; R16 Git-first applies to registration/current promotion.
