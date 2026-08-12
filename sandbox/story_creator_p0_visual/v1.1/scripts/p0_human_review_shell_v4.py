#!/usr/bin/env python3
"""Responsive, evidence-bound P0 human-review shell.

This module renders the governed review packet as a self-contained HTML document.
It is a presentation/review surface only: it never authenticates a reviewer, posts a
human decision, mutates evidence, or upgrades machine output to human adjudication.
"""
from __future__ import annotations

import base64
import datetime as dt
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
    "data-review-shell-version=\"4.0\"",
    "id=\"review-tabs\"",
    "id=\"source-stage\"",
    "id=\"element-list\"",
    "id=\"detail-panel\"",
    "id=\"decision-bar\"",
    "data-action=\"CONFIRM_OBSERVATION\"",
    "data-action=\"CORRECT_WITH_ADJUDICATION\"",
    "data-action=\"REQUEST_NEW_CAPTURE\"",
    "data-action=\"REQUEST_ADDITIONAL_CONTEXT\"",
    "data-action=\"REJECT_AND_BLOCK\"",
    "ESCALATE_SECURITY",
    "ESCALATE_PRIVACY",
    "@media (max-width: 767px)",
    "touch-action:pan-y",
    "scroll-snap-type:x mandatory",
)


def _safe_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")


def _image_data_uri(path: Path | None) -> str | None:
    if not path or not path.exists():
        return None
    suffix = path.suffix.lower()
    mime = "image/png" if suffix == ".png" else "image/jpeg" if suffix in {".jpg", ".jpeg"} else "application/octet-stream"
    return f"data:{mime};base64,{base64.b64encode(path.read_bytes()).decode('ascii')}"


def _challenge_status(challenge: dict[str, Any] | None) -> dict[str, Any]:
    c = challenge or {}
    expires = c.get("expires_at")
    expired = False
    if expires:
        try:
            parsed = dt.datetime.fromisoformat(str(expires).replace("Z", "+00:00"))
            if parsed.tzinfo is None:
                parsed = parsed.replace(tzinfo=dt.timezone.utc)
            expired = parsed <= dt.datetime.now(dt.timezone.utc)
        except ValueError:
            expired = True
    return {
        "challenge_id": c.get("challenge_id"),
        "review_id": c.get("review_id"),
        "required_reviewer_role": c.get("required_reviewer_role"),
        "source_head_sha": c.get("source_head_sha"),
        "visual_output_sha256": c.get("visual_output_sha256"),
        "packet_manifest_sha256": c.get("packet_manifest_sha256"),
        "source_sha256": c.get("source_sha256"),
        "issue_number": c.get("issue_number", 125),
        "expires_at": expires,
        "expired": expired,
        "binding_valid": c.get("binding_valid", True),
    }


def build_human_review_shell_v4(
    packet: dict[str, Any],
    candidate: dict[str, Any],
    image_path: Path | None = None,
    challenge: dict[str, Any] | None = None,
) -> str:
    """Build a responsive, self-contained P0HR review document.

    The shell is deliberately read-only with respect to evidence. The only generated
    output from a reviewer action is a copyable text command bound to challenge_id;
    authenticated publication/readback remains external governance.
    """
    image_uri = _image_data_uri(image_path)
    challenge_state = _challenge_status(challenge)
    summary = packet.get("screen_summary", {})
    elements = candidate.get("elements", [])
    exceptions = packet.get("human_attention_required", [])
    exception_ids = {str(x.get("element_id")) for x in exceptions if x.get("element_id") is not None}

    enriched = []
    for idx, raw in enumerate(elements, 1):
        e = dict(raw)
        eid = str(e.get("element_id") or f"EL-{idx:04d}")
        classification = str(e.get("classification") or "NOT_OBSERVABLE")
        fidelity = e.get("fidelity_property_status") or {}
        has_problem = eid in exception_ids or any(v == "REMEDIATION_REQUIRED" for v in fidelity.values())
        e["_review"] = {
            "ordinal": idx,
            "element_id": eid,
            "classification": classification,
            "has_problem": has_problem,
            "has_omission": bool(e.get("omission") or e.get("is_omission")),
        }
        enriched.append(e)

    counts = {
        "total": len(enriched),
        "confirmed": sum(1 for e in enriched if e["_review"]["classification"] == "CONFIRMED"),
        "inferred": sum(1 for e in enriched if e["_review"]["classification"] == "INFERRED"),
        "not_observable": sum(1 for e in enriched if e["_review"]["classification"] == "NOT_OBSERVABLE"),
        "problems": sum(1 for e in enriched if e["_review"]["has_problem"]),
        "omissions": sum(1 for e in enriched if e["_review"]["has_omission"]),
    }

    source_sha = candidate.get("source_sha256") or challenge_state.get("source_sha256") or ""
    metadata = {
        "screen": candidate.get("screen_code") or candidate.get("source_image_ref") or candidate.get("execution_id") or "P0 screen",
        "review_id": challenge_state.get("review_id") or "",
        "challenge_id": challenge_state.get("challenge_id") or "",
        "head": challenge_state.get("source_head_sha") or "",
        "source_sha256": source_sha,
        "machine_result": summary.get("visual_fidelity_result") or packet.get("result") or "",
        "human_review_ready": bool(packet.get("human_review_ready")),
        "candidate_sha256": packet.get("candidate_sha256") or "",
        "fidelity_report_sha256": packet.get("fidelity_report_sha256") or "",
        "required_reviewer_role": challenge_state.get("required_reviewer_role") or "P0_VISUAL_ADJUDICATOR",
        "issue_number": challenge_state.get("issue_number", 125),
        "expires_at": challenge_state.get("expires_at") or "",
        "expired": bool(challenge_state.get("expired")),
        "binding_valid": bool(challenge_state.get("binding_valid", True)),
        "counts": counts,
    }

    data = {
        "metadata": metadata,
        "elements": enriched,
        "layout_regions": packet.get("layout_regions", []),
        "typography_summary": packet.get("typography_summary", []),
        "color_summary": packet.get("color_summary", []),
        "text_groups": packet.get("text_groups", []),
        "exceptions": exceptions,
        "reconciliation": packet.get("reconciliation"),
        "remediation_history": packet.get("remediation_history", []),
        "allowed_actions": list(ALLOWED_ACTIONS),
    }

    title = html.escape(str(metadata["screen"]))
    image_html = (
        f'<img id="source-image" alt="Imagen fuente de {title}" src="{image_uri}">'
        if image_uri
        else '<div class="source-placeholder">Imagen fuente no embebida en este artefacto.</div>'
    )

    return f'''<!doctype html>
<html lang="es" data-review-shell-version="4.0">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>P0 Visual Human Review V4 · {title}</title>
<style>
:root{{--navy:#071a2d;--navy2:#0e2944;--panel:#fff;--bg:#eef3f7;--line:#d6dee7;--text:#172334;--muted:#5c6b7b;--green:#1b7f37;--amber:#a96800;--violet:#7051a5;--red:#b42318;--blue:#0b5bd3;--shadow:0 8px 24px rgba(5,27,48,.12);--safe-bottom:max(12px,env(safe-area-inset-bottom));}}
*{{box-sizing:border-box}}html{{scroll-behavior:smooth}}body{{margin:0;background:var(--bg);color:var(--text);font:14px/1.45 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}}button,input{{font:inherit}}button{{cursor:pointer}}.mono{{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;overflow-wrap:anywhere}}.muted{{color:var(--muted)}}
.app-header{{position:sticky;top:0;z-index:50;background:var(--navy);color:white;padding:12px 16px;box-shadow:var(--shadow)}}.header-main{{display:flex;gap:18px;align-items:flex-start;justify-content:space-between}}.brand{{min-width:220px}}.brand strong{{font-size:18px;letter-spacing:.02em}}.brand .screen{{color:#63d9ff;margin-top:4px;font-weight:700}}.meta-grid{{display:grid;grid-template-columns:repeat(4,minmax(130px,1fr));gap:10px;flex:1}}.meta-card{{min-width:0}}.meta-card small{{display:block;color:#b8c7d8;text-transform:uppercase;font-size:10px;font-weight:800}}.meta-card .value{{margin-top:3px;font-size:12px;font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}}.status-pill{{display:inline-flex;align-items:center;border-radius:999px;padding:5px 9px;background:#d9f6dc;color:#155c2c;font-size:11px;font-weight:800}}.status-pill.blocked{{background:#fee4e2;color:#912018}}.summary-strip{{display:flex;gap:10px;flex-wrap:wrap;background:#fff4c2;color:#243041;padding:8px 14px;border-bottom:1px solid #ead98e}}.metric{{font-size:12px}}.metric b{{margin-left:4px}}
.review-nav{{position:sticky;top:75px;z-index:45;background:var(--navy2);padding:0 12px;box-shadow:0 5px 16px rgba(5,27,48,.12)}}#review-tabs{{display:flex;gap:4px;overflow-x:auto;scrollbar-width:thin}}.nav-tab{{border:0;background:transparent;color:#dce8f3;padding:12px 14px;font-weight:750;white-space:nowrap;border-bottom:3px solid transparent}}.nav-tab.active{{color:white;border-color:#60a5fa;background:rgba(255,255,255,.06)}}.binding-banner{{margin:12px 12px 0;padding:11px 14px;border-radius:10px;background:#fee4e2;border:1px solid #f6b9b3;color:#7a271a;font-weight:750;display:none}}.binding-banner.show{{display:block}}
.workspace{{display:grid;grid-template-columns:minmax(0,1.05fr) minmax(420px,.95fr);gap:12px;padding:12px;align-items:start}}.card{{background:var(--panel);border:1px solid var(--line);border-radius:10px;box-shadow:0 2px 8px rgba(5,27,48,.06);overflow:hidden}}.card-title{{background:var(--navy);color:white;padding:9px 11px;font-size:12px;font-weight:850;text-transform:uppercase;letter-spacing:.02em}}.source-card{{position:sticky;top:126px}}.source-toolbar{{display:flex;gap:8px;align-items:center;padding:8px;border-bottom:1px solid var(--line);background:#f7fafc;flex-wrap:wrap}}.source-toolbar button{{border:1px solid #b9c7d5;background:white;border-radius:7px;padding:6px 9px}}.source-toolbar .spacer{{flex:1}}#source-stage{{position:relative;background:#f5f7f9;overflow:auto;min-height:380px;max-height:calc(100vh - 245px);touch-action:pan-y}}.source-canvas{{position:relative;transform-origin:top left;display:inline-block;min-width:100%}}#source-image{{display:block;max-width:100%;height:auto;margin:auto}}.source-placeholder{{padding:90px 24px;text-align:center;color:var(--muted)}}#overlay{{position:absolute;inset:0;width:100%;height:100%;pointer-events:none}}.ov-box{{position:absolute;border:2px solid var(--green);background:rgba(27,127,55,.05);pointer-events:auto;cursor:pointer;min-width:10px;min-height:10px}}.ov-box.inferred{{border-color:var(--amber);background:rgba(169,104,0,.06)}}.ov-box.not-observable{{border-color:var(--violet);background:rgba(112,81,165,.06);border-style:dashed}}.ov-box.problem,.ov-box.omission{{border-color:var(--red);background:rgba(180,35,24,.08)}}.ov-box.selected{{outline:3px solid var(--blue);z-index:4}}.ov-label{{position:absolute;left:-2px;top:-22px;border-radius:5px 5px 5px 0;background:currentColor;color:white;padding:2px 6px;font-size:10px;font-weight:900;box-shadow:0 2px 5px rgba(0,0,0,.18)}}
.detail-card{{min-height:560px}}.detail-head{{display:flex;align-items:center;gap:8px;padding:12px;border-bottom:1px solid var(--line)}}.detail-head h2{{font-size:16px;margin:0}}.classification{{border:1px solid currentColor;border-radius:6px;padding:3px 7px;font-size:11px;font-weight:850}}.classification.CONFIRMED{{color:var(--green)}}.classification.INFERRED{{color:var(--amber)}}.classification.NOT_OBSERVABLE{{color:var(--violet)}}.detail-summary{{display:grid;grid-template-columns:1fr 1fr;gap:1px;background:var(--line);border-bottom:1px solid var(--line)}}.kv{{background:white;padding:9px 11px}}.kv small{{display:block;color:var(--muted);font-size:10px;text-transform:uppercase;font-weight:800}}.kv b{{display:block;margin-top:2px}}.compare{{display:grid;grid-template-columns:1fr 1fr;gap:10px;padding:11px}}.compare-box{{border:1px solid var(--line);border-radius:8px;padding:10px;min-height:100px}}.compare-box strong{{display:block;color:var(--blue);font-size:11px;text-transform:uppercase;margin-bottom:8px}}.crop{{max-width:100%;border:1px solid var(--line);background:#f7f7f7}}.subtabs{{display:flex;overflow:auto;border-top:1px solid var(--line);border-bottom:1px solid var(--line)}}.subtab{{border:0;background:white;padding:9px 11px;white-space:nowrap;font-size:11px;font-weight:800;color:var(--muted)}}.subtab.active{{color:var(--blue);box-shadow:inset 0 -2px var(--blue)}}.subpane{{padding:11px;min-height:180px}}.subpane pre{{white-space:pre-wrap;overflow-wrap:anywhere;margin:0;background:#f7f9fb;border-radius:8px;padding:10px;font-size:11px}}.reconcile{{display:grid;grid-template-columns:1fr auto;gap:6px;padding:8px;border-radius:8px;background:#f6fbf7}}.ok{{color:var(--green);font-weight:800}}.warn{{color:var(--amber);font-weight:800}}.bad{{color:var(--red);font-weight:800}}
.elements-card{{margin:0 12px 12px}}.filters{{display:flex;gap:6px;padding:9px;border-bottom:1px solid var(--line);overflow:auto;align-items:center}}.filter{{border:1px solid var(--line);background:white;border-radius:999px;padding:6px 10px;white-space:nowrap;font-size:11px;font-weight:800}}.filter.active{{background:#e9f2ff;border-color:#98bfff;color:#174ea6}}.search{{margin-left:auto;min-width:240px;border:1px solid var(--line);border-radius:7px;padding:7px 9px}}.element-table-wrap{{overflow:auto;max-height:380px}}table{{border-collapse:collapse;width:100%}}th,td{{padding:8px;border-bottom:1px solid #edf0f3;text-align:left;vertical-align:top}}th{{position:sticky;top:0;background:#f7f9fb;font-size:11px;color:#445467;z-index:2}}tr[data-element-id]{{cursor:pointer}}tr[data-element-id]:hover{{background:#f7fbff}}tr.selected{{background:#e8f2ff}}.tag{{display:inline-block;border-radius:4px;padding:2px 5px;font-size:10px;font-weight:850;border:1px solid currentColor}}.mobile-cards{{display:none;padding:8px}}.element-card{{border:1px solid var(--line);border-radius:9px;padding:10px;margin-bottom:8px;background:white}}.element-card.selected{{outline:2px solid var(--blue)}}.review-pages{{display:contents}}.review-page{{scroll-margin-top:128px}}
.decision-spacer{{height:102px}}#decision-bar{{position:fixed;left:0;right:0;bottom:0;z-index:60;background:rgba(255,255,255,.98);border-top:1px solid var(--line);box-shadow:0 -8px 24px rgba(5,27,48,.14);padding:9px 12px calc(9px + env(safe-area-inset-bottom))}}.decision-inner{{display:flex;gap:8px;align-items:center;max-width:1600px;margin:auto}}.decision-title{{font-weight:900;min-width:160px}}.action{{border:1px solid var(--line);border-radius:8px;background:white;padding:8px 10px;font-weight:800;min-height:44px}}.action.good{{color:var(--green);border-color:#8fd49e;background:#f1fbf3}}.action.warn{{color:#8a5800;border-color:#efc36f;background:#fff8e7}}.action.info{{color:#174ea6;border-color:#a8c6f5;background:#f1f6ff}}.action.bad{{color:var(--red);border-color:#f0a7a0;background:#fff2f1}}.action:disabled{{opacity:.45;cursor:not-allowed}}.decision-inner .spacer{{flex:1}}.more{{position:relative}}.more-menu{{display:none;position:absolute;right:0;bottom:52px;background:white;border:1px solid var(--line);border-radius:8px;box-shadow:var(--shadow);padding:6px;min-width:220px}}.more.open .more-menu{{display:block}}.modal{{position:fixed;inset:0;z-index:100;background:rgba(1,15,28,.58);display:none;align-items:center;justify-content:center;padding:16px}}.modal.open{{display:flex}}.modal-card{{width:min(620px,100%);max-height:90vh;overflow:auto;background:white;border-radius:12px;box-shadow:var(--shadow)}}.modal-head{{background:var(--navy);color:white;padding:14px 16px;font-weight:850}}.modal-body{{padding:16px}}.modal-actions{{display:flex;gap:8px;justify-content:flex-end;padding:12px 16px;border-top:1px solid var(--line)}}.command{{background:#f5f7fa;border:1px solid var(--line);border-radius:8px;padding:11px;overflow-wrap:anywhere}}.toast{{position:fixed;right:16px;bottom:120px;z-index:110;background:#102a43;color:white;padding:9px 12px;border-radius:8px;opacity:0;transform:translateY(10px);transition:.2s;pointer-events:none}}.toast.show{{opacity:1;transform:none}}
@media (max-width: 1100px){{.workspace{{grid-template-columns:1fr}}.source-card{{position:relative;top:auto}}#source-stage{{max-height:none}}.meta-grid{{grid-template-columns:repeat(2,1fr)}}.review-nav{{top:84px}}}}
@media (max-width: 767px){{body{{padding-bottom:88px}}.app-header{{padding:9px 10px}}.header-main{{display:block}}.brand{{min-width:0}}.brand strong{{font-size:15px}}.meta-grid{{grid-template-columns:1fr 1fr;margin-top:8px;gap:6px}}.meta-card:nth-child(n+3){{display:none}}.summary-strip{{padding:6px 9px;gap:7px;overflow-x:auto;flex-wrap:nowrap}}.metric{{white-space:nowrap}}.review-nav{{top:105px;padding:0 6px}}#review-tabs{{scroll-snap-type:x mandatory;overscroll-behavior-x:contain}}.nav-tab{{scroll-snap-align:start;padding:10px 12px}}.workspace{{padding:8px;display:block}}.review-pages{{display:flex;overflow-x:auto;scroll-snap-type:x mandatory;scroll-behavior:smooth;touch-action:pan-y;gap:8px}}.review-page{{min-width:100%;scroll-snap-align:start}}.source-card{{position:relative}}#source-stage{{min-height:270px;max-height:58vh}}.detail-card{{min-height:auto}}.detail-summary,.compare{{grid-template-columns:1fr}}.elements-card{{margin:0 8px 8px}}.element-table-wrap{{display:none}}.mobile-cards{{display:block;max-height:55vh;overflow:auto}}.filters{{position:sticky;top:144px;z-index:20;background:white}}.search{{min-width:160px;margin-left:0}}#decision-bar{{padding:7px 8px calc(7px + var(--safe-bottom));overflow-x:auto}}.decision-inner{{min-width:max-content}}.decision-title{{display:none}}.action{{padding:7px 9px;min-height:44px;font-size:11px}}.decision-inner .spacer{{display:none}}}}
@media (prefers-reduced-motion:reduce){{*{{scroll-behavior:auto!important;transition:none!important}}}}
</style>
</head>
<body>
<header class="app-header"><div class="header-main"><div class="brand"><strong>P0 VISUAL HUMAN REVIEW V4</strong><div class="screen" id="screen-name"></div></div><div class="meta-grid"><div class="meta-card"><small>Review ID</small><div class="value mono" id="review-id"></div></div><div class="meta-card"><small>HEAD (Git)</small><div class="value mono" id="head-sha"></div></div><div class="meta-card"><small>Source SHA256</small><div class="value mono" id="source-sha"></div></div><div class="meta-card"><small>Resultado máquina</small><div class="value"><span class="status-pill" id="machine-result"></span></div></div></div></div></header>
<div class="summary-strip" id="summary-strip"></div>
<nav class="review-nav"><div id="review-tabs" aria-label="Navegación de revisión"><button class="nav-tab active" data-target="summary">Resumen</button><button class="nav-tab" data-target="screen">Pantalla</button><button class="nav-tab" data-target="elements">Elementos</button><button class="nav-tab" data-target="detail">Detalle</button><button class="nav-tab" data-target="decision">Decisión</button></div></nav>
<div class="binding-banner" id="binding-banner"></div>
<main><section class="workspace review-pages" id="review-pages"><article class="card source-card review-page" data-page="screen" id="screen"><div class="card-title">Imagen original con anotaciones</div><div class="source-toolbar"><button id="zoom-out" aria-label="Alejar">−</button><b id="zoom-label">100%</b><button id="zoom-in" aria-label="Acercar">+</button><button id="zoom-fit">Ajustar</button><button id="zoom-full">Pantalla completa</button><span class="spacer"></span><span id="visible-count"></span></div><div id="source-stage"><div class="source-canvas" id="source-canvas">{image_html}<div id="overlay" aria-label="Overlay de elementos"></div></div></div></article><article class="card detail-card review-page" data-page="detail" id="detail"><div class="card-title">Detalle del elemento seleccionado</div><div id="detail-panel"></div></article></section>
<section class="card elements-card review-page" data-page="elements" id="elements"><div class="card-title">Lista de elementos detectados</div><div class="filters" id="filter-bar"><button class="filter active" data-filter="ALL">Todos</button><button class="filter" data-filter="CONFIRMED">Confirmed</button><button class="filter" data-filter="INFERRED">Inferred</button><button class="filter" data-filter="NOT_OBSERVABLE">Not Observable</button><button class="filter" data-filter="PROBLEMS">Problemas</button><button class="filter" data-filter="OMISSIONS">Omisiones</button><input class="search" id="search" placeholder="Buscar por ID, texto, tipo o grupo" aria-label="Buscar elementos"></div><div class="element-table-wrap"><table><thead><tr><th>ID</th><th>Tipo</th><th>Texto / descripción</th><th>Estado</th><th>Confianza</th><th>Grupo / rol</th><th>Problema</th></tr></thead><tbody id="element-list"></tbody></table></div><div class="mobile-cards" id="mobile-element-list"></div></section>
<section class="card elements-card review-page" data-page="summary" id="summary"><div class="card-title">Resumen de revisión</div><div class="subpane" id="summary-panel"></div></section><section class="review-page" data-page="decision" id="decision"><div class="decision-spacer"></div></section></main><div class="decision-spacer"></div>
<footer id="decision-bar"><div class="decision-inner"><div class="decision-title">Decisión humana requerida</div><button class="action good" data-action="CONFIRM_OBSERVATION">✓ Todo correcto</button><button class="action warn" data-action="CORRECT_WITH_ADJUDICATION">✎ Corregir lo señalado</button><button class="action info" data-action="REQUEST_NEW_CAPTURE">↻ Necesito otra captura</button><button class="action warn" data-action="REQUEST_ADDITIONAL_CONTEXT">! Falta información</button><button class="action bad" data-action="REJECT_AND_BLOCK">⊘ Rechazar / bloquear</button><span class="spacer"></span><div class="more"><button class="action" id="more-actions">Más acciones</button><div class="more-menu"><button class="action bad" data-action="ESCALATE_SECURITY">Escalar seguridad</button><button class="action bad" data-action="ESCALATE_PRIVACY">Escalar privacidad</button></div></div></div></footer>
<div class="modal" id="decision-modal" role="dialog" aria-modal="true" aria-labelledby="decision-title"><div class="modal-card"><div class="modal-head" id="decision-title">Decisión humana</div><div class="modal-body" id="decision-body"></div><div class="modal-actions"><button class="action" id="decision-cancel">Volver</button><button class="action info" id="decision-copy">Preparar / copiar decisión</button></div></div></div><div class="toast" id="toast">Copiado</div>
<script id="review-data" type="application/json">{_safe_json(data)}</script>
<script>
(()=>{{
const D=JSON.parse(document.getElementById('review-data').textContent), M=D.metadata, els=D.elements||[];const $=s=>document.querySelector(s), $$=s=>[...document.querySelectorAll(s)];const esc=s=>String(s??'').replace(/[&<>\"']/g,c=>({{'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',"'":'&#39;'}}[c]));const clip=s=>s?String(s).slice(0,16)+(String(s).length>16?'…':''):'—';
$('#screen-name').textContent=M.screen;$('#review-id').textContent=M.review_id||'—';$('#head-sha').textContent=clip(M.head);$('#source-sha').textContent=clip(M.source_sha256);$('#machine-result').textContent=M.machine_result||'UNKNOWN';if(!M.human_review_ready)$('#machine-result').classList.add('blocked');const metrics=[['Elementos',M.counts.total],['Confirmed',M.counts.confirmed],['Inferred',M.counts.inferred],['Not observable',M.counts.not_observable],['Problemas',M.counts.problems],['Omisiones',M.counts.omissions],['Human-ready',M.human_review_ready?'Sí':'No']];$('#summary-strip').innerHTML=metrics.map(x=>`<span class="metric">${{x[0]}}:<b>${{x[1]}}</b></span>`).join('');
const decisionDisabled=M.expired||!M.binding_valid||!M.human_review_ready||!M.challenge_id;if(decisionDisabled){{$$('.action[data-action]').forEach(b=>b.disabled=true);const b=$('#binding-banner');b.classList.add('show');b.textContent=M.expired?'CHALLENGE EXPIRADO — puedes consultar evidencia, pero no emitir una decisión válida.':!M.binding_valid?'EVIDENCE BINDING ERROR — la evidencia no coincide con el challenge activo.':!M.human_review_ready?'HUMAN_REVIEW_READY=false — adjudicación deshabilitada.':'No hay challenge activo ligado a esta vista; adjudicación deshabilitada.';}}
let selected=0,filter='ALL',q='',zoom=1;function region(e){{const g=e.geometry||{{}},n=g.viewport_box_normalized||null;if(n&&[n.x,n.y,n.width,n.height].every(v=>typeof v==='number'))return n;const r=e.region||{{}},img=$('#source-image');if(img&&r.width&&r.height&&img.naturalWidth&&img.naturalHeight)return{{x:r.x/img.naturalWidth,y:r.y/img.naturalHeight,width:r.width/img.naturalWidth,height:r.height/img.naturalHeight}};return null;}}function stateClass(e){{const r=e._review||{{}};if(r.has_omission)return'omission';if(r.has_problem)return'problem';if(r.classification==='INFERRED')return'inferred';if(r.classification==='NOT_OBSERVABLE')return'not-observable';return'';}}
function renderOverlay(){{const o=$('#overlay');o.innerHTML='';els.forEach((e,i)=>{{const r=region(e);if(!r)return;const b=document.createElement('button');b.type='button';b.className='ov-box '+stateClass(e)+(i===selected?' selected':'');b.style.left=(r.x*100)+'%';b.style.top=(r.y*100)+'%';b.style.width=(r.width*100)+'%';b.style.height=(r.height*100)+'%';b.dataset.index=i;b.title=`#${{i+1}} ${{e.element_type||''}} ${{e.visible_text||e.semantic_role||''}} ${{e._review?.classification||''}}`;b.setAttribute('aria-label',b.title);b.innerHTML=`<span class="ov-label">${{i+1}}</span>`;b.addEventListener('click',()=>select(i,true));o.appendChild(b);}});}}
function matches(e){{const r=e._review||{{}},text=[r.element_id,e.element_type,e.visible_text,e.semantic_role,e.parent_id].join(' ').toLowerCase();if(q&&!text.includes(q))return false;if(filter==='CONFIRMED'||filter==='INFERRED'||filter==='NOT_OBSERVABLE')return r.classification===filter;if(filter==='PROBLEMS')return r.has_problem;if(filter==='OMISSIONS')return r.has_omission;return true;}}
function renderList(){{const visible=els.map((e,i)=>[e,i]).filter(([e])=>matches(e));$('#visible-count').textContent=`${{visible.length}} / ${{els.length}} elementos`;$('#element-list').innerHTML=visible.map(([e,i])=>`<tr data-element-id="${{esc(e._review.element_id)}}" data-index="${{i}}" class="${{i===selected?'selected':''}}"><td>#${{i+1}}</td><td>${{esc(e.element_type||'—')}}</td><td>${{esc(e.visible_text||e.semantic_role||'—')}}</td><td><span class="tag">${{esc(e._review.classification)}}</span></td><td>${{typeof e.confidence==='number'?(e.confidence*100).toFixed(1)+'%':'—'}}</td><td>${{esc(e.semantic_role||e.parent_id||'—')}}</td><td>${{e._review.has_problem?'Sí':'No'}}</td></tr>`).join('');$('#mobile-element-list').innerHTML=visible.map(([e,i])=>`<div class="element-card ${{i===selected?'selected':''}}" data-index="${{i}}"><b>#${{i+1}} · ${{esc(e.visible_text||e.element_type||'Elemento')}}</b><div><span class="tag">${{esc(e._review.classification)}}</span> · ${{esc(e.element_type||'—')}}</div><div class="muted">${{typeof e.confidence==='number'?(e.confidence*100).toFixed(1)+'%':'Confianza —'}}</div></div>`).join('');$$('[data-index]').forEach(x=>x.addEventListener('click',()=>select(Number(x.dataset.index),true)));}}
function cropFor(e){{const refs=e.evidence_refs||[];return refs.length?`<div class="command mono">${{esc(refs.join('\n'))}}</div>`:'<span class="muted">Sin crop embebido; evidencia referenciada en el packet.</span>';}}
function renderDetail(){{const e=els[selected];if(!e){{$('#detail-panel').innerHTML='<div class="subpane muted">Sin elementos.</div>';return}}const r=e._review||{{}},g=e.geometry||{{}},statuses=e.fidelity_property_status||{{}};const checks=[['Presente en candidato',true],['Representado en sistema',true],['Sin remediación pendiente',!Object.values(statuses).includes('REMEDIATION_REQUIRED')],['Sin contradicción marcada',!r.has_problem],['Sin omisión marcada',!r.has_omission]];$('#detail-panel').innerHTML=`<div class="detail-head"><h2>ELEMENTO #${{selected+1}}</h2><span class="classification ${{esc(r.classification)}}">${{esc(r.classification)}}</span><span class="muted mono">${{esc(r.element_id)}}</span></div><div class="detail-summary"><div class="kv"><small>Texto / descripción</small><b>${{esc(e.visible_text||e.semantic_role||'—')}}</b></div><div class="kv"><small>Tipo semántico</small><b>${{esc(e.element_type||'—')}}</b></div><div class="kv"><small>Confianza</small><b>${{typeof e.confidence==='number'?(e.confidence*100).toFixed(1)+'%':'—'}}</b></div><div class="kv"><small>Grupo / parent</small><b>${{esc(e.semantic_role||e.parent_id||'—')}}</b></div></div><div class="compare"><div class="compare-box"><strong>Fuente / evidencia</strong>${{cropFor(e)}}</div><div class="compare-box"><strong>Lectura del sistema</strong><b>${{esc(e.visible_text||e.semantic_role||'—')}}</b><div>${{esc(e.element_type||'—')}}</div><div>${{esc(r.classification)}}</div></div></div><div class="subtabs"><button class="subtab active" data-pane="semantic">Semántica</button><button class="subtab" data-pane="visual">Atributos visuales</button><button class="subtab" data-pane="position">Posición</button><button class="subtab" data-pane="relations">Relaciones</button><button class="subtab" data-pane="problems">Problemas / omisiones</button></div><div class="subpane" id="subpane"></div>`;const panes={{semantic:{{element_type:e.element_type,semantic_role:e.semantic_role,classification:r.classification,visible_text:e.visible_text,confidence:e.confidence,parent_id:e.parent_id}},visual:e.visual_style||{{}},position:{{region:e.region,geometry:g}},relations:(D.reconciliation?.reconciliations||[]).filter(x=>x.element_id===r.element_id),problems:{{checks,exception:(D.exceptions||[]).filter(x=>String(x.element_id)===r.element_id),fidelity_property_status:statuses}}}};function pane(name){{const v=panes[name];if(name==='problems')$('#subpane').innerHTML='<div class="reconcile">'+checks.map(x=>`<span>${{esc(x[0])}}</span><span class="${{x[1]?'ok':'bad'}}">${{x[1]?'Sí':'No'}}</span>`).join('')+'</div><pre>'+esc(JSON.stringify(v,null,2))+'</pre>';else $('#subpane').innerHTML='<pre>'+esc(JSON.stringify(v,null,2))+'</pre>';}}pane('semantic');$$('.subtab').forEach(b=>b.addEventListener('click',()=>{{$$('.subtab').forEach(x=>x.classList.toggle('active',x===b));pane(b.dataset.pane);}}));}}
function select(i,focusDetail=false){{selected=Math.max(0,Math.min(els.length-1,i));renderOverlay();renderList();renderDetail();if(focusDetail&&innerWidth<768)goPage('detail');}}function renderSummary(){{const represented=M.counts.total;$('#summary-panel').innerHTML=`<div class="detail-summary"><div class="kv"><small>Fuente</small><b class="mono">${{esc(clip(M.source_sha256))}}</b></div><div class="kv"><small>Elementos</small><b>${{M.counts.total}}</b></div><div class="kv"><small>Representados</small><b>${{represented}}</b></div><div class="kv"><small>Confirmed / Inferred / Not observable</small><b>${{M.counts.confirmed}} / ${{M.counts.inferred}} / ${{M.counts.not_observable}}</b></div><div class="kv"><small>Problemas / omisiones</small><b>${{M.counts.problems}} / ${{M.counts.omissions}}</b></div><div class="kv"><small>Human review</small><b>${{decisionDisabled?'NO HABILITADA':'PENDIENTE'}}</b></div></div>`;}}function setZoom(v){{zoom=Math.max(.5,Math.min(3,v));$('#source-canvas').style.transform=`scale(${{zoom}})`;$('#zoom-label').textContent=Math.round(zoom*100)+'%';}}
$('#zoom-in').onclick=()=>setZoom(zoom+.1);$('#zoom-out').onclick=()=>setZoom(zoom-.1);$('#zoom-fit').onclick=()=>setZoom(1);$('#zoom-full').onclick=()=>$('#source-stage').requestFullscreen?.();$$('.filter').forEach(b=>b.addEventListener('click',()=>{{filter=b.dataset.filter;$$('.filter').forEach(x=>x.classList.toggle('active',x===b));renderList();}}));$('#search').addEventListener('input',e=>{{q=e.target.value.trim().toLowerCase();renderList();}});function goPage(name){{$$('.nav-tab').forEach(b=>b.classList.toggle('active',b.dataset.target===name));const el=document.querySelector(`[data-page="${{name}}"]`)||document.getElementById(name);if(innerWidth<768&&el?.parentElement?.id==='review-pages')el.scrollIntoView({{behavior:'smooth',block:'nearest',inline:'start'}});else el?.scrollIntoView({{behavior:'smooth',block:'start'}});}}$$('.nav-tab').forEach(b=>b.addEventListener('click',()=>goPage(b.dataset.target)));
let sx=0,sy=0;$('#review-pages').addEventListener('touchstart',e=>{{sx=e.touches[0].clientX;sy=e.touches[0].clientY}},{{passive:true}});$('#review-pages').addEventListener('touchend',e=>{{if(innerWidth>=768)return;const dx=e.changedTouches[0].clientX-sx,dy=e.changedTouches[0].clientY-sy;if(Math.abs(dx)>70&&Math.abs(dx)>Math.abs(dy)*1.4)goPage(dx<0?'detail':'screen');}},{{passive:true}});$('#more-actions').onclick=()=>$('.more').classList.toggle('open');
function openDecision(action){{const cmd=`challenge_id=${{M.challenge_id}} action=${{action}}`;$('#decision-body').innerHTML=`<p><b>Challenge:</b> <span class="mono">${{esc(M.challenge_id||'—')}}</span></p><p><b>Acción:</b> <span class="mono">${{esc(action)}}</span></p><p><b>Pantalla:</b> ${{esc(M.screen)}}</p><p><b>Elementos:</b> ${{M.counts.total}}</p><p><b>Problemas:</b> ${{M.counts.problems}} · <b>Omisiones:</b> ${{M.counts.omissions}}</p><p class="muted">La web no publica ni autentica esta decisión. Debe publicarse mediante el proveedor autenticado gobernado y luego releerse.</p><div class="command mono" id="decision-command">${{esc(cmd)}}</div>`;$('#decision-modal').classList.add('open');}}$$('.action[data-action]').forEach(b=>b.addEventListener('click',()=>openDecision(b.dataset.action)));$('#decision-cancel').onclick=()=>$('#decision-modal').classList.remove('open');$('#decision-modal').addEventListener('click',e=>{{if(e.target.id==='decision-modal')e.currentTarget.classList.remove('open')}});$('#decision-copy').onclick=async()=>{{const t=$('#decision-command')?.textContent||'';try{{await navigator.clipboard.writeText(t)}}catch{{const ta=document.createElement('textarea');ta.value=t;document.body.appendChild(ta);ta.select();document.execCommand('copy');ta.remove()}}const toast=$('#toast');toast.classList.add('show');setTimeout(()=>toast.classList.remove('show'),1200);}};document.addEventListener('keydown',e=>{{if(e.key==='ArrowRight'&&document.activeElement?.tagName!=='INPUT')select(selected+1);if(e.key==='ArrowLeft'&&document.activeElement?.tagName!=='INPUT')select(selected-1);if(e.key==='Escape')$('#decision-modal').classList.remove('open');if(e.key==='+')setZoom(zoom+.1);if(e.key==='-')setZoom(zoom-.1);}});renderSummary();renderList();renderOverlay();renderDetail();
}})();
</script>
</body></html>'''


def validate_human_review_shell_v4(doc: str) -> dict[str, Any]:
    missing = [marker for marker in SHELL_MARKERS if marker not in doc]
    forbidden = []
    lowered = doc.lower()
    for token in ("github token", "authorization: bearer", "service_role_key", "supabase_service_role"):
        if token in lowered:
            forbidden.append(token)
    return {"pass": not missing and not forbidden, "missing": missing, "forbidden": forbidden}
