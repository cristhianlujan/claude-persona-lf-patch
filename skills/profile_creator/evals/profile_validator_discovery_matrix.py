#!/usr/bin/env python3
import importlib.util
import json
import tempfile
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / 'validators' / 'validate_pack.py'
spec = importlib.util.spec_from_file_location('profile_creator_validate_pack', MODULE_PATH)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def make_validator(root: Path, slug: str):
    path = root / 'profiles' / slug / 'validators' / 'validate_pack.py'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('raise SystemExit(0)\n', encoding='utf-8')
    return path


def run_case(case_id, builder, expected_slugs, expected_errors):
    with tempfile.TemporaryDirectory() as tmp:
        repo = Path(tmp)
        (repo / 'profiles').mkdir(parents=True)
        builder(repo)
        discovered, errors = module.discover_profile_validators(repo)
        slugs = [slug for slug, _, _ in discovered]
        passed = slugs == expected_slugs and errors == expected_errors
        return {
            'id': case_id,
            'expected_slugs': expected_slugs,
            'actual_slugs': slugs,
            'expected_errors': expected_errors,
            'actual_errors': errors,
            'passed': passed,
        }


cases = []

cases.append(run_case(
    'generic_two_profiles',
    lambda repo: (make_validator(repo, 'alpha_profile'), make_validator(repo, 'zeta_profile')),
    ['alpha_profile', 'zeta_profile'],
    [],
))


def template_and_missing(repo):
    make_validator(repo, '_template')
    (repo / 'profiles' / 'beta_without_validator').mkdir(parents=True)
    make_validator(repo, 'gamma_profile')

cases.append(run_case(
    'template_excluded_missing_validator_skipped',
    template_and_missing,
    ['gamma_profile'],
    [],
))


def future_holdout(repo):
    make_validator(repo, 'future_profile_not_known_to_profile_creator')

cases.append(run_case(
    'future_profile_holdout_discovered_without_hardcode',
    future_holdout,
    ['future_profile_not_known_to_profile_creator'],
    [],
))


def no_validators(repo):
    (repo / 'profiles' / 'plain_profile').mkdir(parents=True)

cases.append(run_case(
    'no_validator_contract_means_not_discovered',
    no_validators,
    [],
    [],
))

passed = all(case['passed'] for case in cases)
print(json.dumps({'passed': passed, 'case_count': len(cases), 'cases': cases}, indent=2))
raise SystemExit(0 if passed else 1)
