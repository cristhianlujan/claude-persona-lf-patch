from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping

STATUS_PUBLISHED = "PUBLISHED"
STATUS_RETIRED = "RETIRED"
STATUS_BLOCKED = "BLOCKED"
AUTO_AFTER_TEST = "AUTO_AFTER_TEST"


class CapabilityResolutionError(ValueError):
    pass


@dataclass(frozen=True, order=True)
class SemVer:
    major: int
    minor: int
    patch: int

    @classmethod
    def parse(cls, raw: str) -> "SemVer":
        if not isinstance(raw, str):
            raise CapabilityResolutionError("SEMVER_NOT_STRING")
        parts = raw.strip().split(".")
        if len(parts) != 3 or any(not p.isdigit() for p in parts):
            raise CapabilityResolutionError(f"SEMVER_INVALID:{raw}")
        return cls(*(int(p) for p in parts))

    def __str__(self) -> str:
        return f"{self.major}.{self.minor}.{self.patch}"


def _parse_clause(clause: str):
    for op in (">=", "<=", ">", "<", "=="):
        if clause.startswith(op):
            return op, SemVer.parse(clause[len(op):])
    return "==", SemVer.parse(clause)


def version_in_range(version: str, range_expr: str) -> bool:
    v = SemVer.parse(version)
    if not isinstance(range_expr, str) or not range_expr.strip():
        raise CapabilityResolutionError("VERSION_RANGE_EMPTY")
    for op, bound in (_parse_clause(c) for c in range_expr.split()):
        if op == ">=" and not (v >= bound):
            return False
        if op == "<=" and not (v <= bound):
            return False
        if op == ">" and not (v > bound):
            return False
        if op == "<" and not (v < bound):
            return False
        if op == "==" and not (v == bound):
            return False
    return True


def _bump_kind(old: str, new: str) -> str:
    a, b = SemVer.parse(old), SemVer.parse(new)
    if b <= a:
        return "NONE"
    if b.major != a.major:
        return "MAJOR"
    if b.minor != a.minor:
        return "MINOR"
    return "PATCH"


def _index_registry(registry: Mapping[str, Any]):
    if registry.get("schema") != "LF_CAPABILITY_REGISTRY_PILOT_V1":
        raise CapabilityResolutionError("REGISTRY_SCHEMA_INVALID")
    caps = registry.get("capabilities")
    if not isinstance(caps, list) or not caps:
        raise CapabilityResolutionError("CAPABILITIES_REQUIRED")
    out = {}
    for cap in caps:
        if not isinstance(cap, Mapping):
            raise CapabilityResolutionError("CAPABILITY_NOT_OBJECT")
        code = cap.get("capability_code")
        if not isinstance(code, str) or not code or code in out:
            raise CapabilityResolutionError("CAPABILITY_CODE_INVALID_OR_DUPLICATE")
        versions = cap.get("versions")
        if not isinstance(versions, list) or not versions:
            raise CapabilityResolutionError(f"CAPABILITY_VERSIONS_REQUIRED:{code}")
        seen = set()
        for item in versions:
            raw = item.get("version") if isinstance(item, Mapping) else None
            SemVer.parse(raw)
            if raw in seen:
                raise CapabilityResolutionError(f"DUPLICATE_VERSION:{code}:{raw}")
            seen.add(raw)
            if item.get("status") not in {STATUS_PUBLISHED, STATUS_RETIRED}:
                raise CapabilityResolutionError(f"VERSION_STATUS_INVALID:{code}:{raw}")
        out[code] = dict(cap)
    return out


def _index_consumers(registry: Mapping[str, Any]):
    consumers = registry.get("consumers")
    if not isinstance(consumers, list) or not consumers:
        raise CapabilityResolutionError("CONSUMERS_REQUIRED")
    out = {}
    for consumer in consumers:
        if not isinstance(consumer, Mapping):
            raise CapabilityResolutionError("CONSUMER_NOT_OBJECT")
        code = consumer.get("consumer_code")
        if not isinstance(code, str) or not code or code in out:
            raise CapabilityResolutionError("CONSUMER_CODE_INVALID_OR_DUPLICATE")
        deps = consumer.get("dependencies")
        if not isinstance(deps, list) or not deps:
            raise CapabilityResolutionError(f"DEPENDENCIES_REQUIRED:{code}")
        out[code] = dict(consumer)
    return out


def _dependency(registry: Mapping[str, Any], consumer_code: str, capability_code: str):
    caps = _index_registry(registry)
    consumers = _index_consumers(registry)
    if capability_code not in caps:
        raise CapabilityResolutionError("CAPABILITY_NOT_FOUND")
    if consumer_code not in consumers:
        raise CapabilityResolutionError("CONSUMER_NOT_FOUND")
    matches = [
        d
        for d in consumers[consumer_code]["dependencies"]
        if isinstance(d, Mapping) and d.get("capability_code") == capability_code
    ]
    if len(matches) != 1:
        raise CapabilityResolutionError("DEPENDENCY_NOT_EXACTLY_ONE")
    dep = dict(matches[0])
    installed = dep.get("installed_version")
    SemVer.parse(installed)
    if not version_in_range(installed, dep.get("requested_range", "")):
        raise CapabilityResolutionError("INSTALLED_VERSION_OUTSIDE_RANGE")
    cap_versions = {v["version"]: v for v in caps[capability_code]["versions"]}
    if installed not in cap_versions:
        raise CapabilityResolutionError("INSTALLED_VERSION_UNKNOWN")
    if cap_versions[installed].get("status") == STATUS_RETIRED:
        raise CapabilityResolutionError("BLOCK_INSTALLED_VERSION_RETIRED")
    return caps[capability_code], dep


def resolve_latest_compatible(registry: Mapping[str, Any], consumer_code: str, capability_code: str):
    cap, dep = _dependency(registry, consumer_code, capability_code)
    published = [v for v in cap["versions"] if v.get("status") == STATUS_PUBLISHED]
    if not published:
        raise CapabilityResolutionError("NO_PUBLISHED_VERSIONS")
    ordered = sorted(published, key=lambda x: SemVer.parse(x["version"]))
    compatible = [v for v in ordered if version_in_range(v["version"], dep["requested_range"])]
    if not compatible:
        raise CapabilityResolutionError("BLOCK_CAPABILITY_VERSION_UNRESOLVED")
    latest_available = ordered[-1]["version"]
    latest_compatible = compatible[-1]["version"]
    installed = dep["installed_version"]
    bump = _bump_kind(installed, latest_compatible)
    policy = dep.get("update_policy") or {}
    policy_for_bump = policy.get(bump, "NO_UPDATE") if bump != "NONE" else "NO_UPDATE"
    decision = "CURRENT"
    if latest_compatible != installed:
        decision = "UPGRADE_CANDIDATE" if policy_for_bump == AUTO_AFTER_TEST else "MANUAL_MIGRATION"
    return {
        "schema": "LF_CAPABILITY_RESOLUTION_V1",
        "consumer_code": consumer_code,
        "capability_code": capability_code,
        "requested_range": dep["requested_range"],
        "installed_version": installed,
        "latest_compatible": latest_compatible,
        "latest_available": latest_available,
        "bump_kind": bump,
        "update_policy": policy_for_bump,
        "decision": decision,
        "major_available_outside_range": SemVer.parse(latest_available).major > SemVer.parse(latest_compatible).major,
        "fail_closed": dep.get("fail_closed") is True,
    }


def simulate_push(registry: Mapping[str, Any], capability_code: str, published_version: str):
    caps = _index_registry(registry)
    if capability_code not in caps:
        raise CapabilityResolutionError("CAPABILITY_NOT_FOUND")
    matches = [v for v in caps[capability_code]["versions"] if v["version"] == published_version]
    if len(matches) != 1 or matches[0].get("status") != STATUS_PUBLISHED:
        raise CapabilityResolutionError("PUBLISHED_VERSION_NOT_FOUND")
    consumers = _index_consumers(registry)
    impacted = []
    for consumer_code, consumer in sorted(consumers.items()):
        if any(
            isinstance(d, Mapping) and d.get("capability_code") == capability_code
            for d in consumer["dependencies"]
        ):
            resolution = resolve_latest_compatible(registry, consumer_code, capability_code)
            impacted.append(
                {
                    "consumer_code": consumer_code,
                    "resolution": resolution,
                    "published_version_compatible": version_in_range(
                        published_version, resolution["requested_range"]
                    ),
                }
            )
    return {
        "schema": "LF_CAPABILITY_PUSH_SCAN_V1",
        "capability_code": capability_code,
        "published_version": published_version,
        "impacted_consumers": impacted,
    }


def runtime_pull(registry: Mapping[str, Any], consumer_code: str, capability_code: str):
    return {
        "schema": "LF_CAPABILITY_PULL_CHECK_V1",
        "resolution": resolve_latest_compatible(registry, consumer_code, capability_code),
    }


def apply_candidate(resolution: Mapping[str, Any], *, contract_tests_pass: bool, canary_pass: bool):
    if resolution.get("decision") != "UPGRADE_CANDIDATE":
        return {
            "status": "NO_CHANGE",
            "resolved_version": resolution.get("installed_version"),
            "reason": resolution.get("decision"),
        }
    if not contract_tests_pass:
        return {
            "status": STATUS_BLOCKED,
            "resolved_version": resolution.get("installed_version"),
            "reason": "CONTRACT_TEST_FAILED",
        }
    if not canary_pass:
        return {
            "status": STATUS_BLOCKED,
            "resolved_version": resolution.get("installed_version"),
            "reason": "CANARY_FAILED",
        }
    return {
        "status": "UPDATED",
        "previous_version": resolution.get("installed_version"),
        "resolved_version": resolution.get("latest_compatible"),
        "reason": "COMPATIBLE_TESTED_CANARY_PASS",
    }


def rollback(update_receipt: Mapping[str, Any]):
    if update_receipt.get("status") != "UPDATED":
        raise CapabilityResolutionError("ROLLBACK_REQUIRES_UPDATED_RECEIPT")
    previous = update_receipt.get("previous_version")
    SemVer.parse(previous)
    return {
        "status": "ROLLED_BACK",
        "resolved_version": previous,
        "from_version": update_receipt.get("resolved_version"),
    }
