#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
SQL = (ROOT / "supabase/migrations/20260930231033_lf_evidence_plane_hardening_ekb_closeout_v1.sql").read_text()
lower = SQL.lower()
executable = "\n".join(line for line in lower.splitlines() if not line.lstrip().startswith("--"))

codes = (
    "CURRENTNESS-EVIDENCE-SOURCE-HEAD-REANCHOR-001",
    "S31-EVIDENCE-RECEIPT-REPLAY-CROSSBIND-001",
    "S31-EVIDENCE-RESOLVER-IDENTITY-SPOOF-001",
)
for code in codes:
    assert code in SQL, code

assert "20260930133539" in SQL
assert "7b1abd2d539a1b58403514d987ec0cdd156d15ff74d45212f74466e6c5dfee0a" in SQL
assert "BLOCK_LF_EVIDENCE_LEDGER_GITHUB_PROVIDER_REF_HEAD_MISMATCH" in SQL
assert "BLOCK_LF_EVIDENCE_LEDGER_RESOLVER_IDENTITY_MISMATCH" in SQL
assert "BLOCK_LF_EVIDENCE_LEDGER_COMPOSITION_DIGEST_MISMATCH" in SQL
assert "get diagnostics v_count=row_count" in lower
assert "if v_count<>3" in lower
assert "set estado='resuelto'" in lower
assert "[resolved_20260930][evidence_plane_hardening_v1]" in lower
assert "exception-actualizacion-db-lf-patch-block-evidence-plane-ekb-closeout-readback" in lower
assert "resolved_correction_20260930" in lower
assert "exec-sadm-evidence-plane-ekb-closeout-20260930-002" in lower
assert "evidence_plane_hardening_v1_live_readback_and_rollback_canary" in lower
assert "insert into transversal.error_knowledge" not in executable
assert "delete from transversal.error_knowledge" not in executable
assert "lf_capability_promote_v1" not in executable
assert "insert into public.lf_capability_current" not in executable
assert "update public.lf_capability_current" not in executable
assert "runtime" not in executable
assert "production" not in executable
print("EVIDENCE_PLANE_HARDENING_EKB_CLOSEOUT_V1=PASS exact_codes=3 correction_finding=1 current_unchanged=true runtime_unchanged=true")
