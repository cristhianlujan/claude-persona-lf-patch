# PG-01 → PG-02 bridge — qualification only

**State:** `DRAFT / OFFLINE / NO_DISPATCH_AUTHORITY`.

Observed in Supabase (read-only, 30 Oct 2026): plan `PROGRAMMING_AGENT_PROGRAMMING_REMEDIATION_V1`; units PG-01 = PROG-REM-001 and PG-02 = PROG-REM-002; dependency `PG-02 REQUIRES PG-01`; all observed work/checkpoints BACKLOG/PENDING. Ninety Simple Executor bindings exist for B2B plans, zero for PG. The PG-01 runtime receipt writer exists, but a live caller and qualified dispatch handler are not evidenced.

This code does **not** bind the Simple Executor, Carril D, C6 or a live receipt provider. It checks synthetic candidate input and **always** returns `BLOCKED / authority=NONE / dispatch_allowed=false`, even when fields claim `PASS`. It never writes SQL, touches GitHub at runtime, calls a model or records checkpoint DONE.

The proposed bridge separates:
1. Mapping of PG plan and work identity;
2. Actual current PG-01 source receipt from authenticated ledger;
3. Plan/required checkpoint validator admission on *chosen* engine;
4. PG-02 dependency transition based on fresh authenticated evidence;
5. The single Carril D dispatcher and C6 pre-model hook.

The future owner must identify the actual handler and provider APIs, specify exact run receipts and qualified validators, then implement the live adapter through a governed PR. No inferred authority from synthetic fixtures. No activation/merge of this PR based solely on the supplied tests.

**Qualification:** eleven unit tests defined in `test_pg01_pg02_pre_admission_v1.py`. Require exact-HEAD execution, adversarial review, PASE and an approved disposable end-to-end exercise.
