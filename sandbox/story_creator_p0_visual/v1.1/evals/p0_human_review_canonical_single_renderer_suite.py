#!/usr/bin/env python3
"""Regression contract: Human Review V4.2 has one frozen structural renderer."""
from __future__ import annotations

import json
from pathlib import Path

HERE = Path(__file__).resolve()
V11 = HERE.parents[1]
ROOT = HERE.parents[4]
RENDERER = V11 / "scripts" / "p0_human_review_shell_v4.py"
MIGRATION = ROOT / "supabase" / "migrations" / "20260817001205_lf_p0_canonical_human_review_single_renderer_v1.sql"
MATERIALIZER = ROOT / "supabase" / "functions" / "lf-p0-human-review-v42-materialize-v1" / "index.ts"
WEB = ROOT / "supabase" / "functions" / "lf-p0-human-review-web-v1" / "index.ts"
BLOB = "91144c0f3c01f22b84f5c8a79c43a4e378cb9d18"


def main() -> int:
    renderer = RENDERER.read_text(encoding="utf-8")
    migration = MIGRATION.read_text(encoding="utf-8")
    materializer = MATERIALIZER.read_text(encoding="utf-8")
    web = WEB.read_text(encoding="utf-8")

    results: dict[str, bool] = {}
    results["R01_v42_tabs"] = 'data-review-shell-version="4.2"' in renderer and 'id="review-tabs"' in renderer
    results["R02_ordered_pages"] = "pageOrder=['summary','screen','elements','detail','decision']" in renderer
    results["R03_dynamic_observation_count"] = "LISTA DE ELEMENTOS DETECTADOS (${M.counts.total})" in renderer and "${M.counts.total} elementos detectados" in renderer
    results["R04_single_source_background"] = '<div id="source-stage"><div id="source-canvas">__SOURCE_HTML__<div id="overlay"></div>' in renderer
    results["R05_single_selected_crop"] = renderer.count('id="selected-crop"') == 1 and "drawCrop(e)" in renderer
    results["R06_no_parallel_crop_gallery"] = all(x not in renderer.lower() for x in ("crop-gallery", "crops-grid", "all-crops"))
    results["R07_source_title_preserved"] = "IMAGEN ORIGINAL CON ANOTACIONES" in renderer
    results["R08_element_list_preserved"] = 'id="element-list"' in renderer and 'id="detail-panel"' in renderer
    results["R09_db_gate_renderer_blob"] = BLOB in migration and "CANONICAL_V42_RENDERER_BLOB_MISMATCH" in migration
    results["R10_db_gate_structural_markers"] = all(x in migration for x in (
        "CANONICAL_V42_MARKER_MISSING", "M.counts.total", "IMAGEN ORIGINAL CON ANOTACIONES",
        "LISTA DE ELEMENTOS DETECTADOS", "CANONICAL_V42_SELECTED_CROP_COUNT_INVALID",
        "CANONICAL_V42_PARALLEL_CROP_COMPOSITION_FORBIDDEN",
    ))
    results["R11_copy_refresh_retired"] = "CANONICAL_V42_MATERIALIZER_REQUIRED" in migration and "copying an existing BROWSER_REVIEW is forbidden" in migration
    results["R12_presentation_only_metadata"] = "human_language_presentation_only" in migration and "structural_redesign_forbidden" in migration
    results["R13_materializer_fetches_frozen_renderer"] = BLOB in materializer and "GITHUB_RENDERER_FETCH_FAILED" in materializer and "CANONICAL_RENDERER_BLOB_MISMATCH" in materializer
    results["R14_materializer_uses_canonical_publish"] = "fn_lf_p0_publish_canonical_review_v42_v1" in materializer
    results["R15_human_language_after_render"] = "fn_lf_p0_human_review_human_language_v2" in materializer
    results["R16_typed_bindings"] = all(x in materializer for x in ("$3::text", "$4::text", "$5::text", "$2::text"))
    results["R17_web_requires_canonical_markers"] = all(x in web for x in (
        BLOB, "CANONICAL_V42_CONTRACT_MISMATCH", "CANONICAL_CROP_POLICY_MISMATCH",
        "IMAGEN ORIGINAL CON ANOTACIONES", "LISTA DE ELEMENTOS DETECTADOS", "M.counts.total",
    ))

    failed = [name for name, ok in results.items() if not ok]
    print(json.dumps({
        "suite": "P0_HUMAN_REVIEW_CANONICAL_SINGLE_RENDERER",
        "passed": len(results) - len(failed),
        "total": len(results),
        "failed": failed,
        "results": results,
    }, indent=2, sort_keys=True))
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
