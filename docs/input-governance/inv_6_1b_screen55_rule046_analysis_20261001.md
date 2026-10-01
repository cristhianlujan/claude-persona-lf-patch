# INV-6.1b — análisis de B2B-RULE-AUTH-046 y pantalla 55

Fecha: 2026-10-01  
Base exacta: `main@21bc55aa18eaa57553cef54bf56a6f5ca5fceef8`  
Tipo: D (solo propuesta; no modifica `lf_ops.reglas`)  
Owner direction: `lf_eventos #19834`  
Owner clarification previa: `lf_eventos #19722`

## 1. Hechos

Pantalla 55:

- id: `55`;
- código: `B2B-AUTH-005`;
- módulo: `B2B_AUTENTICACION`;
- `estado=VIGENTE`;
- `activa=true`;
- run canónico de Input Governance: `283`;
- entra en el universo autorizado de recuración por decisión del owner.

Pero su propia definición funcional dice:

> Pantalla TOTP retirada del flujo operativo. Se conserva únicamente como trazabilidad histórica/legacy; no debe recibir navegación activa ni implementarse como ruta operativa.

Por tanto existen dos dimensiones distintas:

```text
Input Governance / trazabilidad     = IN_SCOPE
Navegación operativa B2B           = OUT_OF_SCOPE
```

No son contradictorias.

## 2. Semántica de B2B-RULE-AUTH-046

La regla 046 no es el allowlist de Input Governance.

Título:
`Precedencia de seguridad sobre divulgación visual antes de sesión operativa`.

Su objetivo es resolver conflictos entre:
- seguridad/arquitectura de autenticación;
- divulgación visible;
- contrato visual/design system;
- superficies previas a sesión operativa.

Configuración actual:

```json
{
  "screen_ids": [51,52,53,54,56],
  "excluded_legacy_screen_ids": [55],
  "scope_until": "OPERATIONAL_SESSION_GRANTED"
}
```

Las pantallas 51–56 son todas `B2B_AUTENTICACION`, pero 55 es la única cuya definición actual dice explícitamente que no debe formar parte del flujo operativo.

## 3. Conclusión

La decisión del owner de incluir 55 en Input Governance NO obliga a agregarla a
`B2B-RULE-AUTH-046.valor_config.screen_ids`.

Hoy la exclusión es semánticamente defendible porque esta regla gobierna una superficie
operativa/visual y la pantalla 55 se conserva solo para trazabilidad histórica.

El problema es el nombre:

`excluded_legacy_screen_ids`

puede interpretarse erróneamente como:
“55 está fuera de toda gobernanza/currentness”.

Eso ya no es verdad.

## 4. Propuesta preferida

No cambiar el alcance funcional de la regla 046.

Mantener:

```json
"screen_ids": [51,52,53,54,56]
```

y aclarar la exclusión de 55 de manera aditiva antes de retirar el campo viejo:

```json
{
  "excluded_legacy_screen_ids": [55],
  "excluded_non_operational_screen_ids": [55],
  "exclusion_reason_by_screen": {
    "55": "TRACEABILITY_ONLY_NO_ACTIVE_NAVIGATION"
  },
  "scope_semantics": "OPERATIONAL_PRE_SESSION_SECURITY_VISUAL_ONLY",
  "input_governance_note": "Screen 55 remains in Input Governance currentness/recuration scope despite operational-navigation exclusion.",
  "legacy_exclusion_field_deprecated": true
}
```

Esto evita romper lectores desconocidos mientras elimina la ambigüedad semántica.

## 5. Evidencia de impacto

Búsqueda actual:
- no hay funciones PostgreSQL que referencien literalmente `excluded_legacy_screen_ids`;
- no hay referencias de código Git en main a ese campo.

Por tanto el riesgo de compatibilidad conocido es bajo, pero la corrección sigue requiriendo unidad gobernada si se materializa.

## 6. Relación con INV-6.2

La nueva regla:

`INPUT-GOV-RECURATION-AUTHORIZED-SCREENS-001`

sí debe contener:

```json
{
  "screen_ids": [1,2,3,5,43,51,52,53,54,55,56,57,58]
}
```

porque esa regla gobierna el universo de recuración/currentness, no navegación visual.

Así queda explícitamente separado:

```text
B2B-RULE-AUTH-046
  -> seguridad/divulgación de superficies operativas
  -> 55 excluida por no-operativa

INPUT-GOV-RECURATION-AUTHORIZED-SCREENS-001
  -> gobernanza de recuración
  -> 55 incluida
```

## 7. Salida de 6.1b

Propuesta: **KEEP OPERATIONAL EXCLUSION, CLARIFY SEMANTICS**.

No se modifica `B2B-RULE-AUTH-046` en esta unidad.

Si el owner desea materializar la aclaración:
- hacerlo en una unidad aparte o junto con una modificación explícitamente autorizada de esa regla;
- no mezclarla silenciosamente con 6.2.
