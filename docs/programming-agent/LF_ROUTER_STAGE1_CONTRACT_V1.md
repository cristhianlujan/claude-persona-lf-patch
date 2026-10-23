# Contrato de la etapa 1 del Router ACT-0001 (LF) — `LF_ROUTER_STAGE1_V1`

Complementa `LF_ROUTER_FLOW_V1.md`. La etapa 1 la produce el modelo nativo (GPT/Claude) antes de buscar nada. El validador (`sandbox/lf_contract_gate_test/router_stage1/stage1_validator_v1.py`) solo comprueba forma y reglas y decide el siguiente paso; no clasifica, no busca ni autoriza efectos.

## Salida de la etapa 1

| Campo | Regla |
|---|---|
| `schema_version` | `LF_ROUTER_STAGE1_V1` |
| `texto_original` | La frase literal del usuario, obligatoria. |
| `es_operacion` | `false` si se responde sin inventario (ej. "¿qué hora es en Lima?"). |
| `respuesta_directa` | Obligatoria en `true` si no es operación; `false` si es operación. |
| `sistema` | `LF`, `SALY`, `OTRO` o `DESCONOCIDO` (solo LF se atiende hoy). |
| `accion`, `sujeto` | Al menos uno si es operación. |
| `correcciones` | Lo que el modelo corrigió ("history" → "historias"); cada una cambia algo. |
| `formas_busqueda` | 1 a 4 reformulaciones (español e inglés) **solo para el nivel 1**; vacío si no es operación. |
| `ambiguo`, `alternativas`, `pregunta_usuario` | Si hay ambigüedad: 2 a 3 alternativas y **una** pregunta. Sin ambigüedad: sin alternativas. |
| `capability_hint` | Opcional, `MAYUSCULAS_Y_GUIONES_BAJOS`; es una pista para el despacho, no una autorización. |
| `downstream_execution_allowed` | Siempre `false`. |

Regla "no inventar": ninguna forma de búsqueda puede contener un código de activo (ACT-…, REG_…, PERFIL-…, etc.) que el usuario no escribió.

## Siguiente paso que decide el validador

| Situación | Paso |
|---|---|
| No es operación | `DIRECT_ANSWER` (termina; no entra a la etapa 2) |
| Ambiguo | `ASK_USER` (una pregunta) |
| Sistema distinto de LF | `SYSTEM_NOT_SUPPORTED` (hasta tener la dimensión de sistema) |
| Operación en LF | `LEVEL1_SEARCH` con `lf_router_search_v1`; si queda vacío, nivel 2 con consentimiento |
| Cualquier violación | `INVALID` con los códigos |

## Pruebas

`python3 -I sandbox/lf_contract_gate_test/router_stage1/test_stage1_validator_v1.py`: 19 casos (positivos y negativos) con frases del propietario ("qué hora es en Lima", "crear history de usuario", "spec driving", "el perfil" ambiguo, código inventado, dos preguntas, etc.).

## Lo que NO prueba

Que el modelo produzca bien esta salida con frases reales: este contrato fija la forma y las reglas, no la calidad de la clasificación. Esa se mide con las frases reales del propietario cuando las entregue (pendiente).
