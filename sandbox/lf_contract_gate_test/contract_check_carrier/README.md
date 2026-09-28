# Contract Check Final Thin Carrier V1

Status: `SHADOW_CANDIDATE`

## Purpose

Provide the final transport-only entrypoint for the single Contract Check capability.

```text
JSON input
   |
   v
Final Thin Carrier
   |
   v
Contract Check Semantic Integration V1
   |
   v
PASS / BLOCK
```

## Boundary

The carrier MUST NOT:

- decide whether Contract Check applies;
- resolve or rank contracts;
- infer `operation_code`;
- normalize contracts itself;
- evaluate predicates itself;
- generate or accept a separate upstream verdict path;
- call sibling controls;
- read/write Supabase;
- mutate runtime, contracts, workflow state, or lifecycle state.

It only reads a JSON packet, delegates it unchanged to `Contract Check Semantic Integration V1`, emits the returned structured result, and maps `PASS` to exit code `0`, governed `BLOCK` to `2`, and invalid carrier/input transport to `3`.

## Evidence

Candidate self-test marker:

`PASS_CONTRACT_CHECK_FINAL_THIN_CARRIER_V1=12/12`

This candidate does not perform workflow cutover. Legacy cleanup is the next separately governed step in `lf_eventos.id=15565`.
