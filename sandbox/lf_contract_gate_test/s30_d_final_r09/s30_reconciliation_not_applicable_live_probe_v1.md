# S30 live NOT_APPLICABLE probe

This evidence-only marker exists solely to create one isolated S30-D change whose post-merge `LF GitHub Reconciliation V3` run must classify the change as `NOT_APPLICABLE / S30_KNOWN_ISOLATED_ONLY` and skip all quota-bound Supabase reconciliation steps.

Safety boundary: no production activation, no business effects, no scheduler/orchestrator activation, no model calls, no S26 mutation, and no billing or plan change.
