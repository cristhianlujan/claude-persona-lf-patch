# LF_LANGGRAPH_SPIKE_001

Status: `ISOLATED_SPIKE / NO_PRODUCTION / NO_S26_S30_MUTATION`

Strategy: `LF_PLATFORM_ADOPT_FIRST_20260912` (Strategy 34)

Base main: `c6e1dd5bfc47aa2eabf23de02a39c1aa0742fb8e`

## Question

Can LangGraph absorb LF's commodity orchestration responsibilities without changing LF semantic authority, Cards, EKB, contracts, receipts, or fail-closed behavior?

## Boundary

This spike deliberately wraps the existing governed runtime boundary:

`profile_runtime_runner.execute_profile_runtime`

It does **not** replace it.

LF remains authoritative for:

- profile source validation;
- Cards/adapters and context budgets;
- runtime request/response contracts;
- attestation verification;
- receipts and hashes;
- semantic/evidence gates;
- downstream authorization.

LangGraph is tested only as an orchestration substrate for:

- state and conditional routing;
- per-node retry;
- checkpoints/state history;
- HITL interrupt/resume;
- fail-closed routing around the existing LF runner.

## External baseline

Pinned dependency: `langgraph==1.2.11`.

Official LangGraph documentation states that checkpointed graph state supports fault tolerance, replay/time travel and HITL, and that retry policies can be attached to nodes. The spike tests those capabilities against LF's existing runner rather than assuming compatibility.

## Gates

The spike is acceptable only if all of the following pass:

1. The exact `runtime_result` produced through LangGraph equals the result produced by the current LF runner for the deterministic parity fixture.
2. Missing input blocks before runtime invocation.
3. A selected transient provider error is retried by LangGraph and then succeeds.
4. A non-transient provider error remains fail-closed and is not retried.
5. HITL pauses before runtime ind resumes on the same thread.
6. HITL rejection blocks without invoking runtime.
7. Checkpoint history exposes the expected execution frontier.
8. LF retains ownership of the receipt and its hash.

## Non-goals

- no production migration;
- no change to S26 or S30;
- no Supabase schema change;
- no replacement of `Semantic Authority`;
- no real model call in this first parity harness;
- no claim that in-memory checkpointing is production durability;
- no code deletion.

## Next gate after this spiike

If this deterministic parity harness passes, run a second bounded canary using one real S26 profile request with the current runtime and the LangGraph wrapper side by side. Migration design is forbidden until that real canary proves parity and a rollback path.
