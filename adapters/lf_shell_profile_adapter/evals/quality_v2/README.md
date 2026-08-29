# Shell Adapter Quality V2

This directory contains deterministic contract cases and the behavioral protocol for the Shell adapter.

`run_cases.py` is a contract regression suite. It does not execute a profile/runtime and must not be reported as RAW behavior.

Candidate contract PASS requires all expected-pass and expected-fail cases to behave as declared, the semantic judge to pass on valid material examples, and the runtime capsule to remain within the shared adapter quality budget.
