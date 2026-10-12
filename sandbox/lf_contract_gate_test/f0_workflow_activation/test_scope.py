#!/usr/bin/env python3
from pathlib import Path
p=Path(".github/workflows")
train=(p/"lf-migration-merge-train.yml").read_text()
m93=(p/"ig-m93-shadow-readonly.yml").read_text()
admission=(p/"lf-independent-change-admission.yml").read_text()
judge=(p/"lf-ig-runtime-candidate-judge.yml").read_text()
assert train.count("environment: lf-merge-train") == 2
assert m93.count("environment: lf-merge-train") == 2
assert "LF_SUPABASE_DB_READONLY_PASSWORD: ${{ secrets.LF_SUPABASE_DB_READONLY_PASSWORD }}" in admission
assert "environment: lf-ci-readonly" in admission
assert judge.count("    name: ig-runtime-candidate-judge") == 1
assert "environment: lf-ig-judge" in judge
assert "if: ${{ always() }}" in judge
assert "RESULT=NOT_APPLICABLE" in judge and "RESULT=APPLICABLE_PASS" in judge
assert "LF_SUPABASE_DB_PASSWORD" not in (p/"pase-merge-gate.yml").read_text()
assert "LF_SUPABASE_DB_PASSWORD: ${{ secrets." not in (p/"lf-migration-source-parity-core.yml").read_text()
assert "environment: lf-runtime-readback" in (p/"lf-runtime-independent-readback.yml").read_text()
assert "environment: lf-s30-broker" in (p/"profile-driven-screen-generation.yml").read_text()
print("PASS_F0_STATIC_ENV_SEPARATION")
