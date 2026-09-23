# Work Protocol Manifest V1 — DEPRECATED HISTORICAL SANDBOX

Status: **DEPRECATED / DO NOT USE / DO NOT ADOPT**

This directory is retained only as historical evidence of the rejected Work Protocol V1 experiment.

Reason for deprecation: the candidate duplicated routing/orchestration/validation/closure responsibilities already owned by ACT-0001, canonical operation contracts, profiles, validators, judges and runtime primitives. Keeping it active would create duplicate execution, extra latency and potentially contradictory decisions.

Hard rule: no file in this directory is an adoption or rollout authority. Do not copy its G00–G11 model into a new controller. G12 rollout was cancelled and PR #1008 was closed without merge/apply.

Canonical replacements:
- routing/selection → ACT-0001;
- profile/operation execution and semantic validation → canonical operation/profile contracts;
- execution owner → canonical begin/reservation governance;
- timeout/chunk/checkpoint and ONE_SOLUTION_PER_PR → development/runtime working policy, not a new runtime gate engine.

Executable tombstones in this directory must return or raise `WORK_PROTOCOL_V1_DEPRECATED_DO_NOT_USE`.
