#!/usr/bin/env python3
import json
import subprocess
import sys
from pathlib import Path


def run(command):
    completed = subprocess.run(command, text=True, capture_output=True)
    if completed.stdout:
        print(completed.stdout, end='' if completed.stdout.endswith('\n') else '\n')
    if completed.stderr:
        print(completed.stderr, end='' if completed.stderr.endswith('\n') else '\n', file=sys.stderr)
    return completed.returncode


def discover_profile_validators(repo_root: Path):
    profiles_root = (repo_root / 'profiles').resolve()
    discovered = []
    errors = []
    seen = set()
    if not profiles_root.is_dir():
        return discovered, ['PROFILES_ROOT_MISSING']
    for profile_dir in sorted(profiles_root.iterdir(), key=lambda p: p.name):
        if not profile_dir.is_dir() or profile_dir.name.startswith('_'):
            continue
        validator = profile_dir / 'validators' / 'validate_pack.py'
        if not validator.exists():
            continue
        if validator.is_symlink():
            errors.append(f'PROFILE_VALIDATOR_SYMLINK_FORBIDDEN:{profile_dir.name}')
            continue
        resolved = validator.resolve()
        if profiles_root not in resolved.parents:
            errors.append(f'PROFILE_VALIDATOR_OUTSIDE_PROFILES_ROOT:{profile_dir.name}')
            continue
        if resolved in seen:
            errors.append(f'PROFILE_VALIDATOR_DUPLICATE_TARGET:{profile_dir.name}')
            continue
        seen.add(resolved)
        discovered.append((profile_dir.name, resolved, profile_dir.resolve()))
    return discovered, errors


def main():
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd().resolve()
    repo_root = root.parent.parent
    checks = [
        ('PROFILE_CREATOR_CORE', [sys.executable, str(root/'validators/validate_pack_core.py'), str(root)]),
        ('GENERATED_PROFILE_MANIFEST', [sys.executable, str(root/'validators/validate_generated_profile_manifest.py'), str(root)]),
        ('CANDIDATE_DEPTH_SELF_TEST', [sys.executable, str(root/'validators/validate_candidate_depth.py'), '--self-test', str(root)]),
        ('GOV021_CHAMPION_CHALLENGER', [sys.executable, str(root/'validators/champion_challenger_depth.py'), str(root)]),
        ('PROFILE_VALIDATOR_DISCOVERY_MATRIX', [sys.executable, str(root/'evals/profile_validator_discovery_matrix.py')]),
        ('PROFILE_OPERATION_GENERIC_RESUMER', [sys.executable, str(root/'evals/batch_resume_contract.py')]),
        ('PROFILE_RESOLVER_DISPATCH_CONTRACT', [sys.executable, str(root/'evals/resolver_dispatch_contract.py')]),
        ('UPDATE_RECORDER_READINESS', [sys.executable, str(root/'evals/update_recorder_readiness_contract.py')]),
    ]
    discovered, discovery_errors = discover_profile_validators(repo_root)
    for slug, validator, profile_dir in discovered:
        checks.append((f'PROFILE_PACK::{slug}', [sys.executable, str(validator), str(profile_dir)]))
    failed = list(discovery_errors)
    if not discovered:
        failed.append('NO_GOVERNED_PROFILE_VALIDATORS_DISCOVERED')
    for name, command in checks:
        if run(command) != 0:
            failed.append(name)
    result = {
        'status': 'PASS' if not failed else 'FAIL',
        'checks_executed': [name for name, _ in checks],
        'discovered_profile_validators': [slug for slug, _, _ in discovered],
        'failed_checks': failed,
        'runtime_authorized': False,
        'automatic_impact_authorized': False,
        'semantic_quality_review_authorized': False,
    }
    print(json.dumps(result, indent=2))
    return 0 if not failed else 1


if __name__ == '__main__':
    raise SystemExit(main())
