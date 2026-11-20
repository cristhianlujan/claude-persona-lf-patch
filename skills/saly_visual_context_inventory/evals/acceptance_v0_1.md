# Evaluación de la primera capacidad de SALY

| ID | Caso | Criterio |
|---|---|---|
| SRC-01 | Lectura real SALY-001 | 2 tokens efectivos, 8 logos aprobados en baseline 2026-11-20 (valor dinámico en futuras ejecuciones) |
| SRC-02 | Sin catálogo de estándares activo | `SOURCE_INVENTORY_ONLY`, `image_generation_allowed=false` |
| SRC-03 | 46 tokens candidatos existentes | No aparecen como tokens efectivos ni en fallback |
| SRC-04 | Logo con hash registrado y sin inspección binaria | `independent_sha_verified=false` |
| SRC-05 | Intento de ejecutar para LF/Overall | Falta autoridad del RUN SALY → `BLOCKED` en handler futuro; query no lee LF/Overall |
| SRC-06 | RUN sin handoff, perfil incorrecto o canal distinto | `BLOCKED` por handler futuro; jamás aceptar business en JSON como autoridad |
| SRC-07 | Inexistencia de pantalla/marco/fondo aprobados | No inventar assets ni declarar READY |
| SRC-08 | Recuperar datos en dos momentos | Versiones por IDs y vigencias; no mutar histórico |
| SRC-09 | Rechazo del runtime desde cuenta RO | Permisos de SQL/handler inalterados |
| SRC-10 | Reuso de selección de skill histórica | Prohibido; abrir nuevo RUN para una tarea nueva solo con autorización de Router |

## Evidencia de lectura real (baseline, no de ejecución de nuevo skill)

SELECT directo a `saly.v_identity_current` y `saly.brand_assets`: 2 tokens efectivos (`color.action.primary.bg`, `color.brand.primary`), 8 logos aprobados, `visual.standard_activations` no existe. Los 8 logos tienen `sha256_independent_byte_check=false`. **No son ocho hashes binarios independientes verificados.**

**Resultado:** pruebas SRC-01–04 fundamentadas por lectura actual. SRC-05–10 son criterios pendientes para la implementación gobernada; **no reclamar PASS** de esas pruebas a partir del archivo SQL ni de un fixture.

## Dependencias para habilitar la skill

1. Catálogo de estándares persistente y versionado (contrato DRAFT PR #4237), o política explícita que mantenga el resultado solo inventario.
2. Handler gobernado con aislamiento del RUN SALY y sin privilegios extra; evaluación de impacto en políticas de skill.
3. RUN nuevo para una solicitud nueva de diseño, mediante Router; **no reusar** `EXEC-PROFILE-GATE2-557FD34CF90AACA33869F397` porque su skill elegido fue el PROBE y su selección es inmutable.
