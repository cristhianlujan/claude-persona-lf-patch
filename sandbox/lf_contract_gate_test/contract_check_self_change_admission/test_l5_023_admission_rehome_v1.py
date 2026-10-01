from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MERGE_GATE = ROOT / '.github/workflows/pase-merge-gate.yml'
OLD = ROOT / '.github/workflows/lf-github-reconcile-v3.yml'
DEDICATED = ROOT / '.github/workflows/lf-contract-check-self-change-admission.yml'

merge_gate = MERGE_GATE.read_text(encoding='utf-8')
old = OLD.read_text(encoding='utf-8')

checks = 0
assert not DEDICATED.exists(); checks += 1
assert merge_gate.count('pull_request_target:') == 1; checks += 1
assert 'independent-change-admission:' in merge_gate; checks += 1
assert 'lf_independent_change_admission_carrier_v1.py self-test' in merge_gate; checks += 1
assert 'lf_independent_change_admission_carrier_v1.py classify' in merge_gate; checks += 1
assert 'lf_independent_change_admission_carrier_v1.py validate' in merge_gate; checks += 1
assert 'workflow_run:' not in merge_gate; checks += 1
assert 'lf_github_reconcile_applicability.py' not in merge_gate; checks += 1
assert 'functions/v1/lf-github-reconcile-v3' not in merge_gate; checks += 1
assert 'independent-change-admission:' in old; checks += 1
print(f'PASS_L5_023_ADMISSION_REHOME_V1 checks={checks}')
