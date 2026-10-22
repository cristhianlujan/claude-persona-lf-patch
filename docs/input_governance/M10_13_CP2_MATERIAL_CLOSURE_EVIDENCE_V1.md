# IG M10.13 — CP2 GIT_RUNTIME_PARITY material closure evidence

Program: `IG_CURATOR_VALIDATOR_REFACTOR_V2` · Unit: `M10.13` · Checkpoint: `GIT_RUNTIME_PARITY` · Work item: `474` · Checkpoint row: `1218`.

## Independent source and execution observations

- Canonical workflow: `.github/workflows/lf-migration-merge-train.yml`, original *full-current* step `IG M10.13 CP2 material FULL_CURRENT_STATE parity`.
- Material last-run evidence: `https://github.com/cristhianlujan/claude-persona-lf-patch/actions/runs/39706754375`, job `119588485648`, `lf-migration-merge-train` = `success`; step `IG M10.13 CP2 material FULL_CURRENT_STATE parity` = `success`; artifact upload = `success`; second `lf-migration-merge` job = `success`.
- Positive log signals from the *executed* job (not just authored source): `PASS_MIGRATION_SOURCE_PARITY_TRUSTED_READ_ONLY head=8052deeee06d4cc8f3ba31cbd561e3b308047ae7 migrations=828` and `PASS_IG_M1013_CP2_FULL_CURRENT_STATE source=8052deeee06d4cc8f3ba31cbd561e3b308047ae7`.
- Executed source: `main@8052deeee06d4cc8f3ba31cbd561e3b308047ae7`; subsequent merged PR #3076 / `main@2191a957a6ab2df4cbfac3bdde054956af99eafa` added only this checkpoint's evidence-request document; no migration or Edge content changed.
- Material evidence artifact: `lf-ig-m1013-cp2-full-parity-39706754375-1` (GitHub artifact ID `12395218172`); archive SHA-256 `5828c727632686d67f5fe9a92a07e20dc6d4d7985327b0fa3493e931d0b862e6`; file size 50,311 bytes; was available and unexpired at readback.
- Runner used readonly Supabase role `lf_reconcile_readonly`. Full-current check verifies the current post-baseline migration corpus, registered 15 historical inventory differences, four historical source pointers, and canonical live ledger statement digests. PASE and admission were successful before Train.
- Post-run, live Supabase Edge Function file retrieval and frozen Git `main@8052deeee06d4cc8f3ba31cbd561e3b308047ae7` readback showed exact bytes (including `deno.json`) for 6/6 files: Agent v17 (Git `index.ts` blob `326a5c492c84cceccb45ea8d6a0f39a1d5305637`), Curator v14 (`bd43f469d5d508f64dbee21eea7be611e7d2e780`), Validator v18 (`31a77e43c02f714479e5ed2f1fdb615fbe38eead`), Agent/Curator config `3330a0cb91e661bb049dba3b26f1d1d1b6c1139c`, Validator config `d29ef0262a525187c7fb9e6a0096adc81adf9be1`.
- An earlier false FAIL and read-only permission FAIL were resolved by PR #3072 and PR #3074 without changing governance or database role grants. The last PASS was not inferred from these earlier failed executions.

## Acceptance and negative scope

This evidence supports **only** CP2, and not CP3, CP4, production activation or the whole M10.13 unit. Readiness and assertion contract must be fetched live at checkpoint transition. A forged result with `validator_status=FAIL` must be rejected without leaving a receipt, and the canonical `fn_guard_engineering_material_checkpoint_done_v1` must remain active.

## Transport

Persist through an independently checked `ACTUALIZACION_DB_LF` Git-first migration processed by PASE → LF Migration Merge Train. The migration must obtain the *real live* execution ID and call `programacion.fn_engineering_checkpoint_assertion_record_v1` then `programacion.fn_engineering_checkpoint_transition_v1` atomically. The artifact itself is immutable external evidence; this document is not a replacement for the real runner PASS.
