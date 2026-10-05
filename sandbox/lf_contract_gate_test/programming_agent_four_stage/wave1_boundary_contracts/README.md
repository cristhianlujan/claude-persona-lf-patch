# Programming Agent Wave 1 boundary contracts

Source-only candidate for `A1`, `PG-01`, and `TST-01`.

- **A1 / Analysis** produces `REQUEST_CONTEXT_V1` without Story, Functional Version, Agent Task, or solution inference.
- **PG-01 / Programming** consumes `ANALYSIS_IMPLEMENTATION_PACKAGE_V1`; existing Agent Task runtime is extended at the entry boundary rather than duplicated.
- **TST-01 / Testing** supports `DESIGN_ONLY` without a candidate and `EXECUTION` with an exact frozen candidate. Neither mode requires Story identity.
- `CAPABILITY_SELECTOR` selection remains separate from currentness, consumer admission, and execution entry guards.

This package does not activate runtime or production, change capability current pointers, or retire Story Creator.

Evidence: `lf_eventos://20333`, `lf_eventos://20334`, `lf_eventos://20335`.

Run:

```bash
python sandbox/lf_contract_gate_test/programming_agent_four_stage/wave1_boundary_contracts/validate_wave1_boundary_contracts_v1.py --self-test
```
