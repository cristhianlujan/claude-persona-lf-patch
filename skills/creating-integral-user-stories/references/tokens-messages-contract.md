# Contrato de tokens y mensajes

Juez asociado: `J08_TOKENS_MESSAGES`. Validador: `scripts/validate_tokens.py`.

## Reutilizacion obligatoria

La historia referencia tokens registrados. Prohibido hardcodear HEX, RGB,
tamanos, tipografias, mensajes repetidos e iconos no registrados.

## Token nuevo

Todo token no existente se declara con `status: CANDIDATO`. Un token nuevo no
puede declararse vigente desde esta skill.

```text
token_code, token_type, registered, status, source_ref, fallback
```

## Mensajes

```text
message_code, severity, audience, text_ref, action_token, tone
```

Condiciones de paso:

```text
hardcoded_color_count = 0
hardcoded_spacing_count = 0
unregistered_component_tokens = 0
duplicate_message_text_without_token = 0
candidate_tokens_without_candidate_status = 0
messages_without_severity = 0
```

## Tono LF

Los mensajes de dominio financiero no prometen resultados, no garantizan
aprobacion ni eliminacion de registros, y no usan urgencia artificial.
