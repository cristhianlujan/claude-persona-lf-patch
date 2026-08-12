#!/usr/bin/env python3
"""Human-first, responsive and evidence-bound P0 review shell V4.2.

The public review experience is intentionally simple. Raw hashes, internal IDs,
reader provenance and selected-element JSON stay available under an advanced
technical disclosure instead of dominating the adjudicator workflow.
"""
from __future__ import annotations

import base64
import datetime as dt
import hashlib
import html
import json
from pathlib import Path
from typing import Any

ALLOWED_ACTIONS = (
    "CONFIRM_OBSERVATION",
    "CORRECT_WITH_ADJUDICATION",
    "REQUEST_NEW_CAPTURE",
    "REQUEST_ADDITIONAL_CONTEXT",
    "REJECT_AND_BLOCK",
    "ESCALATE_SECURITY",
    "ESCALATE_PRIVACY",
)

SHELL_MARKERS = (
    "P0 VISUAL HUMAN REVIEW V4",
    'data-review-shell-version="4.2"',
    'id="review-tabs"',
    'id="source-stage"',
    'id="element-list"',
    'id="detail-panel"',
    'id="decision-bar"',
    'id="selected-crop"',
    'data-action="CONFIRM_OBSERVATION"',
    'data-action="CORRECT_WITH_ADJUDICATION"',
    'data-action="REQUEST_NEW_CAPTURE"',
    'data-action="REQUEST_ADDITIONAL_CONTEXT"',
    'data-action="REJECT_AND_BLOCK"',
    "ESCALATE_SECURITY",
    "ESCALATE_PRIVACY",
    "@media (max-width: 767px)",
    "touch-action:pan-y",
    "pageOrder=['summary','screen','elements','detail','decision']",
    "ResizeObserver",
)


def _j(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")


def _sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _text(element: dict[str, Any]) -> str:
    for key in (
        "visible_text",
        "ocr_consensus_text",
        "text",
        "label",
        "semantic_role",
        "subcomponent_role",
    ):
        value = element.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    return str(element.get("element_type") or "Elemento visual")


def _uri(path: Path | None) -> str | None:
    if not path or not path.exists():
        return None
    suffix = path.suffix.lower()
    mime = "image/png" if suffix == ".png" else "image/jpeg"
    return f"data:{mime};base64," + base64.b64encode(path.read_bytes()).decode("ascii")


def _challenge(challenge: dict[str, Any] | None) -> dict[str, Any]:
    challenge = challenge or {}
    expires_at = challenge.get("expires_at")
    expired = False
    if expires_at:
        try:
            parsed = dt.datetime.fromisoformat(str(expires_at).replace("Z", "+00:00"))
            if parsed.tzinfo is None:
                parsed = parsed.replace(tzinfo=dt.timezone.utc)
            expired = parsed <= dt.datetime.now(dt.timezone.utc)
        except ValueError:
            expired = True
    return {
        **challenge,
        "issue_number": challenge.get("issue_number", 125),
        "expired": expired,
        "binding_valid": challenge.get("binding_valid", True),
    }


def adapt_real_rerun_receipt_v4(
    receipt: dict[str, Any], image_path: Path
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    if not isinstance(receipt, dict):
        raise ValueError("REAL_RERUN_RECEIPT_NOT_OBJECT")
    source_sha = str(receipt.get("source_sha256") or "")
    if len(source_sha) != 64:
        raise ValueError("REAL_RERUN_SOURCE_SHA_MISSING")
    observed_sha = _sha(image_path)
    if observed_sha != source_sha:
        raise ValueError(
            f"REAL_SOURCE_SHA_MISMATCH expected={source_sha} observed={observed_sha}"
        )

    readers = receipt.get("reader_outputs") or []
    passes = receipt.get("passes") or []
    if not readers or not passes:
        raise ValueError("REAL_RERUN_FINAL_PASS_MISSING")

    final_pass = passes[-1]
    reader_id = final_pass.get("reader_execution_id")
    reader = next(
        (
            item
            for item in reversed(readers)
            if item.get("reader_execution_id") == reader_id
        ),
        None,
    )
    if not reader:
        raise ValueError("REAL_RERUN_READER_BINDING_MISSING")
    if reader.get("source_sha256") != source_sha:
        raise ValueError("REAL_RERUN_READER_SOURCE_BINDING_MISMATCH")

    reader = json.loads(json.dumps(reader))
    uncertainties = reader.get("reader_uncertainties") or []
    by_element: dict[str, list[dict[str, Any]]] = {}
    for uncertainty in uncertainties:
        element_id = uncertainty.get("element_id")
        if element_id:
            by_element.setdefault(str(element_id), []).append(uncertainty)

    for element in reader.get("elements", []):
        element_id = str(element.get("element_id") or "")
        element["_explicit_uncertainties"] = by_element.get(element_id, [])
        element["_display_text"] = _text(element)

    result = receipt.get("result") or {}
    technical_packet = receipt.get("human_review_packet") or {}
    explicit_terminal = receipt.get("terminal_result") or technical_packet.get("terminal_result")
    terminal_result = explicit_terminal or result.get("result")
    coverage = final_pass.get("independent_screen_coverage") or {}
    packet = {
        "human_review_ready": terminal_result == "READY_FOR_HUMAN_REVIEW_RECHECK" or (not explicit_terminal and bool(result.get("human_review_ready"))),
        "screen_summary": {
            "visual_fidelity_result": terminal_result,
            "pass_id": final_pass.get("pass_id"),
            "reader_execution_id": reader_id,
            "candidate_sha256": final_pass.get("candidate_sha256"),
            "coverage_percent": final_pass.get("coverage_percent"),
        },
        "human_attention_required": [],
        "reader_uncertainties": uncertainties,
        "limitations": technical_packet.get("limitations") or [],
        "technical_gate_result": terminal_result,
        "underlying_technical_gate_result": technical_packet.get("technical_gate_result"),
        "human_adjudication": technical_packet.get("human_adjudication"),
        "p0_5_state": technical_packet.get("p0_5_state"),
        "production_authorized": technical_packet.get("production_authorized"),
        "coverage": coverage,
    }
    runtime_context = {
        "mode": "REAL_RERUN_RECEIPT_V4",
        "code_head_sha": receipt.get("code_head_sha"),
        "configuration_sha256": receipt.get("configuration_sha256"),
        "source_sha256": source_sha,
        "source_bytes": image_path.stat().st_size,
        "source_width": reader.get("width"),
        "source_height": reader.get("height"),
        "pass_id": final_pass.get("pass_id"),
        "reader_execution_id": reader_id,
        "candidate_sha256": final_pass.get("candidate_sha256"),
        "coverage_percent": final_pass.get("coverage_percent"),
        "coverage": coverage,
        "technical_gate_result": terminal_result,
        "underlying_technical_gate_result": technical_packet.get("technical_gate_result"),
        "limitations": technical_packet.get("limitations") or [],
        "p0_5_state": technical_packet.get("p0_5_state"),
        "production_authorized": technical_packet.get("production_authorized"),
    }
    return packet, reader, runtime_context


def build_human_review_shell_from_rerun_receipt_v4(
    receipt: dict[str, Any],
    image_path: Path,
    challenge: dict[str, Any] | None = None,
    *,
    screen_name: str = "01_onboarding paso 1.png",
) -> str:
    packet, candidate, runtime_context = adapt_real_rerun_receipt_v4(
        receipt, image_path
    )
    runtime_context["screen_name"] = screen_name
    return build_human_review_shell_v4(
        packet,
        candidate,
        image_path,
        challenge,
        runtime_context=runtime_context,
    )


def build_human_review_shell_v4(
    packet: dict[str, Any],
    candidate: dict[str, Any],
    image_path: Path | None = None,
    challenge: dict[str, Any] | None = None,
    *,
    runtime_context: dict[str, Any] | None = None,
) -> str:
    challenge_state = _challenge(challenge)
    context = runtime_context or {}
    uncertainties = packet.get("reader_uncertainties") or []
    uncertainty_ids = {
        str(item.get("element_id")) for item in uncertainties if item.get("element_id")
    }
    exceptions = {
        str(item.get("element_id"))
        for item in packet.get("human_attention_required", [])
        if item.get("element_id")
    }

    elements: list[dict[str, Any]] = []
    for ordinal, raw in enumerate(candidate.get("elements", []), 1):
        element = dict(raw)
        element_id = str(element.get("element_id") or f"EL-{ordinal:04d}")
        explicit_uncertainties = element.get("_explicit_uncertainties") or [
            item
            for item in uncertainties
            if str(item.get("element_id")) == element_id
        ]
        classification = str(element.get("classification") or "NOT_OBSERVABLE")
        element["_review"] = {
            "ordinal": ordinal,
            "element_id": element_id,
            "classification": classification,
            "uncertain": element_id in uncertainty_ids or bool(explicit_uncertainties),
            "problem": element_id in exceptions,
            "omission": bool(element.get("omission") or element.get("is_omission")),
        }
        element["_explicit_uncertainties"] = explicit_uncertainties
        element["_display_text"] = element.get("_display_text") or _text(element)
        elements.append(element)

    counts = {
        "total": len(elements),
        "confirmed": sum(
            item["_review"]["classification"] == "CONFIRMED" for item in elements
        ),
        "inferred": sum(
            item["_review"]["classification"] == "INFERRED" for item in elements
        ),
        "not_observable": sum(
            item["_review"]["classification"] == "NOT_OBSERVABLE"
            for item in elements
        ),
        "uncertainties": len(
            {
                item["_review"]["element_id"]
                for item in elements
                if item["_review"]["uncertain"]
            }
        ),
        "problems": sum(item["_review"]["problem"] for item in elements),
        "omissions": sum(item["_review"]["omission"] for item in elements),
    }

    screen_summary = packet.get("screen_summary") or {}
    metadata = {
        "screen": context.get("screen_name")
        or candidate.get("screen_code")
        or candidate.get("source_image_ref")
        or candidate.get("execution_id")
        or "P0 screen",
        "mode": context.get("mode") or "LEGACY_V3_PACKET",
        "source_sha256": context.get("source_sha256")
        or candidate.get("source_sha256")
        or challenge_state.get("source_sha256")
        or "",
        "head": context.get("code_head_sha")
        or challenge_state.get("source_head_sha")
        or "",
        "candidate_sha256": context.get("candidate_sha256")
        or packet.get("candidate_sha256")
        or "",
        "pass_id": context.get("pass_id") or screen_summary.get("pass_id") or "",
        "reader_execution_id": context.get("reader_execution_id")
        or screen_summary.get("reader_execution_id")
        or "",
        "machine_result": context.get("technical_gate_result")
        or screen_summary.get("visual_fidelity_result")
        or packet.get("technical_gate_result")
        or "",
        "human_review_ready": bool(packet.get("human_review_ready")),
        "challenge_id": challenge_state.get("challenge_id") or "",
        "review_id": challenge_state.get("review_id") or "",
        "expires_at": challenge_state.get("expires_at") or "",
        "expired": bool(challenge_state.get("expired")),
        "binding_valid": bool(challenge_state.get("binding_valid", True)),
        "issue_number": challenge_state.get("issue_number", 125),
        "required_reviewer_role": challenge_state.get(
            "required_reviewer_role", "P0_VISUAL_ADJUDICATOR"
        ),
        "counts": counts,
        "coverage_percent": context.get("coverage_percent")
        or screen_summary.get("coverage_percent"),
        "coverage": context.get("coverage") or packet.get("coverage") or {},
        "limitations": context.get("limitations") or packet.get("limitations") or [],
        "p0_5_state": context.get("p0_5_state") or packet.get("p0_5_state"),
        "production_authorized": context.get("production_authorized")
        if "production_authorized" in context
        else packet.get("production_authorized"),
        "source_width": context.get("source_width") or candidate.get("width"),
        "source_height": context.get("source_height") or candidate.get("height"),
        "source_bytes": context.get("source_bytes"),
    }
    data = {
        "metadata": metadata,
        "elements": elements,
        "allowed_actions": list(ALLOWED_ACTIONS),
    }

    source_uri = _uri(image_path)
    title = html.escape(str(metadata["screen"]))
    source_html = (
        f'<img id="source-image" alt="Pantalla fuente {title}" src="{source_uri}">'
        if source_uri
        else '<div class="source-placeholder">Imagen fuente no embebida</div>'
    )

    action_buttons = "".join(
        f'<button class="decision-btn" data-action="{action}" type="button"></button>'
        for action in ALLOWED_ACTIONS[:5]
    )
    more_action_buttons = "".join(
        f'<button class="decision-btn secondary" data-action="{action}" type="button"></button>'
        for action in ALLOWED_ACTIONS[5:]
    )

    document = _TEMPLATE
    replacements = {
        "__TITLE__": title,
        "__DATA__": _j(data),
        "__SOURCE_HTML__": source_html,
        "__ACTION_BUTTONS__": action_buttons,
        "__MORE_ACTION_BUTTONS__": more_action_buttons,
    }
    for token, value in replacements.items():
        document = document.replace(token, value)
    return document


def validate_human_review_shell_v4(document: str) -> dict[str, Any]:
    missing = [marker for marker in SHELL_MARKERS if marker not in document]
    forbidden_needles = (
        "SUPABASE_SERVICE_ROLE_KEY",
        "GITHUB_TOKEN=",
        "Authorization: Bearer",
        "PRIVATE KEY-----",
        "access_token",
    )
    forbidden = [needle for needle in forbidden_needles if needle in document]
    return {
        "pass": not missing and not forbidden,
        "missing": missing,
        "forbidden": forbidden,
    }


_TEMPLATE = r'''<!doctype html>
<html lang="es" data-review-shell-version="4.2">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>P0 Visual Human Review V4.2 · __TITLE__</title>
<style>
:root{--header-h:92px;--nav-h:48px;--navy:#06192b;--navy2:#0b2743;--blue:#145edb;--bg:#edf2f6;--card:#fff;--line:#d7e0e8;--text:#172334;--muted:#66758a;--green:#147a37;--green-bg:#e9f7ed;--amber:#9a5b00;--amber-bg:#fff6df;--violet:#6d43a8;--violet-bg:#f4effb;--red:#b42318;--red-bg:#fff0ef;--yellow:#fff1b8;--shadow:0 6px 20px rgba(4,26,48,.08);--radius:12px}*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:var(--bg);color:var(--text);font:14px/1.42 Inter,ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;touch-action:pan-y}button,input{font:inherit}button{cursor:pointer}button:disabled{cursor:not-allowed}.app-header{position:sticky;top:0;z-index:80;background:linear-gradient(135deg,var(--navy),#041321);color:#fff;padding:11px 16px 10px;border-bottom:1px solid #1d3b57}.header-grid{display:grid;grid-template-columns:minmax(240px,1.25fr) repeat(3,minmax(160px,.8fr));gap:14px;align-items:end}.brand-kicker{font-size:17px;font-weight:900;letter-spacing:.01em}.screen-name{color:#6ed8ff;font-size:15px;font-weight:800;margin-top:2px}.header-label{font-size:10px;text-transform:uppercase;letter-spacing:.06em;color:#a9bdd0;font-weight:800}.header-value{margin-top:3px;font-size:12px;font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.pass-pill{display:inline-flex;padding:6px 9px;border-radius:999px;background:#90df77;color:#082514;font-size:10px;font-weight:900;max-width:100%}.review-nav{position:sticky;top:var(--header-h);z-index:75;background:var(--navy2);border-bottom:1px solid #294863}.review-tabs{display:flex;overflow-x:auto;scrollbar-width:none}.review-tabs::-webkit-scrollbar{display:none}.nav-tab{border:0;background:transparent;color:#ccdae7;padding:12px 16px;font-weight:800;white-space:nowrap;border-bottom:3px solid transparent}.nav-tab.active{color:#fff;border-bottom-color:#58b8ff;background:rgba(255,255,255,.05)}.binding-banner{display:none;margin:10px 12px 0;padding:10px 12px;border-radius:9px;border:1px solid #fecaca;background:var(--red-bg);color:#8a2018;font-weight:800}.binding-banner.show{display:block}.page{scroll-margin-top:calc(var(--header-h) + var(--nav-h) + 10px)}.quick-strip{margin:10px 12px 0;background:var(--yellow);border:1px solid #ead476;border-radius:8px;display:flex;gap:18px;overflow-x:auto;padding:8px 12px;box-shadow:var(--shadow)}.quick-item{white-space:nowrap;font-size:12px}.quick-item b{margin-left:5px}.summary-section{padding:10px 12px 0}.summary-card{background:var(--card);border:1px solid var(--line);border-radius:var(--radius);box-shadow:var(--shadow);padding:14px}.summary-top{display:flex;justify-content:space-between;gap:14px;align-items:center}.summary-title{font-size:18px;font-weight:900}.summary-sub{margin-top:3px;color:var(--muted)}.ready-badge{padding:8px 11px;border-radius:999px;background:var(--green-bg);color:var(--green);font-weight:900;white-space:nowrap}.metrics{display:grid;grid-template-columns:repeat(6,minmax(120px,1fr));gap:8px;margin-top:12px}.metric{border:1px solid var(--line);border-radius:10px;padding:10px;background:#fbfcfd}.metric strong{display:block;font-size:22px;line-height:1.1}.metric span{color:var(--muted);font-size:11px;font-weight:700}.metric.attention{background:var(--amber-bg);border-color:#ead69a}.metric.coverage{background:var(--green-bg);border-color:#bde5c8}.main-grid{display:grid;grid-template-columns:minmax(0,1.03fr) minmax(380px,.97fr);gap:10px;padding:10px 12px}.card{background:var(--card);border:1px solid var(--line);border-radius:var(--radius);box-shadow:var(--shadow);overflow:hidden}.card-title{display:flex;align-items:center;justify-content:space-between;gap:10px;background:var(--navy);color:#fff;padding:10px 12px;font-weight:900}.card-title small{font-weight:600;color:#bcd0e1}.source-card{position:sticky;top:calc(var(--header-h) + var(--nav-h) + 10px)}.source-toolbar{display:flex;gap:6px;align-items:center;padding:8px;border-bottom:1px solid var(--line);background:#f9fbfc}.icon-btn,.plain-btn{border:1px solid #bdc9d4;border-radius:7px;background:#fff;color:#26384a;padding:6px 9px;font-weight:800}.toolbar-spacer{flex:1}.element-counter{font-size:11px;color:var(--muted);font-weight:800}#source-stage{overflow:auto;max-height:calc(100vh - var(--header-h) - var(--nav-h) - 104px);background:#f8fafc;touch-action:pan-y}#source-canvas{position:relative;display:inline-block;min-width:100%;transform-origin:top left}#source-image{display:block;width:100%;height:auto}.source-placeholder{padding:70px 20px;text-align:center;color:var(--muted)}#overlay{position:absolute;inset:0;pointer-events:none}.overlay-box{position:absolute;border:2px solid var(--green);background:rgba(20,122,55,.05);pointer-events:auto;cursor:pointer;border-radius:2px}.overlay-box.inferred{border-color:#ef8e00;background:rgba(239,142,0,.06)}.overlay-box.not-observable{border-color:var(--violet);background:rgba(109,67,168,.06)}.overlay-box.attention,.overlay-box.problem,.overlay-box.omission{border-color:var(--red);background:rgba(180,35,24,.06)}.overlay-box.selected{outline:3px solid var(--blue);outline-offset:1px}.overlay-label{position:absolute;left:-2px;top:-19px;min-width:18px;height:18px;padding:1px 4px;border-radius:3px;background:#12283c;color:#fff;font-size:10px;line-height:16px;text-align:center;font-weight:900}.detail-card{min-height:580px}.detail-shell{padding:12px}.selected-head{display:flex;align-items:center;gap:8px;flex-wrap:wrap}.selected-id{background:#ffe99d;border:1px solid #efd26a;border-radius:6px;padding:6px 9px;font-weight:900}.status-badge{display:inline-flex;align-items:center;border-radius:999px;padding:5px 8px;font-size:11px;font-weight:900}.status-badge.confirmed{background:var(--green-bg);color:var(--green)}.status-badge.inferred{background:var(--amber-bg);color:var(--amber)}.status-badge.not-observable{background:var(--violet-bg);color:var(--violet)}.semantic-type{margin-left:auto;color:var(--muted);font-size:11px;font-weight:700}.reading-panel{margin-top:10px;border:1px solid var(--line);border-radius:9px;overflow:hidden}.reading-grid{display:grid;grid-template-columns:1fr 1fr}.reading-cell{padding:10px;min-height:88px}.reading-cell+.reading-cell{border-left:1px solid var(--line)}.cell-label{font-size:10px;text-transform:uppercase;color:var(--muted);font-weight:900}.cell-value{margin-top:5px;font-size:16px;font-weight:800}.confidence{margin-top:4px;color:var(--green);font-weight:900}.review-note{margin-top:10px;border-radius:8px;padding:9px 10px;background:#f4f7fa;border:1px solid var(--line)}.review-note.attention{background:var(--amber-bg);border-color:#ead69a;color:#634100}.review-note.problem{background:var(--red-bg);border-color:#f0b6b2;color:#84251d}.compare-card{margin-top:10px;border:1px solid var(--line);border-radius:9px;overflow:hidden}.mini-title{padding:8px 10px;background:#f7f9fb;border-bottom:1px solid var(--line);font-size:11px;font-weight:900;text-transform:uppercase}.compare-grid{display:grid;grid-template-columns:1fr 1fr}.compare-pane{padding:10px;min-height:150px}.compare-pane+.compare-pane{border-left:1px solid var(--line)}.compare-heading{font-weight:900;color:#174cbd;font-size:11px}.crop-wrap{display:flex;align-items:center;justify-content:center;min-height:95px;margin-top:7px;background:#fafafa;border:1px solid #e2e8ef;border-radius:6px;overflow:hidden}#selected-crop{max-width:100%;max-height:160px}.system-reading{margin-top:7px;border:1px solid #e2e8ef;border-radius:6px;padding:12px;background:#fff;min-height:95px;font-size:15px}.evidence-meta{margin-top:7px;color:var(--muted);font-size:11px}.detail-tabs{display:flex;gap:2px;overflow-x:auto;margin:12px -12px 0;padding:0 12px;border-bottom:1px solid var(--line)}.detail-tab{border:0;background:transparent;padding:9px 8px;color:#53657a;font-size:11px;font-weight:900;white-space:nowrap;border-bottom:3px solid transparent}.detail-tab.active{color:var(--blue);border-bottom-color:var(--blue)}.detail-tab-panel{display:none;padding-top:10px}.detail-tab-panel.active{display:block}.kv{display:grid;grid-template-columns:150px 1fr;gap:7px;padding:5px 0;border-bottom:1px solid #edf1f4}.kv:last-child{border-bottom:0}.kv .k{color:var(--muted)}.ok-list{display:grid;grid-template-columns:1fr auto;gap:4px 10px}.ok{color:var(--green);font-weight:900}.warn{color:var(--amber);font-weight:900}.mono{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;word-break:break-all}.technical{margin-top:10px;border:1px dashed #b8c4cf;border-radius:8px;background:#fafbfc}.technical summary{padding:9px 10px;font-weight:900;color:#40546a}.technical-body{padding:0 10px 10px}pre{white-space:pre-wrap;word-break:break-word;background:#f2f5f8;border-radius:7px;padding:8px;font-size:10px;max-height:220px;overflow:auto}.elements-section{padding:0 12px 10px}.elements-card{overflow:hidden}.elements-head{display:flex;gap:8px;align-items:center;padding:8px 10px;background:#102b47;color:#fff}.elements-head strong{white-space:nowrap}.search-wrap{margin-left:auto;position:relative}.search-wrap input{width:min(320px,42vw);border:1px solid #496278;background:#0a2035;color:#fff;border-radius:7px;padding:7px 9px}.search-wrap input::placeholder{color:#b7c6d3}.filters{display:flex;gap:6px;overflow-x:auto;padding:8px;background:#fff;border-bottom:1px solid var(--line)}.filter{border:1px solid #cbd6df;background:#fff;border-radius:7px;padding:6px 9px;font-weight:900;white-space:nowrap}.filter.active{background:#e8f1ff;border-color:#8ab3f2;color:#174cbd}.filter[data-filter="CONFIRMED"]{color:var(--green)}.filter[data-filter="INFERRED"]{color:var(--amber)}.filter[data-filter="NOT_OBSERVABLE"]{color:var(--violet)}.filter[data-filter="ATTENTION"]{color:var(--red)}.table-wrap{overflow:auto;max-height:440px}#element-list{width:100%;border-collapse:collapse;min-width:760px}#element-list th,#element-list td{padding:8px 9px;border-top:1px solid #edf1f4;text-align:left;font-size:12px}#element-list th{position:sticky;top:0;background:#f5f7f9;z-index:1;font-size:11px}#element-list tr{cursor:pointer}#element-list tr:hover{background:#f7fbff}#element-list tr.selected{background:#e6f1ff}.status-text{font-weight:900}.status-text.CONFIRMED{color:var(--green)}.status-text.INFERRED{color:var(--amber)}.status-text.NOT_OBSERVABLE{color:var(--violet)}.attention-dot{display:inline-block;width:8px;height:8px;border-radius:50%;background:var(--red);margin-right:5px}.decision-section{padding:0 12px 14px}.decision-card{display:grid;grid-template-columns:minmax(0,1.7fr) minmax(300px,.8fr);gap:12px;padding:12px}.decision-title{font-weight:900;font-size:15px}.decision-sub{margin:3px 0 10px;color:var(--muted)}#decision-bar{position:sticky;bottom:0;z-index:70;background:#fff;border-top:1px solid var(--line);padding-top:8px}.decision-buttons{display:grid;grid-template-columns:repeat(5,minmax(120px,1fr));gap:7px}.decision-btn{border:1px solid #b8c4cf;border-radius:8px;padding:10px 8px;background:#fff;text-align:left;min-height:64px}.decision-btn .friendly{display:block;font-weight:900}.decision-btn .code{display:block;margin-top:3px;color:var(--muted);font-size:9px}.decision-btn[data-action="CONFIRM_OBSERVATION"]{background:#f0fbf3;border-color:#a9d9b6;color:#17632d}.decision-btn[data-action="CORRECT_WITH_ADJUDICATION"]{background:#fff7df;border-color:#e6c970;color:#714b00}.decision-btn[data-action="REQUEST_NEW_CAPTURE"]{background:#eef5ff;border-color:#a9c6ef;color:#164a98}.decision-btn[data-action="REQUEST_ADDITIONAL_CONTEXT"]{background:#fff1e7;border-color:#e8b589;color:#82430c}.decision-btn[data-action="REJECT_AND_BLOCK"]{background:#fff0ef;border-color:#e5aaa5;color:#8f2018}.decision-btn:disabled{opacity:.45}.more-actions{margin-top:8px}.more-actions summary{font-weight:800;color:var(--muted)}.more-actions .secondary{display:inline-block;min-height:auto;margin:7px 5px 0 0;padding:7px 9px}.decision-command{display:none;margin-top:9px;padding:9px;background:#f5f7f9;border-radius:7px}.decision-command.show{display:block}.challenge-box{border-left:1px solid var(--line);padding-left:12px}.challenge-row{margin:7px 0}.challenge-row .label{font-size:10px;text-transform:uppercase;color:var(--muted);font-weight:900}.challenge-row .value{margin-top:2px;font-weight:700}.read-only-note{margin-top:9px;padding:8px;border-radius:7px;background:#f7f8fa;color:#526477;font-size:11px}footer{padding:8px 16px 18px;color:#6d7b89;font-size:10px}.hidden{display:none!important}@media (max-width:1100px){.header-grid{grid-template-columns:1fr 1fr}.metrics{grid-template-columns:repeat(3,1fr)}.main-grid{grid-template-columns:1fr}.source-card{position:relative;top:auto}#source-stage{max-height:none}.detail-card{min-height:0}.decision-card{grid-template-columns:1fr}.challenge-box{border-left:0;border-top:1px solid var(--line);padding:10px 0 0}.decision-buttons{grid-template-columns:repeat(3,1fr)}}@media (max-width: 767px){.app-header{position:relative;padding:10px 12px}.header-grid{display:block}.header-grid>div:not(:first-child){display:none}.brand-kicker{font-size:15px}.screen-name{font-size:13px}.review-nav{top:0}.quick-strip{margin:8px 8px 0;padding:7px 8px}.quick-item{font-size:11px}.summary-section{padding:8px 8px 0}.summary-top{align-items:flex-start}.summary-title{font-size:16px}.ready-badge{font-size:10px}.metrics{grid-template-columns:repeat(2,1fr)}.metric strong{font-size:19px}.main-grid{display:block;padding:8px}.main-grid>.page{margin-bottom:8px}.source-card{position:relative}.card-title{font-size:12px}.source-toolbar{position:sticky;top:var(--nav-h);z-index:20}.source-toolbar .element-counter{display:none}#source-stage{max-height:none}.detail-shell{padding:10px}.selected-head{align-items:flex-start}.semantic-type{width:100%;margin:0}.reading-grid,.compare-grid{grid-template-columns:1fr}.reading-cell+.reading-cell,.compare-pane+.compare-pane{border-left:0;border-top:1px solid var(--line)}.elements-section{padding:0 8px 8px}.elements-head{display:block}.search-wrap{margin:8px 0 0}.search-wrap input{width:100%}.table-wrap{max-height:none;overflow:visible}#element-list{min-width:0}#element-list thead{display:none}#element-list,#element-list tbody,#element-list tr,#element-list td{display:block;width:100%}#element-list tr{border-top:1px solid var(--line);padding:9px}#element-list td{border:0;padding:2px 0}#element-list td:nth-child(1){font-weight:900;color:#173d65}#element-list td:nth-child(2){color:var(--muted);font-size:10px}#element-list td:nth-child(3){font-size:14px;font-weight:800}#element-list td:nth-child(4),#element-list td:nth-child(5),#element-list td:nth-child(6){display:inline-block;width:auto;margin-right:9px}.decision-section{padding:0 8px 10px}.decision-buttons{display:flex;overflow-x:auto;scroll-snap-type:x mandatory}.decision-btn{min-width:76vw;scroll-snap-align:start}.decision-card{padding:10px}.page{scroll-margin-top:calc(var(--nav-h) + 8px)}}
</style>
</head>
<body>
<header id="app-header" class="app-header"><div class="header-grid"><div><div class="brand-kicker">P0 VISUAL HUMAN REVIEW V4.2</div><div id="header-screen" class="screen-name"></div></div><div><div class="header-label">Review ID</div><div id="header-review" class="header-value"></div></div><div><div class="header-label">HEAD (Git)</div><div id="header-head" class="header-value mono"></div></div><div><div class="header-label">Resultado máquina</div><div id="header-result" class="header-value"></div></div></div></header>
<nav id="review-nav" class="review-nav"><div id="review-tabs" class="review-tabs"><button class="nav-tab active" data-page="summary">Resumen</button><button class="nav-tab" data-page="screen">Pantalla</button><button class="nav-tab" data-page="elements">Elementos</button><button class="nav-tab" data-page="detail">Detalle</button><button class="nav-tab" data-page="decision">Decisión</button></div></nav>
<div id="binding-banner" class="binding-banner"></div><div id="quick-strip" class="quick-strip"></div>
<section id="summary" class="page summary-section"><div class="summary-card"><div class="summary-top"><div><div class="summary-title">Revisión visual de la pantalla</div><div class="summary-sub">Compara lo visible con lo que interpretó el sistema. Los detalles técnicos están disponibles, pero no bloquean la revisión visual.</div></div><div id="ready-badge" class="ready-badge"></div></div><div id="metrics" class="metrics"></div></div></section>
<div class="main-grid"><section id="screen" class="page card source-card"><div class="card-title"><span>IMAGEN ORIGINAL CON ANOTACIONES</span><small>Toca o haz click en un número para revisar el elemento</small></div><div class="source-toolbar"><button id="zoom-out" class="icon-btn" type="button">−</button><button id="zoom-reset" class="plain-btn" type="button">100%</button><button id="zoom-in" class="icon-btn" type="button">+</button><button id="zoom-fit" class="plain-btn" type="button">Ajustar</button><span class="toolbar-spacer"></span><span id="element-counter" class="element-counter"></span></div><div id="source-stage"><div id="source-canvas">__SOURCE_HTML__<div id="overlay"></div></div></div></section>
<section id="detail" class="page card detail-card"><div class="card-title"><span>DETALLE DEL ELEMENTO SELECCIONADO</span><small id="detail-short-status"></small></div><div id="detail-panel" class="detail-shell"><div class="selected-head"><span id="selected-id" class="selected-id"></span><span id="selected-status" class="status-badge"></span><span id="selected-semantic" class="semantic-type"></span></div><div class="reading-panel"><div class="reading-grid"><div class="reading-cell"><div class="cell-label">Lectura del sistema</div><div id="selected-text" class="cell-value"></div><div id="selected-confidence" class="confidence"></div></div><div class="reading-cell"><div class="cell-label">Cómo interpretarlo</div><div id="selected-role" class="cell-value"></div><div id="selected-group" class="evidence-meta"></div></div></div></div><div id="review-note" class="review-note"></div><div class="compare-card"><div class="mini-title">COMPARACIÓN FUENTE ↔ LECTURA DEL SISTEMA</div><div class="compare-grid"><div class="compare-pane"><div class="compare-heading">FUENTE · evidencia visual</div><div class="crop-wrap"><canvas id="selected-crop"></canvas></div><div id="crop-meta" class="evidence-meta"></div></div><div class="compare-pane"><div class="compare-heading">LECTURA DEL SISTEMA</div><div id="system-reading" class="system-reading"></div><div id="system-meta" class="evidence-meta"></div></div></div></div><div class="detail-tabs"><button class="detail-tab active" data-detail-tab="semantic">Semántica</button><button class="detail-tab" data-detail-tab="visual">Visual</button><button class="detail-tab" data-detail-tab="position">Posición</button><button class="detail-tab" data-detail-tab="relations">Relaciones</button><button class="detail-tab" data-detail-tab="issues">Problemas / omisiones</button></div><div id="tab-semantic" class="detail-tab-panel active"></div><div id="tab-visual" class="detail-tab-panel"></div><div id="tab-position" class="detail-tab-panel"></div><div id="tab-relations" class="detail-tab-panel"></div><div id="tab-issues" class="detail-tab-panel"></div><details class="technical"><summary>Ver detalle técnico / evidencia avanzada</summary><div class="technical-body"><div id="technical-metadata"></div><pre id="selected-json"></pre></div></details></div></section></div>
<section id="elements" class="page elements-section"><div class="card elements-card"><div class="elements-head"><strong id="elements-title"></strong><div class="search-wrap"><input id="search" type="search" placeholder="Buscar por texto, tipo o ID…" aria-label="Buscar elementos"></div></div><div id="filters" class="filters"></div><div class="table-wrap"><table id="element-list"><thead><tr><th>ID</th><th>Tipo</th><th>Texto / descripción</th><th>Estado</th><th>Confianza</th><th>Atención</th></tr></thead><tbody></tbody></table></div></div></section>
<section id="decision" class="page decision-section"><div class="card decision-card"><div><div class="decision-title">DECISIÓN HUMANA REQUERIDA</div><div class="decision-sub">Cuando exista un challenge activo, elige una sola acción. La web prepara la decisión, pero no la publica.</div><div id="decision-bar"><div class="decision-buttons">__ACTION_BUTTONS__</div><details class="more-actions"><summary>Más acciones</summary>__MORE_ACTION_BUTTONS__</details><div id="decision-command" class="decision-command"><div class="cell-label">Decisión preparada</div><div id="decision-command-text" class="mono"></div><button id="copy-decision" class="plain-btn" type="button">Copiar decisión</button></div></div></div><aside class="challenge-box"><div class="challenge-row"><div class="label">Challenge</div><div id="challenge-id" class="value mono"></div></div><div class="challenge-row"><div class="label">Vence</div><div id="challenge-expiry" class="value"></div></div><div class="challenge-row"><div class="label">Issue</div><div id="challenge-issue" class="value"></div></div><div class="challenge-row"><div class="label">Rol requerido</div><div id="challenge-role" class="value"></div></div><div class="read-only-note">La web no publica ni autentica esta decisión. El comentario autenticado y su readback gobernado se realizan fuera de esta interfaz.</div></aside></div></section>
<footer>LF Visual Pipeline · P0 HUMAN REVIEW SHELL V4.2 · presentación humana + evidencia avanzada colapsada</footer>
<script>
const D=__DATA__;const M=D.metadata;const E=D.elements;const A=D.allowed_actions;const pageOrder=['summary','screen','elements','detail','decision'];let selected=0,zoom=1,filter='ALL',query='',navLockUntil=0;const $=s=>document.querySelector(s),$$=s=>[...document.querySelectorAll(s)];const esc=v=>String(v??'');const friendlyStatus=s=>s==='CONFIRMED'?'Confirmado':s==='INFERRED'?'Inferido':s==='NOT_OBSERVABLE'?'No observable':s||'Sin estado';const statusClass=s=>s==='CONFIRMED'?'confirmed':s==='INFERRED'?'inferred':'not-observable';const confidence=e=>{let c=Number(e.confidence);if(!Number.isFinite(c))return '—';if(c<=1)c*=100;return `${c.toFixed(c>=99?0:1)}%`};const region=e=>e.region||{};const hasRegion=e=>{const r=region(e);return [r.x,r.y,r.width,r.height].every(v=>Number.isFinite(Number(v)))&&Number(r.width)>0&&Number(r.height)>0};const fmtBytes=n=>{if(!Number.isFinite(Number(n)))return '—';return Number(n).toLocaleString('es-PE')};
function syncOffsets(){document.documentElement.style.setProperty('--header-h',`${$('#app-header').offsetHeight}px`);document.documentElement.style.setProperty('--nav-h',`${$('#review-nav').offsetHeight}px`)}new ResizeObserver(syncOffsets).observe($('#app-header'));new ResizeObserver(syncOffsets).observe($('#review-nav'));syncOffsets();
function renderHeader(){$('#header-screen').textContent=`Pantalla: ${M.screen}`;$('#header-review').textContent=M.review_id||'Pendiente de challenge';$('#header-head').textContent=M.head||'—';$('#header-result').innerHTML=`<span class="pass-pill">${esc(M.machine_result||'SIN RESULTADO')}</span>`;const q=[['Fuente','REAL'],['Formato','PNG'],['Dimensiones',`${M.source_width||'—'}×${M.source_height||'—'}`],['Bytes',fmtBytes(M.source_bytes)],['Cobertura global',`${Number(M.coverage_percent||0).toFixed(0)}% (${M.counts.total}/${M.counts.total})`]];$('#quick-strip').innerHTML=q.map(([k,v])=>`<div class="quick-item">${k}: <b>${v}</b></div>`).join('');$('#ready-badge').textContent=M.human_review_ready?'Listo para revisión':'No listo para revisión';const metrics=[['Elementos',M.counts.total,''],['Confirmados',M.counts.confirmed,''],['Inferidos',M.counts.inferred,''],['No observables',M.counts.not_observable,''],['Requieren atención',M.counts.uncertainties,'attention'],['Cobertura',`${Number(M.coverage_percent||0).toFixed(0)}%`,'coverage']];$('#metrics').innerHTML=metrics.map(([l,v,c])=>`<div class="metric ${c}"><strong>${v}</strong><span>${l}</span></div>`).join('');$('#element-counter').textContent=`${M.counts.total} elementos detectados`;$('#elements-title').textContent=`LISTA DE ELEMENTOS DETECTADOS (${M.counts.total})`}
function bannerState(){const b=$('#binding-banner');let t='';if(M.expired)t='CHALLENGE EXPIRADO — puedes revisar la evidencia, pero no emitir una decisión válida.';else if(!M.binding_valid)t='EVIDENCE BINDING ERROR — la evidencia no coincide con el challenge activo.';else if(!M.human_review_ready)t='HUMAN_REVIEW_READY=false — la revisión no puede adjudicarse todavía.';else if(!M.challenge_id)t='No hay challenge activo ligado a esta vista. La revisión es solo lectura hasta emitir uno nuevo.';b.textContent=t;b.classList.toggle('show',!!t)}
function buildOverlay(){const w=Number(M.source_width)||1,h=Number(M.source_height)||1;$('#overlay').innerHTML='';E.forEach((e,i)=>{if(!hasRegion(e))return;const r=region(e);const box=document.createElement('button');box.type='button';box.className=`overlay-box ${statusClass(e._review.classification)} ${e._review.uncertain?'attention':''} ${e._review.problem?'problem':''} ${e._review.omission?'omission':''}`;box.style.left=`${Number(r.x)/w*100}%`;box.style.top=`${Number(r.y)/h*100}%`;box.style.width=`${Number(r.width)/w*100}%`;box.style.height=`${Number(r.height)/h*100}%`;box.dataset.index=i;box.setAttribute('aria-label',`Elemento ${i+1}: ${e._display_text}`);box.innerHTML=`<span class="overlay-label">${i+1}</span>`;box.addEventListener('click',()=>selectElement(i,true));$('#overlay').appendChild(box)})}
function labelForAction(a){return {CONFIRM_OBSERVATION:['Todo correcto','Confirmar observación'],CORRECT_WITH_ADJUDICATION:['Corregir lo señalado','Corregir con adjudicación'],REQUEST_NEW_CAPTURE:['Necesito otra captura','Solicitar nueva captura'],REQUEST_ADDITIONAL_CONTEXT:['Falta información','Solicitar contexto adicional'],REJECT_AND_BLOCK:['Rechazar / bloquear','Rechazar y bloquear'],ESCALATE_SECURITY:['Escalar seguridad','Revisión de seguridad'],ESCALATE_PRIVACY:['Escalar privacidad','Revisión de privacidad']}[a]||[a,a]}
function renderDecisionLabels(){$$('.decision-btn').forEach(btn=>{const [friendly,desc]=labelForAction(btn.dataset.action);btn.innerHTML=`<span class="friendly">${friendly}</span><span class="code">${btn.dataset.action}</span>`;btn.title=desc})}
function reviewExplanation(e){const u=e._explicit_uncertainties||[];if(e._review.problem)return ['problem','Existe un problema material asociado a este elemento. Revisa la comparación antes de decidir.'];if(e._review.omission)return ['problem','Este elemento está marcado como posible omisión.'];if(u.length)return ['attention',`Requiere atención: ${u.map(x=>x.code||'incertidumbre').join(', ')}.`];if(e._review.classification==='INFERRED')return ['attention','El sistema infirió esta interpretación a partir de la evidencia visual. Conviene validarla antes de aprobar.'];if(e._review.classification==='NOT_OBSERVABLE')return ['attention','La fuente no permite observar este dato con suficiente certeza.'];return ['','La lectura está confirmada por la evidencia disponible y no tiene incertidumbres explícitas.']}
function kv(k,v){return `<div class="kv"><div class="k">${k}</div><div>${esc(v??'—')}</div></div>`}
function drawCrop(e){const img=$('#source-image'),cv=$('#selected-crop'),r=region(e);if(!img||!img.complete||!hasRegion(e)){cv.width=1;cv.height=1;return}const sx=Math.max(0,Number(r.x)),sy=Math.max(0,Number(r.y)),sw=Math.max(1,Number(r.width)),sh=Math.max(1,Number(r.height));const scale=Math.min(2,520/sw,190/sh);cv.width=Math.max(1,Math.round(sw*scale));cv.height=Math.max(1,Math.round(sh*scale));const ctx=cv.getContext('2d');ctx.clearRect(0,0,cv.width,cv.height);ctx.imageSmoothingEnabled=true;ctx.drawImage(img,sx,sy,sw,sh,0,0,cv.width,cv.height)}
function renderDetail(){const e=E[selected];if(!e)return;const ordinal=e._review.ordinal;$('#selected-id').textContent=`ELEMENTO #${ordinal}`;const sb=$('#selected-status');sb.textContent=friendlyStatus(e._review.classification);sb.className=`status-badge ${statusClass(e._review.classification)}`;$('#detail-short-status').textContent=friendlyStatus(e._review.classification);$('#selected-semantic').textContent=`Tipo semántico: ${e.semantic_role||e.element_type||'—'}`;$('#selected-text').textContent=e._display_text||'Sin texto visible';$('#selected-confidence').textContent=`Confianza ${confidence(e)}`;$('#selected-role').textContent=e.semantic_role||e.element_type||'Elemento visual';$('#selected-group').textContent=e.parent_id?`Relacionado con ${e.parent_id}`:'Sin grupo declarado';const [cls,note]=reviewExplanation(e);const rn=$('#review-note');rn.className=`review-note ${cls}`;rn.textContent=note;$('#system-reading').innerHTML=`<strong>${esc(e._display_text||'Sin texto visible')}</strong><br><span class="evidence-meta">${esc(e.semantic_role||e.element_type||'Elemento visual')} · ${friendlyStatus(e._review.classification)}</span>`;$('#system-meta').textContent=`Confianza ${confidence(e)}`;const r=region(e);$('#crop-meta').textContent=hasRegion(e)?`Región: x ${r.x}, y ${r.y}, w ${r.width}, h ${r.height}`:'Sin región utilizable';drawCrop(e);$('#tab-semantic').innerHTML=kv('Tipo',e.element_type)+kv('Rol',e.semantic_role)+kv('Clasificación',friendlyStatus(e._review.classification))+kv('Confianza',confidence(e))+kv('Texto visible',e._display_text);$('#tab-visual').innerHTML=kv('Atributos visuales','Solo se muestran cuando están declarados por el lector.')+kv('Estilo',e.visual_style||e.style||'No declarado')+kv('Importancia visual',e.visual_importance||'No declarada');$('#tab-position').innerHTML=kv('Región',hasRegion(e)?`x ${r.x}, y ${r.y}, w ${r.width}, h ${r.height}`:'No disponible')+kv('Padre',e.parent_id||'No declarado')+kv('Fuente',M.source_width&&M.source_height?`${M.source_width}×${M.source_height}px`:'—');$('#tab-relations').innerHTML=kv('Parent',e.parent_id||'No declarado')+kv('Subcomponente',e.subcomponent_role||'No declarado')+kv('Evidence refs',(e.evidence_refs||[]).length);const u=(e._explicit_uncertainties||[]).map(x=>x.code||'INCERTIDUMBRE');$('#tab-issues').innerHTML=`<div class="ok-list"><span>Presente en fuente</span><span class="ok">Sí</span><span>Representado en sistema</span><span class="ok">Sí</span><span>Omisión</span><span class="${e._review.omission?'warn':'ok'}">${e._review.omission?'Sí':'No'}</span><span>Problema material</span><span class="${e._review.problem?'warn':'ok'}">${e._review.problem?'Sí':'No'}</span><span>Incertidumbres</span><span class="${u.length?'warn':'ok'}">${u.length?u.join(', '):'Ninguna explícita'}</span></div>`;$('#technical-metadata').innerHTML=kv('ID interno',e._review.element_id)+kv('Reader',M.reader_execution_id)+kv('Pass',M.pass_id)+kv('Candidate SHA',M.candidate_sha256)+kv('Source SHA',M.source_sha256)+kv('HEAD',M.head);$('#selected-json').textContent=JSON.stringify(e,null,2);$$('.overlay-box').forEach(x=>x.classList.toggle('selected',Number(x.dataset.index)===selected));$$('#element-list tbody tr').forEach(x=>x.classList.toggle('selected',Number(x.dataset.index)===selected))}
function selectElement(i,fromVisual=false){if(!Number.isInteger(i)||i<0||i>=E.length)return;selected=i;renderDetail();if(window.innerWidth<768){navLockUntil=Date.now()+900;setActivePage('detail');$('#detail').scrollIntoView({behavior:'smooth',block:'start'})}else if(fromVisual){$('#detail').scrollIntoView({behavior:'smooth',block:'nearest'})}}
function filters(){const f=[['ALL',`Todos (${M.counts.total})`],['CONFIRMED',`Confirmados (${M.counts.confirmed})`],['INFERRED',`Inferidos (${M.counts.inferred})`],['NOT_OBSERVABLE',`No observables (${M.counts.not_observable})`],['ATTENTION',`Requieren atención (${M.counts.uncertainties})`],['PROBLEMS',`Problemas (${M.counts.problems})`],['OMISSIONS',`Omisiones (${M.counts.omissions})`]];$('#filters').innerHTML=f.map(([v,l])=>`<button class="filter ${v===filter?'active':''}" data-filter="${v}" type="button">${l}</button>`).join('');$$('.filter').forEach(b=>b.onclick=()=>{filter=b.dataset.filter;filters();renderRows()})}
function matchesFilter(e){if(filter==='ALL')return true;if(filter==='ATTENTION')return e._review.uncertain;if(filter==='PROBLEMS')return e._review.problem;if(filter==='OMISSIONS')return e._review.omission;return e._review.classification===filter}
function renderRows(){const tbody=$('#element-list tbody');tbody.innerHTML='';E.forEach((e,i)=>{const hay=[e._display_text,e.element_type,e.semantic_role,e._review.element_id].join(' ').toLowerCase();if(query&&!hay.includes(query))return;if(!matchesFilter(e))return;const tr=document.createElement('tr');tr.dataset.index=i;const attention=e._review.uncertain?'<span class="attention-dot"></span>Revisar':'—';tr.innerHTML=`<td>#${e._review.ordinal}</td><td>${esc(e.element_type||'—')}</td><td>${esc(e._display_text||'Elemento visual')}</td><td><span class="status-text ${e._review.classification}">${friendlyStatus(e._review.classification)}</span></td><td>${confidence(e)}</td><td>${attention}</td>`;tr.onclick=()=>selectElement(i,true);tbody.appendChild(tr)});renderDetail()}
function setActivePage(id){$$('.nav-tab').forEach(t=>t.classList.toggle('active',t.dataset.page===id))}$$('.nav-tab').forEach(t=>t.onclick=()=>{navLockUntil=Date.now()+900;setActivePage(t.dataset.page);document.getElementById(t.dataset.page).scrollIntoView({behavior:'smooth',block:'start'})});const io=new IntersectionObserver(entries=>{if(Date.now()<navLockUntil)return;const visible=entries.filter(x=>x.isIntersecting).sort((a,b)=>b.intersectionRatio-a.intersectionRatio)[0];if(visible)setActivePage(visible.target.id)},{rootMargin:'-24% 0px -58% 0px',threshold:[0,.2,.5]});pageOrder.forEach(id=>{const n=document.getElementById(id);if(n)io.observe(n)});let tx=0,ty=0;document.addEventListener('touchstart',ev=>{if(ev.touches.length!==1)return;tx=ev.touches[0].clientX;ty=ev.touches[0].clientY},{passive:true});document.addEventListener('touchend',ev=>{if(window.innerWidth>=768||!ev.changedTouches.length)return;const dx=ev.changedTouches[0].clientX-tx,dy=ev.changedTouches[0].clientY-ty;if(Math.abs(dx)<65||Math.abs(dx)<Math.abs(dy)*1.35)return;const active=$('.nav-tab.active')?.dataset.page||'summary';let idx=pageOrder.indexOf(active);idx+=dx<0?1:-1;idx=Math.max(0,Math.min(pageOrder.length-1,idx));const next=pageOrder[idx];navLockUntil=Date.now()+900;setActivePage(next);document.getElementById(next).scrollIntoView({behavior:'smooth',block:'start'})},{passive:true});function setZoom(v){zoom=Math.max(.5,Math.min(2.5,v));$('#source-canvas').style.width=(zoom*100)+'%';$('#zoom-reset').textContent=`${Math.round(zoom*100)}%`}$('#zoom-in').onclick=()=>setZoom(zoom+.15);$('#zoom-out').onclick=()=>setZoom(zoom-.15);$('#zoom-reset').onclick=()=>setZoom(1);$('#zoom-fit').onclick=()=>setZoom(1);$('#search').addEventListener('input',ev=>{query=ev.target.value.trim().toLowerCase();renderRows()});$$('.detail-tab').forEach(t=>t.onclick=()=>{$$('.detail-tab').forEach(x=>x.classList.remove('active'));$$('.detail-tab-panel').forEach(x=>x.classList.remove('active'));t.classList.add('active');$(`#tab-${t.dataset.detailTab}`).classList.add('active')});const decisionDisabled=M.expired||!M.binding_valid||!M.human_review_ready||!M.challenge_id;renderDecisionLabels();$$('.decision-btn').forEach(btn=>{btn.disabled=decisionDisabled;btn.onclick=()=>{const action=btn.dataset.action;const command=`challenge_id=${M.challenge_id} action=${action}`;$('#decision-command-text').textContent=command;$('#decision-command').classList.add('show')}});$('#copy-decision').onclick=async()=>{const t=$('#decision-command-text').textContent;if(t)await navigator.clipboard.writeText(t)};function renderChallenge(){$('#challenge-id').textContent=M.challenge_id||'Sin challenge activo';$('#challenge-expiry').textContent=M.expires_at||'—';$('#challenge-issue').textContent=`#${M.issue_number||125}`;$('#challenge-role').textContent=M.required_reviewer_role||'P0_VISUAL_ADJUDICATOR'}renderHeader();bannerState();renderChallenge();buildOverlay();filters();renderRows();if($('#source-image'))$('#source-image').addEventListener('load',()=>{buildOverlay();renderDetail()});
</script>
</body></html>'''
