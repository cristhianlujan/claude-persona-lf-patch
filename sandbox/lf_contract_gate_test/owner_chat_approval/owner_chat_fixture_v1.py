"""Unico fixture sintetico de identidad para tests del canal propietario LF.

Valores cotejados por SELECT del catalogo LF; no acreditan autenticacion
del ChatGPT USER turn. Produccion siempre lee private.lf_owner_chat_identity_v1
con JOIN a public.lf_ig_project_owner_v2, nunca este archivo.
"""
OWNER_SUB = "00000000-0000-4000-8000-000000000001"
OTHER_SUB = "00000000-0000-4000-8000-000000000002"
OWNER_NAME = "Cristhian Luján"
OWNER = OWNER_SUB
REPO = "cristhianlujan/claude-persona-lf-patch"
CHANNEL = "CHAT_ORCHESTRATOR_USER_TURN"
CHANNEL_CLAUDE = "CHAT_CLAUDE_SESSION"
CHANNEL_GPT = "CHAT_GPT_SESSION"
CLAUDE_HASH = "e9ff5f5f431ad1a7fdea5aeda30fcbad4bd48d2f0d73231e9383682098c4e258"
# Both channels inherit the SINGLE installation-email fingerprint.
# The real plaintext owner email is NEVER present in tests or source.
OWNER_EMAIL_SHA256 = CLAUDE_HASH
AUTHORIZED_ACCOUNT_SEED = (
    (CHANNEL_CLAUDE, OWNER_EMAIL_SHA256, True),
    (CHANNEL_GPT, OWNER_EMAIL_SHA256, True),
)
# Isolated synthetic mailbox assembled at test runtime, not owner information.
# It allows positive trim/lower tests without publishing the real email.
import hashlib
TEST_EMAIL = "fixture." + "account" + "@" + "example.invalid"
TEST_EMAIL_SHA = hashlib.sha256(TEST_EMAIL.encode("utf-8")).hexdigest()
AUTHORIZED_ACCOUNT_FIXTURE = (
    (CHANNEL_CLAUDE, TEST_EMAIL_SHA, True),
    (CHANNEL_GPT, TEST_EMAIL_SHA, True),
)
PROPOSER = "fixture-proposer-01"
REGISTRAR = "fixture-recorder-01"
