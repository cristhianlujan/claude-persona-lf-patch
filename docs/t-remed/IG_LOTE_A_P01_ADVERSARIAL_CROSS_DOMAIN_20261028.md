# P01 — Segunda cohorte adversarial de alcance (solo lectura)

Fecha 28-oct-2026. Contraste de reglas reales con tres destinos: Login B2B, alta cliente ONB_004 y HOME_FAQ sin módulo. **Hipótesis no ratificadas**. Este lote incorpora deliberadamente casos que no deben resolverse todos como “eliminar herencia”.

| Regla | Observación real | Hipótesis que requiere contrastación |
|---|---|---|
| `REG_ONB_003` — Consentimientos que bloquean avance | DERIVED_GLOBAL hacia Login B2B **y** ONB_004; la segunda pantalla sí declara Términos y consentimiento | Expansión B2B probablemente inaplicable; en ONB_004 puede ser legítima. Confirmar campos, versión de consentimiento y flujo |
| `REG_ONB_004` — Marketing opcional | DERIVED_GLOBAL en Login, ONB_004 y HOME_FAQ; regla describe `consent_marketing=false` | Aplicabilidad solo donde se decide elegibilidad de comunicaciones; consultar fuente de consentimiento y tipo de contacto |
| `B2B-RULE-A11Y-001` — Accesibilidad | LEGACY_EXPLICIT en Login; DERIVED_GLOBAL en ONB_004 y HOME_FAQ | Puede ser transversalmente legítima, pero la misma formulación B2B no sustituye una decisión de ámbito LF; comprobar estándares y owner de diseño |
| `B2B-RULE-PRIVACY-001` — Prohibición PII en telemetría | LEGACY_EXPLICIT en Login; DERIVED_GLOBAL en ONB_004 y HOME_FAQ | Requisito potencialmente reutilizable en diversos canales. Mantener como candidato positivo para análisis, no descartarlo por venir de B2B |
| `B2B-RULE-AUTH-001` — Denegar operaciones por defecto tras autenticación | LEGACY_EXPLICIT en Login; DERIVED_GLOBAL en ONB_004 y HOME_FAQ | La condición postautenticación B2B no está probada en esos destinos; exigir evidencia de la operación server-side |
| `B2B-RULE-RATE-001` — Política central de rate limit | LEGACY_EXPLICIT en Login; DERIVED_GLOBAL en ONB_004 y HOME_FAQ | Regla de reutilización potencial, pero no asignar un policy_id de B2B a un contexto sin política autorizada |
| `B2B-RULE-PROD-001` — Bloqueo de producción de activos B2B | LEGACY_EXPLICIT en Login; DERIVED_GLOBAL en ONB_004 y HOME_FAQ | Distinguir control de ciclo de vida de Backoffice de una norma de despliegue general de LF; no asumir equivalencia |

## Qué evita esta prueba

1. Eliminar automáticamente todas las herencias fuera del shell: accesibilidad y privacidad podrían tener aplicaciones legítimas.
2. Conservar automáticamente las que coinciden en el mismo shell: un requerimiento de onboarding solo aplica donde su condición se cumple.
3. Tratar reglas de gerencia/despliegue como condiciones de interfaz visual.
4. Reutilizar un policy_id porque una etiqueta o categoría coincide.
5. Desempatar con puntuación sin pruebas positivas y negativas.

**Resultado combinado P01:** cinco reglas iniciales más siete contrastes adicionales, todos observacionales. No se declara revisión independiente ni aprobación. Las 241 filas de P07 siguen en `UNRESOLVED_REQUIRES_SEMANTIC_EVIDENCE` hasta contar con decisión verificable.
