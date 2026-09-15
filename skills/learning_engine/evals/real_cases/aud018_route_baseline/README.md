# MOTOR-AUD018-ROUTE-BASELINE-001

Purpose: freeze the first real input/output pair for Motor de Aprendizaje using EKB `AUD-018`.

This case is intentionally **not** a Learning Engine behavioral PASS. The governed Router was actually called and returned `BLOCK_OPERATION_NOT_REGISTERED`, so the Learning Engine itself was not executed.

## Exact observed flow

`ACT-0001 -> ACT-0046 -> EXECUTE -> BLOCK_OPERATION_NOT_REGISTERED`

## Evidence boundary

- current Main at observation: `5f33c4ce25fca201c109d31be5c2e1e1ec465afc`
- ACT-0046 GitHub pack blob: `46250c542c5335486429e0de49ee47db15569970`
- ACT-0046 Google Doc revision is pinned in `configuration.json`
- `execution_receipt.json` binds exact input, invocation, configuration and output SHA-256 values
- `verify_receipt.py` recomputes all four hashes
- no Supabase write
- no S26 mutation
- no S30 mutation
- no runtime/production/automatic impact

## Verify

```bash
python skills/learning_engine/evals/real_cases/aud018_route_baseline/verify_receipt.py
```

Expected:

```text
MOTOR_AUD018_BASELINE_RECEIPT_PASS
```

## Next gate

Materialize a governed Learning Engine execution route candidate without broadening generic `SKILL/EXECUTE` semantics.
