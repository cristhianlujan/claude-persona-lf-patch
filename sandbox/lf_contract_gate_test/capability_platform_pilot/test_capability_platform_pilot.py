from __future__ import annotations

import copy
import importlib.util
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REGISTRY = json.loads((ROOT / "capability_registry_v1.json").read_text(encoding="utf-8"))
spec = importlib.util.spec_from_file_location("capability_resolver", ROOT / "capability_resolver.py")
assert spec is not None and spec.loader is not None
resolver = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = resolver
spec.loader.exec_module(resolver)


def _registry_with_versions(versions, installed="2.1.0", requested=">=2.0.0 <3.0.0"):
    data = copy.deepcopy(REGISTRY)
    cap = next(c for c in data["capabilities"] if c["capability_code"] == "CAP-S30-SEMANTIC-QUALITY")
    cap["versions"] = versions
    dep = next(
        d
        for c in data["consumers"]
        if c["consumer_code"] == "ACT-0046"
        for d in c["dependencies"]
        if d["capability_code"] == "CAP-S30-SEMANTIC-QUALITY"
    )
    dep["installed_version"] = installed
    dep["requested_range"] = requested
    return data


def test_patch_auto_upgrade():
    data = _registry_with_versions(
        [
            {"version": "2.1.0", "status": "PUBLISHED", "maturity": "SANDBOX_VERIFIED"},
            {"version": "2.1.1", "status": "PUBLISHED", "maturity": "SANDBOX_VERIFIED"},
        ]
    )
    r = resolver.resolve_latest_compatible(data, "ACT-0046", "CAP-S30-SEMANTIC-QUALITY")
    assert r["latest_compatible"] == "2.1.1"
    assert r["bump_kind"] == "PATCH"
    assert r["decision"] == "UPGRADE_CANDIDATE"
    out = resolver.apply_candidate(r, contract_tests_pass=True, canary_pass=True)
    assert out["status"] == "UPDATED" and out["resolved_version"] == "2.1.1"


def test_minor_auto_upgrade_after_tests():
    data = _registry_with_versions(
        [
            {"version": "2.1.1", "status": "PUBLISHED", "maturity": "SANDBOX_VERIFIED"},
            {"version": "2.2.0", "status": "PUBLISHED", "maturity": "DETERMINISTIC_VERIFIED"},
        ],
        installed="2.1.1",
    )
    r = resolver.resolve_latest_compatible(data, "ACT-0046", "CAP-S30-SEMANTIC-QUALITY")
    assert r["bump_kind"] == "MINOR" and r["decision"] == "UPGRADE_CANDIDATE"
    assert resolver.apply_candidate(r, contract_tests_pass=True, canary_pass=True)["resolved_version"] == "2.2.0"


def test_major_outside_range_is_not_auto_installed():
    r = resolver.resolve_latest_compatible(REGISTRY, "ACT-0046", "CAP-S30-SEMANTIC-QUALITY")
    assert r["latest_available"] == "3.0.0"
    assert r["latest_compatible"] == "2.2.0"
    assert r["major_available_outside_range"] is True
    assert r["decision"] == "UPGRADE_CANDIDATE"


def test_contract_failure_keeps_installed_version():
    r = resolver.resolve_latest_compatible(REGISTRY, "ACT-0046", "CAP-S30-SEMANTIC-QUALITY")
    out = resolver.apply_candidate(r, contract_tests_pass=False, canary_pass=True)
    assert out == {"status": "BLOCKED", "resolved_version": "2.1.0", "reason": "CONTRACT_TEST_FAILED"}


def test_canary_failure_keeps_installed_version():
    r = resolver.resolve_latest_compatible(REGISTRY, "ACT-0046", "CAP-S30-SEMANTIC-QUALITY")
    out = resolver.apply_candidate(r, contract_tests_pass=True, canary_pass=False)
    assert out == {"status": "BLOCKED", "resolved_version": "2.1.0", "reason": "CANARY_FAILED"}


def test_push_pull_parity():
    push = resolver.simulate_push(REGISTRY, "CAP-S30-SEMANTIC-QUALITY", "2.2.0")
    act = next(x for x in push["impacted_consumers"] if x["consumer_code"] == "ACT-0046")
    pull = resolver.runtime_pull(REGISTRY, "ACT-0046", "CAP-S30-SEMANTIC-QUALITY")
    assert act["resolution"] == pull["resolution"]
    assert act["published_version_compatible"] is True


def test_pinned_consumer_stays_within_range():
    r = resolver.resolve_latest_compatible(REGISTRY, "PILOT-CONSUMER-PINNED", "CAP-S30-SEMANTIC-QUALITY")
    assert r["latest_compatible"] == "2.1.1"
    assert r["bump_kind"] == "PATCH"
    assert r["decision"] == "UPGRADE_CANDIDATE"


def test_retired_installed_version_fails_closed():
    data = copy.deepcopy(REGISTRY)
    cap = next(c for c in data["capabilities"] if c["capability_code"] == "CAP-S30-SEMANTIC-QUALITY")
    next(v for v in cap["versions"] if v["version"] == "2.1.0")["status"] = "RETIRED"
    try:
        resolver.resolve_latest_compatible(data, "ACT-0046", "CAP-S30-SEMANTIC-QUALITY")
    except resolver.CapabilityResolutionError as exc:
        assert str(exc) == "BLOCK_INSTALLED_VERSION_RETIRED"
    else:
        raise AssertionError("retired installed version must fail closed")


def test_invalid_semver_fails_closed():
    data = copy.deepcopy(REGISTRY)
    cap = next(c for c in data["capabilities"] if c["capability_code"] == "CAP-S30-SEMANTIC-QUALITY")
    cap["versions"].append({"version": "v2-latest", "status": "PUBLISHED", "maturity": "TEST"})
    try:
        resolver.resolve_latest_compatible(data, "ACT-0046", "CAP-S30-SEMANTIC-QUALITY")
    except resolver.CapabilityResolutionError as exc:
        assert str(exc).startswith("SEMVER_INVALID:")
    else:
        raise AssertionError("invalid semver must fail closed")


def test_out_of_range_installed_fails_closed():
    data = _registry_with_versions(
        [{"version": "3.0.0", "status": "PUBLISHED", "maturity": "ARCHITECTURE_READY"}],
        installed="3.0.0",
        requested=">=2.0.0 <3.0.0",
    )
    try:
        resolver.resolve_latest_compatible(data, "ACT-0046", "CAP-S30-SEMANTIC-QUALITY")
    except resolver.CapabilityResolutionError as exc:
        assert str(exc) == "INSTALLED_VERSION_OUTSIDE_RANGE"
    else:
        raise AssertionError("out-of-range installed version must fail closed")


def test_rollback():
    r = resolver.resolve_latest_compatible(REGISTRY, "ACT-0046", "CAP-S30-SEMANTIC-QUALITY")
    update = resolver.apply_candidate(r, contract_tests_pass=True, canary_pass=True)
    rb = resolver.rollback(update)
    assert rb["status"] == "ROLLED_BACK"
    assert rb["resolved_version"] == "2.1.0"
    assert rb["from_version"] == "2.2.0"


def test_s26_second_capability_resolves():
    r = resolver.resolve_latest_compatible(REGISTRY, "ACT-0046", "CAP-S26-SOURCE-FIDELITY")
    assert r["latest_compatible"] == "1.1.0"
    assert r["bump_kind"] == "MINOR"
    assert r["decision"] == "UPGRADE_CANDIDATE"


if __name__ == "__main__":
    cases = [
        test_patch_auto_upgrade,
        test_minor_auto_upgrade_after_tests,
        test_major_outside_range_is_not_auto_installed,
        test_contract_failure_keeps_installed_version,
        test_canary_failure_keeps_installed_version,
        test_push_pull_parity,
        test_pinned_consumer_stays_within_range,
        test_retired_installed_version_fails_closed,
        test_invalid_semver_fails_closed,
        test_out_of_range_installed_fails_closed,
        test_rollback,
        test_s26_second_capability_resolves,
    ]
    for fn in cases:
        fn()
    print(f"CAPABILITY_PLATFORM_PILOT_PASS={len(cases)}")
