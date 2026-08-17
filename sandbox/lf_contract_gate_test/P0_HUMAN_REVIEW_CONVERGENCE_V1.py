#!/usr/bin/env python3
"""Executable P0-4 Human Review Convergence Contract.

Pure contract tests: no human decision is manufactured and no sealed holdout is opened.
"""
from __future__ import annotations

import hashlib
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

BINDING_FIELDS = (
    "source_head_sha", "source_object_id", "source_sha256",
    "visual_output_object_id", "visual_output_sha256",
    "packet_manifest_object_id", "packet_manifest_sha256",
    "review_id", "challenge_id",
)
COUNTERS = ("element_count", "uncertain_count", "inferred_count", "changed_count", "pending_human_count")
REPO_ROOT = Path(__file__).resolve().parents[2]
CANONICAL_RENDERER = REPO_ROOT / "sandbox/story_creator_p0_visual/v1.1/scripts/p0_human_review_shell_v4.py"
CANONICAL_MIGRATION = REPO_ROOT / "supabase/migrations/20260817001205_lf_p0_canonical_human_review_single_renderer_v1.sql"
CANONICAL_MATERIALIZER = REPO_ROOT / "supabase/functions/lf-p0-human-review-v42-materialize-v1/index.ts"
CANONICAL_WEB = REPO_ROOT / "supabase/functions/lf-p0-human-review-web-v1/index.ts"
CANONICAL_RENDERER_BLOB = "91144c0f3c01f22b84f5c8a79c43a4e378cb9d18"


def canonical_element(e: dict[str, Any]) -> dict[str, Any]:
    return {k: e.get(k) for k in (
        "element_id", "element_type", "region", "visible_text", "ocr_consensus_text",
        "classification", "semantic_role", "subcomponent_role", "parent_id", "state",
    )}


def fingerprint(elements: list[dict[str, Any]]) -> str:
    stable = sorted((canonical_element(e) for e in elements), key=lambda x: str(x.get("element_id") or ""))
    raw = json.dumps(stable, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    return hashlib.sha256(raw).hexdigest()


def delta(old: list[dict[str, Any]], new: list[dict[str, Any]]) -> dict[str, int]:
    a = {str(e.get("element_id")): canonical_element(e) for e in old}
    b = {str(e.get("element_id")): canonical_element(e) for e in new}
    added = len(b.keys() - a.keys()); removed = len(a.keys() - b.keys())
    common = a.keys() & b.keys(); changed = sum(a[k] != b[k] for k in common)
    unchanged = len(common) - changed
    return {"unchanged": unchanged, "changed": changed, "added": added, "removed": removed, "invalidated": changed + added + removed}


def project_states(rows: list[dict[str, Any]], now: datetime) -> list[dict[str, Any]]:
    by_scope: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for r in rows:
        by_scope.setdefault((r["review_lane"], r["scope"]), []).append(r)
    out: list[dict[str, Any]] = []
    for group in by_scope.values():
        ordered = sorted(group, key=lambda r: (r["issued_at"], r["challenge_id"]), reverse=True)
        for i, r in enumerate(ordered):
            state = "SUPERSEDED" if i else ("EXPIRED" if r["expires_at"] <= now else ("ACTIVE" if r.get("review_ready") else "NOT_REVIEW_READY"))
            out.append({**r, "state": state})
    return out


def assert_binding(html: str, expected: dict[str, Any], *, generated_at: datetime, now: datetime, ttl_hours: int = 24) -> None:
    if 'id="p0-review-binding-v1"' not in html or 'data-review-shell-version="4.2"' not in html:
        raise ValueError("REVIEW_READY_WITHOUT_CURRENT_HTML")
    for field in BINDING_FIELDS:
        if not expected.get(field) or str(expected[field]) not in html:
            raise ValueError(f"BINDING_MISMATCH:{field}")
    if now - generated_at > timedelta(hours=ttl_hours):
        raise ValueError("STALE_UI_ARTIFACT")
    for counter in COUNTERS:
        if counter not in expected or expected[counter] is None:
            raise ValueError(f"COUNTER_MISSING:{counter}")


def assert_carry_forward(old_fp: str, new_fp: str, carry: bool) -> None:
    if carry and old_fp != new_fp:
        raise ValueError("UNSAFE_CARRY_FORWARD")


def assert_first_review(mode: str, prior_decisions: int) -> None:
    if prior_decisions == 0 and mode != "HOLISTIC":
        raise ValueError("FIRST_REVIEW_NOT_HOLISTIC")


def assert_human_debt(old_fp: str, new_fp: str, previous_pending: int, current_pending: int, justification: str = "") -> None:
    if old_fp == new_fp and current_pending > previous_pending and not justification.strip():
        raise ValueError("HUMAN_DEBT_CONVERGENCE_FAIL")


def assert_lane(*, lane: str, candidate_output_exposed: bool, sealed_holdout: bool) -> None:
    if lane == "P0-5" and candidate_output_exposed:
        raise ValueError("P0_5_CANDIDATE_OUTPUT_EXPOSED")
    if sealed_holdout and lane in {"P0-4", "P0-5"}:
        raise ValueError("SEALED_HOLDOUT_IN_NORMAL_QUEUE")


def assert_sensitive_dual(classification: str, dual_review_required: bool) -> None:
    if classification == "SENSITIVE" and not dual_review_required:
        raise ValueError("SENSITIVE_DUAL_REVIEW_REQUIRED")


def expect_fail(label: str, fn, code: str) -> None:
    try:
        fn()
    except ValueError as exc:
        if not str(exc).startswith(code):
            raise SystemExit(f"FAIL_{label}: expected={code} observed={exc}")
        return
    raise SystemExit(f"FAIL_{label}: negative case passed")


def run_canonical_renderer_contract() -> None:
    renderer = CANONICAL_RENDERER.read_text(encoding="utf-8")
    migration = CANONICAL_MIGRATION.read_text(encoding="utf-8")
    materializer = CANONICAL_MATERIALIZER.read_text(encoding="utf-8")
    web = CANONICAL_WEB.read_text(encoding="utf-8")
    checks = {
        "R01_v42_tabs": 'data-review-shell-version="4.2"' in renderer and 'id="review-tabs"' in renderer,
        "R02_ordered_pages": "pageOrder=['summary','screen','elements','detail','decision']" in renderer,
        "R03_dynamic_observation_count": "LISTA DE ELEMENTOS DETECTADOS (${M.counts.total})" in renderer and "${M.counts.total} elementos detectados" in renderer,
        "R04_single_source_background": '<div id="source-stage"><div id="source-canvas">__SOURCE_HTML__<div id="overlay"></div>' in renderer,
        "R05_single_selected_crop": renderer.count('<canvas id="selected-crop"') == 1 and "function drawCrop(e)" in renderer,
        "R06_no_parallel_crop_gallery": all(x not in renderer.lower() for x in ("crop-gallery", "crops-grid", "all-crops")),
        "R07_source_title_preserved": "IMAGEN ORIGINAL CON ANOTACIONES" in renderer,
        "R08_element_list_preserved": 'id="element-list"' in renderer and 'id="detail-panel"' in renderer,
        "R09_db_gate_renderer_blob": CANONICAL_RENDERER_BLOB in migration and "CANONICAL_V42_RENDERER_BLOB_MISMATCH" in migration,
        "R10_db_gate_structural_markers": all(x in migration for x in (
            "CANONICAL_V42_MARKER_MISSING", "M.counts.total", "IMAGEN ORIGINAL CON ANOTACIONES",
            "LISTA DE ELEMENTOS DETECTADOS", "CANONICAL_V42_SELECTED_CROP_COUNT_INVALID",
            "CANONICAL_V42_PARALLEL_CROP_COMPOSITION_FORBIDDEN",
        )),
        "R11_copy_refresh_retired": "CANONICAL_V42_MATERIALIZER_REQUIRED" in migration and "copying an existing BROWSER_REVIEW is forbidden" in migration,
        "R12_presentation_only_metadata": "human_language_presentation_only" in migration and "structural_redesign_forbidden" in migration,
        "R13_materializer_fetches_frozen_renderer": CANONICAL_RENDERER_BLOB in materializer and "GITHUB_RENDERER_FETCH_FAILED" in materializer and "CANONICAL_RENDERER_BLOB_MISMATCH" in materializer,
        "R14_materializer_uses_canonical_publish": "fn_lf_p0_publish_canonical_review_v42_v1" in materializer,
        "R15_human_language_after_render": "fn_lf_p0_human_review_human_language_v2" in materializer,
        "R16_typed_bindings": all(x in materializer for x in ("$3::text", "$4::text", "$5::text", "$2::text")),
        "R17_web_requires_canonical_markers": all(x in web for x in (
            CANONICAL_RENDERER_BLOB, "CANONICAL_V42_CONTRACT_MISMATCH", "CANONICAL_CROP_POLICY_MISMATCH",
            "IMAGEN ORIGINAL CON ANOTACIONES", "LISTA DE ELEMENTOS DETECTADOS", "M.counts.total",
        )),
    }
    failed = [name for name, ok in checks.items() if not ok]
    print(json.dumps({"suite":"P0_HUMAN_REVIEW_CANONICAL_SINGLE_RENDERER","passed":len(checks)-len(failed),"total":len(checks),"failed":failed,"results":checks},sort_keys=True))
    if failed:
        raise SystemExit("FAIL_P0_HUMAN_REVIEW_CANONICAL_SINGLE_RENDERER:" + ",".join(failed))
    print("PASS_P0_HUMAN_REVIEW_CANONICAL_SINGLE_RENDERER_GATE=17/17")


def main() -> int:
    now = datetime(2026, 8, 14, 6, 0, tzinfo=timezone.utc)
    head = "0" * 40; sha = "1" * 64
    base = {
        "source_head_sha": head, "source_object_id": "src-1", "source_sha256": sha,
        "visual_output_object_id": "vis-1", "visual_output_sha256": "2" * 64,
        "packet_manifest_object_id": "man-1", "packet_manifest_sha256": "3" * 64,
        "review_id": "REV-1", "challenge_id": "CH-1",
        "element_count": 91, "uncertain_count": 30, "inferred_count": 18,
        "changed_count": 0, "pending_human_count": 91,
    }
    html = '<html data-review-shell-version="4.2"><script id="p0-review-binding-v1">' + json.dumps(base) + '</script></html>'
    assert_binding(html, base, generated_at=now, now=now)

    e1 = {"element_id": "A", "visible_text": "Pago seguro", "classification": "CONFIRMED", "region": {"x": 1}}
    e2 = {**e1, "text_lineage": {"block": 9, "merge": "GRAPH"}}
    if fingerprint([e1]) != fingerprint([e2]): raise SystemExit("FAIL_LINEAGE_SHOULD_NOT_CHANGE_SEMANTIC_FP")
    e3 = {**e1, "visible_text": "Pago seQuro"}
    if fingerprint([e1]) == fingerprint([e3]): raise SystemExit("FAIL_VISIBLE_CHANGE_MUST_CHANGE_FP")
    d = delta([e1, {"element_id":"B","visible_text":"x"}], [e1, {"element_id":"C","visible_text":"y"}])
    if d != {"unchanged":1,"changed":0,"added":1,"removed":1,"invalidated":2}: raise SystemExit(f"FAIL_DELTA_REMOVAL:{d}")

    rows = [
        {"review_lane":"P0-4","scope":"screen-1","challenge_id":"old","issued_at":now-timedelta(hours=1),"expires_at":now+timedelta(hours=20),"review_ready":True},
        {"review_lane":"P0-4","scope":"screen-1","challenge_id":"new","issued_at":now,"expires_at":now+timedelta(hours=24),"review_ready":True},
    ]
    states = project_states(rows, now)
    active = [r for r in states if r["state"] == "ACTIVE"]
    if len(active) != 1 or active[0]["challenge_id"] != "new": raise SystemExit("FAIL_MAX_ONE_ACTIVE")
    if any(r["challenge_id"] == "old" and r["state"] != "SUPERSEDED" for r in states): raise SystemExit("FAIL_SUPERSESSION")

    neg = 0
    def bad(field: str):
        wrong = dict(base); wrong[field] = "WRONG"
        bad_html = '<html data-review-shell-version="4.2"><script id="p0-review-binding-v1">' + json.dumps(wrong) + '</script></html>'
        return lambda: assert_binding(bad_html, base, generated_at=now, now=now)
    for label,field in (("WRONG_HEAD","source_head_sha"),("WRONG_CHALLENGE","challenge_id"),("WRONG_SOURCE_SHA","source_sha256"),("WRONG_VISUAL_SHA","visual_output_sha256"),("WRONG_MANIFEST_SHA","packet_manifest_sha256")):
        expect_fail(label,bad(field),"BINDING_MISMATCH"); neg += 1
    expect_fail("NO_HTML",lambda: assert_binding("<html></html>",base,generated_at=now,now=now),"REVIEW_READY_WITHOUT_CURRENT_HTML"); neg += 1
    expect_fail("STALE_UI",lambda: assert_binding(html,base,generated_at=now-timedelta(hours=25),now=now),"STALE_UI_ARTIFACT"); neg += 1
    no_counter=dict(base); no_counter.pop("changed_count")
    expect_fail("COUNTERS",lambda: assert_binding(html,no_counter,generated_at=now,now=now),"COUNTER_MISSING"); neg += 1
    expect_fail("CARRY",lambda: assert_carry_forward("a"*64,"b"*64,True),"UNSAFE_CARRY_FORWARD"); neg += 1
    expect_fail("FIRST_REVIEW",lambda: assert_first_review("DELTA",0),"FIRST_REVIEW_NOT_HOLISTIC"); neg += 1
    expect_fail("DEBT",lambda: assert_human_debt("a"*64,"a"*64,91,92),"HUMAN_DEBT_CONVERGENCE_FAIL"); neg += 1
    expect_fail("P05_EXPOSURE",lambda: assert_lane(lane="P0-5",candidate_output_exposed=True,sealed_holdout=False),"P0_5_CANDIDATE_OUTPUT_EXPOSED"); neg += 1
    expect_fail("HOLDOUT",lambda: assert_lane(lane="P0-4",candidate_output_exposed=False,sealed_holdout=True),"SEALED_HOLDOUT_IN_NORMAL_QUEUE"); neg += 1
    expect_fail("DUAL",lambda: assert_sensitive_dual("SENSITIVE",False),"SENSITIVE_DUAL_REVIEW_REQUIRED"); neg += 1

    assert_first_review("HOLISTIC",0)
    assert_human_debt("a"*64,"a"*64,91,91)
    assert_carry_forward("a"*64,"a"*64,True)
    assert_lane(lane="P0-5",candidate_output_exposed=False,sealed_holdout=False)
    assert_sensitive_dual("SENSITIVE",True)

    if neg != 14: raise SystemExit(f"FAIL_NEGATIVE_COUNT:{neg}")
    run_canonical_renderer_contract()
    print("PASS_P0_HUMAN_REVIEW_CONVERGENCE=20/20")
    print("PASS_HUMAN_DEBT_CONVERGENCE=4/4")
    print(json.dumps({"result":"PASS","negative_contracts":14,"semantic_lineage_invariant":True,"removed_elements_visible":True,"max_one_active":True,"p0_4_p0_5_separate":True,"sealed_holdout_used":False,"human_decisions_simulated":False,"production_authorized":False},sort_keys=True))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
