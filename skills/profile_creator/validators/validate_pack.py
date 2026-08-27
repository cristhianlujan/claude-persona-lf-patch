#!/usr/bin/env python3
import json
import subprocess
import sys
from pathlib import Path


def run(command):
    completed = subprocess.run(command, text=True, capture_output=True)
    if completed.stdout:
        print(completed.stdout, end='')
    if completed.stderr:
        print(completed.stderr, end='', file=sys.stderr)
    return completed.returncode


def main():
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd().resolve()
    repo_root = root.parent.parent
    checks = [
        ('PROFILE_CREATOR_CORE', [sys.executable, str(root/'validators/validate_pack_core.py'), str(root)]),
        ('GENERATED_PROFILE_MANIFEST', [sys.executable, str(root/'validators/validate_generated_profile_manifest.py'), str(root)]),
        ('CANDIDATE_DEPTH_SELF_TEST', [sys.executable, str(root/'validators/validate_candidate_depth.py'), '--self-test', str(root)]),
        ('GOV021_CHAMPION_CHALLENGER', [sys.executable, str(root/'validators/champion_challenger_depth.py'), str(root)]),
    ]
    canary = repo_root/'profiles/evidence_lineage_reviewer_lf'
    if canary.exists():
        checks.append(('EVIDENCE_LINEAGE_CANARY', [sys.executable, str(canary/'validators/validate_pack.py'), str(canary)]))
    failed = []
    for name, command in checks:
        rc = run(command)
        if rc != 0:
            failed.append(name)
    result = {
        'status': 'PASS' if not failed else 'FAIL',
        'checks_executed': [name for name, _ in checks],
        'failed_checks': failed,
        'runtime_authorized': False,
        'automatic_impact_authorized': False,
        'semantic_quality_review_authorized': False,
    }
    print(json.dumps(result, indent=2))
    return 0 if not failed else 1


if __name__ == '__main__':
    raise SystemExit(main())
