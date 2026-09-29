# lf-github-reconcile-v3 v12

Repair-window policy alignment only.

The active Edge reconciler and governed Pooler fallback must evaluate the same branch-protection contract emitted by `.github/workflows/lf-github-reconcile-v3.yml` during `PASE_REPAIR_WINDOW`: `required_status_checks=[]` / no required workflow paths is expected and verified through `pase_repair_window_required_checks_empty=true`.

This version deliberately does **not** activate `pase-merge-gate`, retire the legacy `lf-contract-check` push compatibility caller, or change ruleset enforcement.
