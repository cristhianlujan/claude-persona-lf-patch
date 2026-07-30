# Contrato de tokens y mensajes

Versión operativa: `v0.5`. Juez asociado: `J08_TOKENS_MESSAGES`.
Validador: `scripts/validate_tokens.py`.

## 1. Propósito

Evitar valores visuales y textos hardcodeados mediante tokens registrados o candidatos explícitos y mensajes semánticos verificables.

## 2. Contrato de entrada

| Entrada | Contenido obligatorio |
|---|---|
| `interaction_contract` | Componentes y estados de interacción. |
| `token_registry` | Tokens visuales, formato y componentes. |
| `message_catalog` | Códigos, severidad y referencias de texto. |
| `source_copy` | Texto de negocio confirmado cuando exista. |

## 3. Preflight

1. Confirmar entradas, versión y referencias resolubles.
2. Confirmar independencia entre worker y J08.
3. Confirmar metadata y SHA-256.
4. Detener con `BLOCKED` ante registro ausente, conflicto de política o metadata faltante.

## 4. Procedimiento obligatorio

1. Inventariar colores, espacios, tipografías, iconos y componentes.
2. Resolver cada valor contra `token_registry`.
3. Marcar token no registrado como `CANDIDATO`; nunca como vigente.
4. Inventariar mensajes y exigir `message_code`, `severity` y `text_ref`.
5. Detectar códigos duplicados, colores HEX/RGB y espaciados px/rem/em.
6. Ejecutar caso positivo, negativo y metadata ausente con el validador real.

## 5. Reglas e invariantes

- Prohibidos HEX, RGB, px, rem y em literales en interacción o tokens.
- `registered=true` exige `status=REGISTERED`.
- `registered=false` exige `status=CANDIDATO`.
- Todo mensaje tiene código, severidad y `text_ref`.
- Códigos de mensaje duplicados impiden PASS.

## 6. Contrato de salida

Salida principal: `schemas/story-pack.schema.json#/properties/tokens_messages` y envelope v0.5.

## 7. Assertions de paso

```text
tokens_messages_section_missing = 0
tokens_missing = 0
messages_missing = 0
tokens_without_code = 0
messages_without_code = 0
hardcoded_color_count = 0
hardcoded_spacing_count = 0
unregistered_component_tokens = 0
messages_without_severity = 0
messages_without_text_ref = 0
duplicate_message_codes = 0
```

## 8. Condiciones de bloqueo

```text
token_registry_required_but_unavailable = true
message_policy_conflict = true
metadata_or_evidence_unavailable = true
retry_limit_exhausted = true
```

## 9. Caso positivo ejecutable

```json
{
  "tokens_messages": {
    "tokens": [{"token_code": "COLOR-PRIMARY", "registered": true, "status": "REGISTERED"}],
    "messages": [{"message_code": "MSG-001", "severity": "INFO", "text_ref": "TXT-001"}]
  },
  "interaction": {}
}
```

Resultado esperado: `PASS_WITH_EVIDENCE`.

## 10. Caso negativo ejecutable

```json
{
  "tokens_messages": {
    "tokens": [{"token_code": "BTN-1", "registered": true, "status": "CANDIDATO"}],
    "messages": [{"message_code": "MSG-001"}, {"message_code": "MSG-001"}]
  },
  "interaction": {"style_note": "color: #ffffff; margin: 8px"}
}
```

Resultado esperado: `RETURN_TO_WORKER` por hardcodes, token inválido, mensajes incompletos y duplicidad.

## 11. Reparación y handoff

Reparar exclusivamente el objeto asociado; no reducir umbral, borrar assertion, inventar token ni autoaprobar. Tras `retry_limit = 2`, devolver `BLOCKED`. Entregar comando, ejecutor, conteos, hashes y `evidence_refs`.

## 12. Fuentes de diseño no normativas

- **anthropics/skills:** evals objetivas y reparación iterativa.
- **microsoft/vscode:** workflows y stop conditions.
- **freeCodeCamp/freeCodeCamp:** constraints y unicidad.
- **Significant-Gravitas/AutoGPT:** estado reproducible y límites.

Los contratos LF prevalecen.
