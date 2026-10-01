from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
NEW = ROOT / '.github/workflows/lf-contract-check-self-change-admission.yml'
OLD = ROOT / '.github/workflows/lf-github-reconcile-v3.yml'

new = NEW.read_text(encoding='utf-8')
old = OLD.read_text(encoding='utf-8')

checks = 0
assert 'pull_request_target' in new; checks += 1
assert 'lf_independent_change_admission_carrier_v1.py self-test' in new; checks += 1
assert 'lf_independent_change_admission_carrier_v1.py classify' in new; checks += 1
assert 'lf_independent_change_admission_carrier_v1.py validate' in new; checks += 1
assert 'workflow_run:' not in new; checks += 1
assert 'lf_github_reconcile_applicability.py' not in new; checks += 1
assert 'functions/v1/lf-github-reconcile-v3' not in new; checks += 1
assert 'independent-change-admission:' in old; checks += 1
print(f'PASS_L5_023_ADMISSION_REHOME_V1 checks={checks}')
