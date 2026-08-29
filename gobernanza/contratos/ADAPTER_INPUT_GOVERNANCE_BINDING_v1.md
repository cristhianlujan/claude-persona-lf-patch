# ADAPTER INPUT GOVERNANCE BINDING v1

Estado: CANDIDATO / READ_ONLY / NO_HABILITADO

## Objetivo
Unificar cómo los adapters consumen gobernanza de inputs sin duplicar prompts ni crear lógica paralela. La autoridad sigue siendo `INPUT_READINESS_CONTRACT`; al 2026-08-29 la revisión observada vigente es `5.12`. Cada ejecución debe resolver la revisión vigente y registrar la versión realmente consumida.

## Regla canónica
Todo adapter que reciba requisitos funcionales, fuentes autoritativas, freshness, requisitos negativos, conflictos/precedencia o una decisión de elegibilidad/readiness debe consumir selectivamente `INPUT_GOVERNANCE_AGENT` mediante `INPUT_READINESS_CONTRACT` antes de aplicar su función técnica.

No se copia ni se reimplementa la lógica del agente dentro del adapter.

## Secciones permitidas
Consumir solo las necesarias:
- `APPLICABILITY_READINESS`
- `SOURCE_AUTHORITY_PROVENANCE`
- `FRESHNESS_INVALIDATION`
- `NEGATIVE_REQUIREMENTS`
- `CONFLICT_PRECEDENCE`

Las secciones no aplicables quedan fuera de `sections_consumed`; si toda la gobernanza es no aplicable, la decisión debe ser `N/A` con razón explícita.

## Flujo
`Router -> resolve adapter binding -> decide input-governance applicability -> resolve live INPUT_READINESS_CONTRACT -> consume only required sections -> verify source_refs + snapshot_hash -> persist governance_receipt -> PASS: technical adapter function | PARTIAL/NEGATIVE_CONFIRMED: block/return governed reason`

El consumo de gobernanza no habilita una segunda llamada LLM propia del adapter ni convierte al adapter en autoridad funcional.

## governance_receipt mínimo
```yaml
governance_agent_used: true|false
governance_version: "<resolved live revision or N/A>"
sections_consumed: ["<allowed section>"]
source_refs: ["<governed source ref>"]
snapshot_hash: "<source/contract snapshot hash or N/A>"
decision: PASS|PARTIAL|NEGATIVE_CONFIRMED|N/A
gap_or_na: "<gap, blocker or N/A reason>"
timestamp: "<ISO-8601>"
```

## Continuación
- `PASS`: puede continuar la función técnica del adapter.
- `PARTIAL`: no puede aplicar; debe bloquear/retornar con gap gobernado.
- `NEGATIVE_CONFIRMED`: no puede aplicar; debe respetar el requisito negativo.
- `N/A`: solo válido cuando `input_governance_applicable=false` y `gap_or_na` explica por qué.

## Hard fail P0
- input funcional relevante sin binding a este contrato;
- lógica local que forkea o sustituye `INPUT_READINESS_CONTRACT`;
- `APPLIED` con decisión distinta de `PASS`;
- falta de `source_refs` o `snapshot_hash` cuando gobernanza aplica;
- receipt ausente/incompleto;
- sección consumida fuera de la allowlist;
- snapshot no ligado a las fuentes evaluadas;
- uso de un agente ad hoc alternativo.

## Política de tokens
El adapter referencia este contrato y registra solo las secciones consumidas. No inyectar el contrato completo ni las cinco secciones en cada prompt. Runtime capsule conserva únicamente reglas de activación, PASS-only y receipt.
