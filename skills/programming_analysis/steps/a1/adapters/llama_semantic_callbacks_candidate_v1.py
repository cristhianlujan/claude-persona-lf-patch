"""A1-only model callbacks over the EXISTING LlamaHTTPClient.chat interface.

SOURCE_CANDIDATE: no profile/router/RUN, no client construction, no network
until caller explicitly invokes a callback. A separate reviewer client is
required but different Python objects do NOT prove independent model authority.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Callable

from jsonschema import Draft202012Validator

A1 = Path(__file__).resolve().parents[1]
INTENT_SCHEMA = A1 / "schemas/intent_analysis_candidate_v1.schema.json"
SCHEMA_MODE = "AUTO"
REVIEW_SCHEMA = {
    "type": "object", "additionalProperties": False,
    "required": ["verdict", "issues"],
    "properties": {
        "verdict": {"enum": ["PASS", "FAIL"]},
        "issues": {"type": "array", "items": {"type": "string", "minLength": 1}}
    }
}

PRODUCER_INSTRUCTION = """You analyze a software engineering request for an
internal A1 intake step. Return JSON matching the supplied schema ONLY.
Reason semantically, not by matching a fixed list of keywords or looking
for a login example. An implementation request does not prove a greenfield
repository. Infer intended operation, artifact, capability, actor context,
and user-assumed state. Preserve negation and constraints. Never invent
database records, repository identifiers, approvals, code currentness, or
policies. A missing detail is an investigation need, not proof of an absent
policy. Every evidence span must be an exact original-text slice with
Python code-point offsets. Assign OPERATION, ARTIFACT and CAPABILITY evidence
even for implicit phrasings. Contradictions or indeterminate intent must be
represented as material ambiguities, not silently resolved.
Do not perform coding, research, deployment, or an external action."""

REVIEWER_INSTRUCTION = """Act as a semantic fidelity reviewer for an A1
software engineering intake candidate. Judge the original request and
the proposed structured interpretation independently. Return JSON only.
PASS requires preservation of operation semantics, negations and
constraints, business/actor context, object/capability differentiation,
and correct treatment of unverified greenfield assertions as user
hypotheses. Reject hallucinated approvals, repo IDs, security policies,
claims of code existence/absence, or missing material ambiguity.
Literal quote existence does NOT establish semantic correctness.
Do not assume that CREATE and IMPLEMENT mean the same thing.
Do not give PASS simply because JSON matches a schema."""


def _decode(result: Any, schema: dict) -> tuple[dict, str]:
    if not isinstance(result, dict):
        raise ValueError("A1_LLM_RESULT_NOT_OBJECT")
    literal = result.get("content")
    if not isinstance(literal, str):
        raise ValueError("A1_LLM_CONTENT_MISSING")
    try:
        value = json.loads(literal)
    except json.JSONDecodeError as exc:
        raise ValueError("A1_LLM_JSON_INVALID") from exc
    if not isinstance(value, dict) or not Draft202012Validator(schema).is_valid(value):
        raise ValueError("A1_LLM_SCHEMA_INVALID")
    result_id = result.get("id")
    if not isinstance(result_id, str) or not result_id.strip():
        raise ValueError("A1_LLM_RESPONSE_ID_MISSING")
    # A model response ID is transport metadata, NEVER independent attestation.
    return value, result_id.strip()


def bind_clients(*, producer_client: Any, reviewer_client: Any,
                 profile_slug: str = "programming_analysis_lf_a1_candidate") -> tuple[Callable, Callable]:
    """Use already configured LlamaHTTPClient instances, no model hardcoding.

    Caller must supply two distinct clients, but neither model identity nor
    independence is authenticated here. This is intentionally SOURCE_ONLY.
    """
    if producer_client is reviewer_client or producer_client is None or reviewer_client is None:
        raise ValueError("A1_SEPARATE_MODEL_CLIENTS_REQUIRED")
    if not callable(getattr(producer_client, "chat", None)) or not callable(
        getattr(reviewer_client, "chat", None)
    ):
        raise TypeError("A1_LLAMA_CLIENT_CHAT_INTERFACE_REQUIRED")
    schema = json.loads(INTENT_SCHEMA.read_text(encoding="utf-8"))

    def producer(raw_text: str) -> dict:
        value, _ = _decode(producer_client.chat(
            system_prompt=PRODUCER_INSTRUCTION,
            user_prompt=raw_text,
            schema=schema,
            profile_slug=profile_slug,
            schema_mode=SCHEMA_MODE
        ), schema)
        return value

    def reviewer(raw_text: str, candidate: dict) -> dict:
        # Import the existing A1 candidate canonical hash. The model must not
        # self-certify this digest.
        from hashlib import sha256
        payload = json.dumps(candidate, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        fingerprint = sha256(payload.encode("utf-8")).hexdigest()
        result, response_id = _decode(reviewer_client.chat(
            system_prompt=REVIEWER_INSTRUCTION,
            user_prompt=json.dumps({
                "original_request": raw_text,
                "candidate": candidate
            }, ensure_ascii=False, sort_keys=True),
            schema=REVIEW_SCHEMA,
            profile_slug=profile_slug,
            schema_mode=SCHEMA_MODE
        ), REVIEW_SCHEMA)
        return {
            "verdict": result["verdict"],
            "issues": result["issues"],
            "candidate_sha256": fingerprint,
            "reviewer_ref": "model-response://a1/" + response_id
        }

    return producer, reviewer
