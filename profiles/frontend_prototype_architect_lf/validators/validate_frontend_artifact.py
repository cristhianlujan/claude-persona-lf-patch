#!/usr/bin/env python3
"""Deterministic external readback validator for frontend_prototype_architect_lf.

Candidate declarations are never treated as proof. This validator resolves the
referenced workspace files, recomputes hashes/byte counts and parses HTML.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from html.parser import HTMLParser
from pathlib import Path

VOID_TAGS = {
    "area", "base", "br", "col", "embed", "hr", "img", "input",
    "link", "meta", "param", "source", "track", "wbr",
}
ALLOWED_SANDBOX_PREFIXES = ("sandbox/", "sandbox_runs/")
REQUIRED_ROLES = {"PRODUCT_DIRECTION", "UI_ARCHITECT"}


class StrictStaticHTMLParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.stack: list[str] = []
        self.seen_html = False
        self.seen_body = False
        self.errors: list[str] = []

    def handle_starttag(self, tag: str, attrs) -> None:
        tag = tag.lower()
        if tag == "html":
            self.seen_html = True
        if tag == "body":
            self.seen_body = True
        if tag not in VOID_TAGS:
            self.stack.append(tag)

    def handle_startendtag(self, tag: str, attrs) -> None:
        return

    def handle_endtag(self, tag: str) -> None:
        tag = tag.lower()
        if tag in VOID_TAGS:
            return
        if not self.stack:
            self.errors.append(f"unexpected closing tag </{tag}>")
            return
        expected = self.stack.pop()
        if expected != tag:
            self.errors.append(f"mismatched closing tag </{tag}> expected </{expected}>")

    def close(self) -> None:
        super().close()
        if self.stack:
            self.errors.append("unclosed tags: " + ",".join(self.stack))
        if not self.seen_html:
            self.errors.append("missing <html> root")
        if not self.seen_body:
            self.errors.append("missing <body>")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def safe_resolve(workspace: Path, ref: str) -> Path:
    if not ref or Path(ref).is_absolute():
        raise ValueError("reference must be non-empty and repo-relative")
    candidate = (workspace / ref).resolve()
    root = workspace.resolve()
    try:
        candidate.relative_to(root)
    except ValueError as exc:
        raise ValueError("path traversal/outside workspace") from exc
    return candidate


def validate_source_inputs(deliverable: dict, workspace: Path, errors: list[str]) -> None:
    sources = deliverable.get("source_inputs")
    if not isinstance(sources, list) or len(sources) < 2:
        errors.append("source_inputs must contain at least Product and UI authority")
        return
    seen_roles: set[str] = set()
    for idx, source in enumerate(sources):
        label = f"source_inputs[{idx}]"
        if not isinstance(source, dict):
            errors.append(f"{label} must be object")
            continue
        role = source.get("authority_role")
        if role in REQUIRED_ROLES:
            seen_roles.add(role)
        if source.get("currentness") != "CURRENT":
            errors.append(f"{label} is not CURRENT")
        if source.get("verdict") not in {"PASS", "APPROVED"}:
            errors.append(f"{label} verdict is not PASS/APPROVED")
        ref = source.get("source_ref")
        declared = source.get("source_sha256")
        try:
            path = safe_resolve(workspace, ref)
        except Exception as exc:
            errors.append(f"{label} invalid source_ref: {exc}")
            continue
        if not path.is_file():
            errors.append(f"{label} source_ref does not exist: {ref}")
            continue
        actual = sha256_bytes(path.read_bytes())
        if actual != declared:
            errors.append(f"{label} SHA mismatch: declared={declared} actual={actual}")
    missing = sorted(REQUIRED_ROLES - seen_roles)
    if missing:
        errors.append("missing required authority roles: " + ",".join(missing))


def parse_static_html(data: bytes) -> list[str]:
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return ["index.html is not UTF-8"]
    parser = StrictStaticHTMLParser()
    try:
        parser.feed(text)
        parser.close()
    except Exception as exc:
        return [f"HTML parser failure: {exc}"]
    return parser.errors


def validate_artifacts(deliverable: dict, workspace: Path, errors: list[str]) -> None:
    decision = deliverable.get("prototype_decision") or {}
    mode = decision.get("execution_mode")
    files = deliverable.get("files_to_create")
    evidence = deliverable.get("artifact_evidence")
    if not isinstance(files, list) or not files:
        errors.append("files_to_create must be non-empty")
        return
    if not any(str(path).endswith("index.html") for path in files):
        errors.append("files_to_create must include index.html")
    if not isinstance(deliverable.get("html_structure"), dict) or not deliverable["html_structure"]:
        errors.append("html_structure must be non-empty")
    if not isinstance(deliverable.get("css_structure"), dict) or not deliverable["css_structure"]:
        errors.append("css_structure must be non-empty")

    if mode == "ADVISORY_SPEC_ONLY":
        if evidence not in ([], None):
            errors.append("advisory mode must not claim artifact_evidence")
        return
    if mode != "CREATE_AND_VERIFY_ARTIFACT":
        errors.append("unknown prototype execution_mode")
        return
    if not isinstance(evidence, list) or not evidence:
        errors.append("artifact mode requires artifact_evidence")
        return

    by_path = {item.get("path"): item for item in evidence if isinstance(item, dict)}
    for ref in files:
        if not isinstance(ref, str):
            errors.append("files_to_create entries must be strings")
            continue
        normalized = ref.replace("\\", "/")
        if not normalized.startswith(ALLOWED_SANDBOX_PREFIXES):
            errors.append(f"artifact outside allowed sandbox paths: {ref}")
            continue
        item = by_path.get(ref)
        if not item:
            errors.append(f"missing artifact_evidence for {ref}")
            continue
        try:
            path = safe_resolve(workspace, ref)
        except Exception as exc:
            errors.append(f"invalid artifact path {ref}: {exc}")
            continue
        if not path.is_file():
            errors.append(f"artifact does not exist: {ref}")
            continue
        data = path.read_bytes()
        actual_sha = sha256_bytes(data)
        actual_bytes = len(data)
        if actual_bytes < 1:
            errors.append(f"artifact empty: {ref}")
        if item.get("exists") is not True or item.get("readback") is not True:
            errors.append(f"artifact declaration lacks exists/readback=true: {ref}")
        if item.get("declared_sha256") != actual_sha:
            errors.append(f"declared artifact SHA mismatch: {ref}")
        if item.get("readback_sha256") != actual_sha:
            errors.append(f"readback artifact SHA mismatch: {ref}")
        if item.get("bytes") != actual_bytes:
            errors.append(f"artifact byte-count mismatch: {ref}")
        if ref.endswith(".html"):
            parse_errors = parse_static_html(data)
            if parse_errors:
                errors.extend(f"{ref}: {msg}" for msg in parse_errors)
            if item.get("parse_status") != "HTML_PARSE_PASS":
                errors.append(f"HTML parse_status not PASS: {ref}")
        elif ref.endswith(".css") and item.get("parse_status") != "CSS_READ_PASS":
            errors.append(f"CSS parse_status not PASS: {ref}")

    extras = sorted(set(by_path) - set(files))
    if extras:
        errors.append("artifact_evidence contains undeclared files: " + ",".join(extras))


def validate_score(payload: dict, errors: list[str]) -> None:
    score = payload.get("score")
    if not isinstance(score, dict):
        errors.append("score must be object")
        return
    criteria = score.get("criteria")
    if not isinstance(criteria, list) or len(criteria) != 5:
        errors.append("score.criteria must contain exactly five criteria")
        return
    total = 0
    for idx, item in enumerate(criteria):
        if not isinstance(item, dict):
            errors.append(f"score.criteria[{idx}] must be object")
            continue
        points = item.get("points")
        refs = item.get("evidence_refs")
        if not isinstance(points, int) or not 0 <= points <= 5:
            errors.append(f"score.criteria[{idx}] invalid points")
            continue
        total += points
        if not isinstance(refs, list) or not refs or any(not isinstance(ref, str) or len(ref.strip()) < 3 for ref in refs):
            errors.append(f"score.criteria[{idx}] lacks concrete evidence_refs")
    if score.get("total") != total:
        errors.append(f"score total mismatch: declared={score.get('total')} recomputed={total}")


def validate(payload: dict, workspace: Path) -> dict:
    errors: list[str] = []
    if payload.get("worker") != "frontend_prototype_architect_lf":
        errors.append("wrong worker")
    if payload.get("output_type") != "HTML_SANDBOX_SPEC":
        errors.append("wrong output_type")
    deliverable = payload.get("deliverable_created")
    if not isinstance(deliverable, dict):
        errors.append("deliverable_created must be object")
        return {"valid": False, "errors": errors}

    validate_source_inputs(deliverable, workspace, errors)
    validate_artifacts(deliverable, workspace, errors)
    validate_score(payload, errors)

    verdict = payload.get("self_verdict")
    mode = (deliverable.get("prototype_decision") or {}).get("execution_mode")
    if verdict == "PASS_ARTIFACT_VERIFIED":
        if mode != "CREATE_AND_VERIFY_ARTIFACT":
            errors.append("artifact PASS requires CREATE_AND_VERIFY_ARTIFACT")
        if isinstance(payload.get("score"), dict) and payload["score"].get("total", 0) < 22:
            errors.append("artifact PASS requires score >=22")
    if verdict == "ADVISORY_COMPLETE" and mode != "ADVISORY_SPEC_ONLY":
        errors.append("ADVISORY_COMPLETE requires ADVISORY_SPEC_ONLY")
    if mode == "CREATE_AND_VERIFY_ARTIFACT" and verdict == "ADVISORY_COMPLETE":
        errors.append("artifact mode cannot use advisory verdict")

    return {"valid": not errors, "errors": errors}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("output_json", type=Path)
    parser.add_argument("--workspace", type=Path, default=Path.cwd())
    args = parser.parse_args()
    payload = json.loads(args.output_json.read_text(encoding="utf-8"))
    result = validate(payload, args.workspace)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result["valid"] else 1


if __name__ == "__main__":
    sys.exit(main())
