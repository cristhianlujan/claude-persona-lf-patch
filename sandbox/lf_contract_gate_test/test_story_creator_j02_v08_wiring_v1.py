#!/usr/bin/env python3
from __future__ import annotations
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[2]
SKILL = ROOT / "skills/creating-integral-user-stories"
WRAPPER = "scripts/validate_screen_decomposition_visual.py"
LEGACY = "scripts/validate_screen_decomposition.py"
REG = "candidate://creating-integral-user-stories/ART_SCRIPT_VALIDATE_SCREEN_DECOMPOSITION_VISUAL"
EXPECTED_SHA = "af30bd17d5c2fb91d1d2932b64e762bfc30cd27f963d0cbf215417c6dc95e7c2"
ACTIVE_DOCS = [
    SKILL / "agents/screen-decomposer.md",
    SKILL / "perfiles/PERFIL_SCREEN_DECOMPOSER_LF.md",
    SKILL / "references/screen-decomposition-protocol.md",
]

def check() -> None:
    actual_sha = hashlib.sha256((SKILL / WRAPPER).read_bytes()).hexdigest()
    assert actual_sha == EXPECTED_SHA, (actual_sha, EXPECTED_SHA)
    for path in ACTIVE_DOCS:
        text = path.read_text(encoding="utf-8")
        assert WRAPPER in text, path
        assert LEGACY not in text, path
        assert "J02_SCREEN_DECOMPOSITION v0.7" not in text, path
    profile = (SKILL / "perfiles/PERFIL_SCREEN_DECOMPOSER_LF.md").read_text(encoding="utf-8")
    assert "J02_SCREEN_DECOMPOSITION v0.8" in profile
    assert EXPECTED_SHA in profile
    assert REG in profile
    judge = (SKILL / "judges/screen-decomposition.yaml").read_text(encoding="utf-8")
    assert "judge_version: v0.8" in judge
    assert f"semantic_validator_ref: {WRAPPER}" in judge
    assert f"semantic_validator_registration_ref: {REG}" in judge
    manifest = (SKILL / "manifest.yaml").read_text(encoding="utf-8")
    assert WRAPPER in manifest
    assert "judge_version: v0.8" in manifest
    assert f"validator: {WRAPPER}" in manifest

if __name__ == "__main__":
    check()
    print("PASS_STORY_CREATOR_J02_V08_WIRING")
