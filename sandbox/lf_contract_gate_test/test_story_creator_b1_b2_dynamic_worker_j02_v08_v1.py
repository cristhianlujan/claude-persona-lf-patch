#!/usr/bin/env python3
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SKILL = ROOT / "skills" / "creating-integral-user-stories"
WRAPPER = SKILL / "scripts" / "validate_screen_decomposition_visual.py"
EXPECTED_SHA256 = "af30bd17d5c2fb91d1d2932b64e762bfc30cd27f963d0cbf215417c6dc95e7c2"
REGISTRATION = "candidate://creating-integral-user-stories/ART_SCRIPT_VALIDATE_SCREEN_DECOMPOSITION_VISUAL"


def text(rel: str) -> str:
    return (SKILL / rel).read_text(encoding="utf-8")


def check() -> None:
    # B1: new delegated work is selected by governed binding, never by a fixed profile.
    schema = text("schemas/task-packet.schema.json")
    assert '"title":"LF Task Packet v0.4"' in schema
    assert '"worker_binding"' in schema
    assert '"resolution_mode":{"const":"ORCHESTRATOR_RESOLVED"}' in schema
    assert '"entry_guard_decision":{"const":"ORCHESTRATOR_ENTRY_ACCEPTED"}' in schema
    assert '"worker_profile"' in schema  # compatibility projection remains optional
    required_prefix = schema.split('"properties"', 1)[0]
    assert '"worker_profile"' not in required_prefix

    ingestor = text("agents/screen-ingestor.md")
    assert "no se hardcodea un `PERFIL_SCREEN_INGESTOR_LF`" in ingestor
    assert "ORCHESTRATOR_RESOLVED" in ingestor
    assert "futuro worker de backend" in ingestor

    # B2: active J02 source wiring is the visual v0.8 wrapper and denominator is 26.
    assert hashlib.sha256(WRAPPER.read_bytes()).hexdigest() == EXPECTED_SHA256
    judge = text("judges/screen-decomposition.yaml")
    assert "judge_version: v0.8" in judge
    assert "semantic_validator_ref: scripts/validate_screen_decomposition_visual.py" in judge
    assert f"semantic_validator_registration_ref: {REGISTRATION}" in judge
    assert "assertion_denominator: 26" in judge
    for assertion in (
        "visual_observation_coverage",
        "confirmed_epistemic_invariants",
        "confirmed_inherited_inference",
    ):
        assert f"assertion_id: {assertion}" in judge
    assert "assertions_passed=26" in judge
    assert "assertions_total=26" in judge

    for rel in (
        "agents/screen-decomposer.md",
        "perfiles/PERFIL_SCREEN_DECOMPOSER_LF.md",
        "references/screen-decomposition-protocol.md",
    ):
        body = text(rel)
        assert "validate_screen_decomposition_visual.py" in body, rel
        assert "J02_SCREEN_DECOMPOSITION v0.7" not in body, rel

    protocol = text("references/screen-decomposition-protocol.md")
    assert "Assertions J02 v0.8 — 26/26" in protocol
    assert "assertions_total = 26" in protocol
    assert "17/17" in protocol and "no se permite" in protocol.lower()


if __name__ == "__main__":
    check()
    print("PASS_STORY_CREATOR_B1_B2_DYNAMIC_WORKER_J02_V08_V1")
