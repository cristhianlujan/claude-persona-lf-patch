# Strategy 28 production docs-only FAST canary

Temporary canary used only to verify the production routing introduced by PR #508.

Expected behavior:
- `feedback-tier-router` => FAST / `DOCS_EKB_ONLY_PRODUCTION_SLICE`
- `schema-bootstrap-probe` => skipped
- `v7-runtime-apply-rollback` => skipped
- existing non-Bootstrap checks remain unchanged

This branch is not intended to merge.