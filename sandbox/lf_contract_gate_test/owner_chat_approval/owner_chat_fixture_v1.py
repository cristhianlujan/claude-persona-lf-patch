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
PROPOSER = "fixture-proposer-01"
REGISTRAR = "fixture-recorder-01"
