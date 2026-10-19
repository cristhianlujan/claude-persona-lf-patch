"""PE10 E2 generic evidence floor. No DB writes, no model invocation, no case oracle.

Reuses the existing M0.3 SQL source extractor and validates its reverse-consumer
candidate output. This is NOT a PL/pgSQL parser or a runtime-execution oracle.
"""
from __future__ import annotations

import hashlib
import json
import re
from collections import Counter
from typing import Any

COMPARISONS = frozenset({
    "HISTORICAL_EDGE_DECLARED",
    "CURRENT_EDGE_NOT_IN_P0",
    "CURRENT_CONSUMER_OUTSIDE_P0",
})
RESOLUTIONS = frozenset({
    "STATIC_CALL_CANDIDATE_RESOLVED",
    "STATIC_CALL_TARGET_UNRESOLVED",
    "AMBIGUOUS_STATIC_CALLEE_IDENTITY",
})
OBSERVATION_SCOPE = "CURRENT_BODY_NOT_HISTORICAL_EXECUTION"
CONTEXT_TYPES = frozenset({
    "CONFIRMED_CODE", "UNREVIEWED", "COMMENT_ONLY",
    "STRING_ONLY", "DYNAMIC_UNKNOWN",
})
MATERIAL_CHANGED = frozenset({
    "CURRENT_EDGE_NOT_IN_P0", "CURRENT_CONSUMER_OUTSIDE_P0",
})


def mask_noncode_sql(source: str) -> str:
    """Mask ordinary SQL/PLpgSQL strings/comments. Partial lexical floor only.

    Quoted identifiers, EXECUTE construction and complex procedural languages
    are deliberately not certified by this function.
    """
    out = list(source)
    pos = 0
    size = len(source)

    def blank(start: int, end: int) -> None:
        for i in range(start, end):
            if out[i] != "\n":
                out[i] = " "

    while pos < size:
        if source.startswith("--", pos):
            end = source.find("\n", pos + 2)
            if end < 0:
                end = size
            blank(pos, end)
            pos = end
        elif source.startswith("/*", pos):
            start = pos
            pos += 2
            depth = 1
            while pos < size and depth:
                if source.startswith("/*", pos):
                    depth += 1
                    pos += 2
                elif source.startswith("*/", pos):
                    depth -= 1
                    pos += 2
                else:
                    pos += 1
            blank(start, pos)
        elif source[pos] == "'":
            start = pos
            pos += 1
            while pos < size:
                if source.startswith("''", pos):
                    pos += 2
                elif source[pos] == "'":
                    pos += 1
                    break
                else:
                    pos += 1
            blank(start, pos)
        elif source[pos] == "$":
            found = re.match(r"\$[a-zA-Z_][a-zA-Z_0-9]*\$|\$\$", source[pos:])
            if found:
                delimiter = found.group()
                start = pos
                pos += len(delimiter)
                end = source.find(delimiter, pos)
                pos = size if end < 0 else end + len(delimiter)
                blank(start, pos)
            else:
                pos += 1
        else:
            pos += 1
    return "".join(out)


def exact_static_call_candidate(source: str, called_name: str) -> bool:
    """Return lexical code-position evidence, not verified execution."""
    if not re.fullmatch(r"fn_[A-Za-z_0-9]+", called_name):
        raise ValueError("called_name must be an exact fn_ identifier")
    code = mask_noncode_sql(source)
    pattern = r"(?<![A-Za-z_0-9])(?:[A-Za-z_][A-Za-z_0-9]*\.)?" + re.escape(called_name) + r"\s*\("
    return bool(re.search(pattern, code))


def edge_key(row: dict[str, Any]) -> str:
    consumer = row.get("consumer_identity")
    called = row.get("called_name")
    namespace = row.get("called_schema") or "?"
    if not isinstance(consumer, str) or not consumer.strip():
        raise ValueError("consumer_identity missing")
    if not isinstance(called, str) or not re.fullmatch(r"fn_[A-Za-z_0-9]+", called):
        raise ValueError("invalid exact callee name")
    return f"{consumer}|{namespace}.{called}"


def canonical_manifest(rows: list[dict[str, Any]]) -> tuple[str, list[dict[str, Any]]]:
    if not isinstance(rows, list) or not rows:
        raise ValueError("nonempty edge census required")
    observed_keys: set[str] = set()
    normalized = []
    for source in rows:
        row = dict(source)
        key = edge_key(row)
        if key in observed_keys:
            raise ValueError(f"duplicate edge: {key}")
        observed_keys.add(key)
        comparison = row.get("historical_comparison")
        resolution = row.get("resolution_status")
        if comparison not in COMPARISONS or resolution not in RESOLUTIONS:
            raise ValueError(f"invalid classification: {key}")
        if row.get("observation_scope") != OBSERVATION_SCOPE:
            raise ValueError(f"source epoch conflation: {key}")
        count = row.get("candidate_count")
        identities = row.get("callee_candidates")
        if not isinstance(count, int) or count < 0 or not isinstance(identities, list) or len(identities) != count:
            raise ValueError(f"callee resolution cardinality mismatch: {key}")
        expected = (
            "STATIC_CALL_TARGET_UNRESOLVED" if count == 0
            else "STATIC_CALL_CANDIDATE_RESOLVED" if count == 1
            else "AMBIGUOUS_STATIC_CALLEE_IDENTITY"
        )
        if resolution != expected:
            raise ValueError(f"false resolution state: {key}")
        context = row.get("lexical_context_check", "UNREVIEWED")
        if context not in CONTEXT_TYPES:
            raise ValueError(f"unknown lexical context: {key}")
        if row.get("static_confirmed") is True and (context != "CONFIRMED_CODE" or count != 1):
            raise ValueError(f"unproved static edge promotion: {key}")
        if row.get("runtime_execution_proven") is True:
            raise ValueError(f"static evidence cannot prove runtime execution: {key}")
        normalized.append({
            "key": key,
            "callee_candidates": identities,
            "candidate_count": count,
            "historical_comparison": comparison,
            "resolution_status": resolution,
            "lexical_context_check": context,
            "observation_scope": OBSERVATION_SCOPE,
            "static_confirmed": row.get("static_confirmed") is True,
        })
    normalized.sort(key=lambda item: item["key"])
    payload = json.dumps(normalized, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest(), normalized


def validate_synthesis(rows: list[dict[str, Any]], synthesis: dict[str, Any]) -> dict[str, Any]:
    """Fail closed on loss of any changed/outside-P0 candidate in synthesis."""
    digest, normalized = canonical_manifest(rows)
    if not isinstance(synthesis, dict) or synthesis.get("edge_manifest_sha256") != digest:
        raise ValueError("synthesis does not bind complete original edge manifest")
    if synthesis.get("claims_runtime_execution") is True:
        raise ValueError("runtime claim without independent execution evidence")
    failed = [r for r in normalized
              if r["historical_comparison"] in MATERIAL_CHANGED
              and r["key"] not in set(synthesis.get("preserved_edge_keys", []))
              and r["key"] not in set(synthesis.get("explicit_unresolved_keys", []))]
    if failed:
        raise ValueError("material incoming/outgoing edges lost in synthesis: " + ",".join(r["key"] for r in failed[:3]))
    for key in set(synthesis.get("explicit_unresolved_keys", [])):
        if key not in {r["key"] for r in normalized}:
            raise ValueError(f"unresolved unknown not tied to a real edge: {key}")
    counts = Counter(row["historical_comparison"] for row in normalized)
    return {
        "status": "PASS_STATIC_MANIFEST_CONSERVATION_ONLY",
        "edge_manifest_sha256": digest,
        "edges": len(normalized),
        "partition": dict(counts),
        "runtime_proven": False,
        "complete_current_universe_proven": False,
    }
