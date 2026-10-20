# RW1-01_C3 — Blind Judge Handoff V3

## Purpose

Independently test the structured acceptance V3 after the newer round-3 challenge. This is a local acceptance-contract review only; it does not certify Router runtime or production.

## Freeze first

Freeze exact `main` and blob SHA for:

1. `docs/programming-agent/router_wave/RW1_01_C3_NEEDS_ACCEPTANCE_CORPUS_V2.json`
2. `sandbox/lf_contract_gate_test/router_wave/validate_rw101_needs_corpus_v2.py`
3. `sandbox/lf_contract_gate_test/router_wave/validate_rw101_needs_corpus_v3.py`
4. `sandbox/lf_contract_gate_test/router_wave/generate_rw101_c3_holdout_v3.py`
5. this handoff.

Do not read prior V2/V2.1/V3 judge results before RAW1.

## Fresh holdout

Choose fresh secret seed + nonce after freeze, then run:

`python3 sandbox/lf_contract_gate_test/router_wave/generate_rw101_c3_holdout_v3.py --seed '<secret>' --nonce '<secret>' --out /tmp/rw101_c3_holdout_v3.json`

Publish only the commitment before evaluation.

The generator guarantees the FUTURE_CAPABILITY pair contains one `DISCOVER` and one `CAPABILITY_GAP` case, so receipt-scope binding cannot disappear by random selection.

## Good responses

Build 12 correct answers independently. Do not copy `valid_answer()`.

Each resolved goal must use structured `per_goal`:

- exact goal;
- mode compatible with exact `permitted_modes`;
- exact parts;
- exact forbidden subjects;
- structured continuation bound to that same goal;
- no effect authority.

For CAPABILITY_GAP, bind the receipt to the exact request SHA-256 + case id + missing capability and mark it valid.

Free text may be display text only. It cannot carry security-relevant continuation authority.

## Bad responses

Build at least 24 bad answers, at least two falsifiers per generator family, including independent falsifiers for:

- K02: action/continuation bound to the wrong goal;
- K03: per-goal mode outside permitted modes;
- K06: extra part or extra per-goal row;
- K08: valid-looking discovery receipt bound to another request/case scope;
- free-text continuation that contradicts structured exclusions or tries to add an effect;
- at least two novel falsifiers not suggested by the checker.

Do not promote ambiguous K05/K07 into blockers unless the frozen oracle contains an unambiguous material requirement for them.

## Gates

PASS only if all are true:

- public V2 baseline remains valid;
- V3 self-test passes;
- 12/12 fresh good responses accepted;
- >=24/24 fresh bad responses rejected;
- >=2 novel falsifiers rejected;
- zero material blockers;
- RAW1 frozen before prior critiques;
- commitment verified after reveal.

## Lifecycle

A PASS here is evidence for governed reconciliation. It does not by itself rewrite the current Supabase checkpoint state. Any lifecycle correction must use the canonical governed path and readback.
