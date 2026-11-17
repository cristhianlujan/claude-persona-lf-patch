"""Protocolo LF de orden HUMANA por chat; SIN firma externa.

Seguridad: el transporte del orquestador es el unico origen admitido del evento
USER. El texto/hashes y campos escritos por un modelo NO prueban autoria.
Este modulo valida un registro recibido, NO autentica por si solo al emisor.
"""
from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime, timedelta, timezone
from typing import Any
from zoneinfo import ZoneInfo
from uuid import UUID

REPO_PATTERN = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\Z")
SHA40 = re.compile(r"[a-f0-9]{40}\Z")
SHA64 = re.compile(r"[a-f0-9]{64}\Z")
CODE = re.compile(r"[A-Z0-9_-]{3,128}\Z")
ORDER = re.compile(r"\AAPRUEBO ([0-9a-f]{12}) (.+)\Z", re.DOTALL)
DEFAULT_CATALOG = {
    "MERGE_GOVERNANCE_PR": frozenset({"action", "repository", "pr_number", "head_sha"}),
    "PROMOTE_RULE_BATCH": frozenset({"action", "repository", "execution_id", "rule_codes", "rule_snapshots_sha256"}),
    "UPDATE_IG_PARAMETER": frozenset({"action", "repository", "parameter_namespace",
                                       "parameter_code", "channel_code", "expected_revision",
                                       "new_value_sha256", "new_activo"}),
}

class ChatOrderRejected(ValueError):
    """Codigo estable de bloqueo, verificable en tests."""


def canonical(scope: dict[str, Any]) -> str:
    return json.dumps(scope, sort_keys=True, ensure_ascii=False,
                      separators=(",", ":"), allow_nan=False)


def sha256_literal(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def sha256_normalized_account_email(value: str) -> str:
    """SHA256(lower(trim(email))) sin devolver ni almacenar el correo."""
    if not isinstance(value,str) or not value.strip():
        raise ChatOrderRejected("ACCOUNT_EMAIL_MISSING")
    return sha256_literal(value.strip().lower())


def validate_scope(scope: Any, catalog: dict | None = None) -> dict:
    allowed = catalog if catalog is not None else DEFAULT_CATALOG
    if not isinstance(scope, dict) or not isinstance(scope.get("action"), str):
        raise ChatOrderRejected("INVALID_SCOPE")
    action = scope["action"]
    if action not in allowed or set(scope) != set(allowed[action]):
        raise ChatOrderRejected("ACTION_OR_FIELDS_NOT_CATALOGUED")
    if not isinstance(scope.get("repository"), str) or not REPO_PATTERN.fullmatch(scope["repository"]):
        raise ChatOrderRejected("INVALID_REPOSITORY")
    if action == "MERGE_GOVERNANCE_PR":
        if type(scope["pr_number"]) is not int or scope["pr_number"] < 1 or not isinstance(scope["head_sha"],str) or not SHA40.fullmatch(scope["head_sha"]):
            raise ChatOrderRejected("INVALID_PR_HEAD")
    elif action == "PROMOTE_RULE_BATCH":
        codes = scope["rule_codes"]
        if not isinstance(codes, list) or not codes or codes != sorted(set(codes)) or any(not isinstance(x,str) or not CODE.fullmatch(x) for x in codes):
            raise ChatOrderRejected("INVALID_RULE_SET")
        if not isinstance(scope["execution_id"], str) or not re.fullmatch(r"EXEC-[A-Z0-9_-]{10,128}", scope["execution_id"]):
            raise ChatOrderRejected("INVALID_RUN")
        if not isinstance(scope["rule_snapshots_sha256"],str) or not SHA64.fullmatch(scope["rule_snapshots_sha256"]):
            raise ChatOrderRejected("INVALID_RULE_SNAPSHOTS")
    elif action == "UPDATE_IG_PARAMETER":
        if (scope.get("parameter_namespace") != "OWNER_CHAT"
                or scope.get("parameter_code") != "SESSION_EMAIL_SHA256"
                or not isinstance(scope.get("channel_code"), str)
                or not re.fullmatch(r"CHAT_[A-Z_]+_SESSION",scope["channel_code"])
                or type(scope.get("expected_revision")) is not int
                or scope["expected_revision"] < 1
                or not isinstance(scope.get("new_value_sha256"),str)
                or not SHA64.fullmatch(scope["new_value_sha256"])
                or type(scope.get("new_activo")) is not bool):
            raise ChatOrderRejected("INVALID_PARAMETER_CHANGE_SCOPE")
    return scope


def expected_order(scope: dict, catalog: dict | None = None) -> str:
    validate_scope(scope, catalog)
    data = canonical(scope)
    return "APRUEBO " + sha256_literal(data)[:12] + " " + data


def _utc(s: Any) -> datetime:
    if not isinstance(s, str) or not s.endswith("Z"):
        raise ChatOrderRejected("INVALID_UTC_TIMESTAMP")
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError as e:
        raise ChatOrderRejected("INVALID_UTC_TIMESTAMP") from e


def verify_order(*, event: dict, expected_scope: dict,
                 owner_sub: str, channel_code: str, repository_full_name: str,
                 authorized_accounts: tuple[tuple[str,str,bool],...],
                 proposer_subject: str,
                 registrar_subject: str, now: datetime,
                 catalog: dict | None = None) -> dict:
    """Llamar SOLO despues del readback del evento USER del orquestador.

    owner_sub, channel_code y repository_full_name deben provenir del readback
    protegido de private.lf_owner_chat_identity_v1, nunca de la orden.
    """
    validate_scope(expected_scope, catalog)
    if expected_scope['repository'] != repository_full_name:
        raise ChatOrderRejected('REPOSITORY_CONFIG_MISMATCH')
    if not isinstance(event, dict) or set(event) != {"event_kind", "origin", "actor_sub", "channel_code", "session_account_sha256", "conversation_id", "message_id", "text_literal", "sent_at", "scope"}:
        raise ChatOrderRejected("EVENT_CONTRACT_INVALID")
    if event["event_kind"] != "USER_MESSAGE" or event["origin"] != channel_code:
        raise ChatOrderRejected("NOT_AN_ORCHESTRATED_USER_TURN")
    if not all(isinstance(v,str) and len(v)>=8 for v in [owner_sub,channel_code,proposer_subject,registrar_subject]):
        raise ChatOrderRejected("ACTOR_CONTRACT_INVALID")
    try:
        normalized_sub = str(UUID(owner_sub))
        actual_sub = str(UUID(event["actor_sub"]))
    except (ValueError, AttributeError, TypeError) as exc:
        raise ChatOrderRejected("OWNER_SUB_INVALID") from exc
    if normalized_sub != owner_sub or actual_sub != normalized_sub:
        raise ChatOrderRejected("WRONG_OWNER")
    if proposer_subject == registrar_subject or registrar_subject == owner_sub:
        raise ChatOrderRejected("NO_PROPOSER_REGISTRAR_SEPARATION")
    sess_channel = event["channel_code"]
    sess_sha = event["session_account_sha256"]
    if not isinstance(sess_channel,str) or not isinstance(sess_sha,str) or not SHA64.fullmatch(sess_sha):
        raise ChatOrderRejected("ACCOUNT_SESSION_INVALID")
    # Trusted account identity proof is the platform session SHA, checked
    # against the ACTIVE canonical parameter readback. Never read environment.
    # A model-supplied hash alone is NOT authenticated ingress.
    if not isinstance(authorized_accounts,tuple) or not any(
        entry == (sess_channel,sess_sha,True) for entry in authorized_accounts
    ):
        raise ChatOrderRejected("ACCOUNT_SESSION_NOT_AUTHORIZED")
    for key in ("conversation_id", "message_id"):
        if not isinstance(event[key],str) or len(event[key]) < 12:
            raise ChatOrderRejected("MISSING_CHAT_MESSAGE_REF")
    if not isinstance(event["scope"],dict) or canonical(event["scope"]) != canonical(expected_scope):
        raise ChatOrderRejected("WRONG_EXACT_SCOPE")
    if not isinstance(event["text_literal"],str) or event["text_literal"] != expected_order(expected_scope,catalog):
        raise ChatOrderRejected("INVALID_ORDER_LITERAL_OR_SHORT_HASH")
    sent = _utc(event["sent_at"])
    if now.tzinfo is None or sent > now.astimezone(timezone.utc) + timedelta(seconds=30):
        raise ChatOrderRejected("FUTURE_MESSAGE")
    if now.astimezone(timezone.utc) >= sent + timedelta(minutes=15):
        raise ChatOrderRejected("EXPIRED_ORDER")
    return {"schema_version":"LF_OWNER_CHAT_ORDER_V2", "channel":"ORCHESTRATION_CHAT",
            "event_kind":"USER_MESSAGE", "actor_sub": owner_sub,
            "identity_mode":"ACCOUNT_SESSION","channel_code":sess_channel,
            "session_account_sha256":sess_sha,
            "proposer_subject": proposer_subject, "registrar_subject": registrar_subject,
            "message_id":event["message_id"], "conversation_id":event["conversation_id"],
            "text_literal":event["text_literal"],
            "text_literal_sha256":sha256_literal(event["text_literal"]),
            "scope":expected_scope, "scope_sha256":sha256_literal(canonical(expected_scope)),
            "sent_at":event["sent_at"], "sent_at_lima":sent.astimezone(ZoneInfo("America/Lima")).isoformat(),
            "expires_at":(sent+timedelta(minutes=15)).isoformat().replace("+00:00","Z"),
            "consumed":False,"revoked":False,"ingress_status":"VALIDATED_ORCHESTRATOR_EVENT"}
