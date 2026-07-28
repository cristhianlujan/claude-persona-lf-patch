---
name: creating-integral-user-stories
description: >
  Use when a product screen, functional specification, prototype,
  registered screen, handoff, or existing partial story set must be
  decomposed into complete, traceable, implementation-ready user stories.
version: v0.1
status: CANDIDATO_READ_ONLY
---

# Creating Integral User Stories

Convierte una pantalla registrada en fuente operativa en un conjunto de
historias de usuario con Story Pack integral, trazable y verificable por jueces.

## Regla principal

Una pantalla no equivale a una historia. Una historia no esta completa por
tener actor, necesidad y beneficio.

```text
Pantalla -> inventario funcional -> contextos -> unidades funcionales
-> decision CREATE/MERGE/CROSS_CUTTING/OUT_OF_SCOPE/PENDING/DUPLICATE/RELATED
-> historias -> Story Pack -> pruebas -> jueces -> evidencia
```

## Cuando activar

Activa cuando el pedido menciona pantalla, modulo, prototipo, especificacion
funcional, handoff de producto, o historias parciales que deben completarse.

## Cuando NO activar

No actives para redaccion libre, traduccion, resumen, priorizacion de backlog
sin pantalla fuente, ni para aprobar o marcar artefactos como vigentes.

## Flujo obligatorio

1. Leer fuente operativa y crear snapshot con sha. Ejecutar J01.
2. Descomponer la pantalla. Ver `references/screen-decomposition-protocol.md`.
   Ejecutar J02.
3. Redactar nucleo funcional por historia. Ver `references/story-pack-contract.md`.
   Ejecutar J03.
4. Auditar campos. Ver `references/field-contract.md`. Ejecutar J04.
5. Enriquecer transversales: observaciones y errores (J05), seguridad y
   privacidad (J06), auditoria y trazabilidad (J07), tokens y mensajes (J08),
   analytics y observabilidad (J09).
6. Derivar pruebas. Ver `references/test-derivation-contract.md`. Ejecutar J10.
7. Validar el paquete con `scripts/validate_package.py`. Ejecutar J11.
8. Escribir en la rama autorizada y releer. Ejecutar J12.
9. Cerrar ledger con `scripts/calculate_binary_completion.py`. Ejecutar J13.

## Progressive disclosure

Este archivo no contiene los contratos completos. Carga solo la referencia
necesaria para el step en curso. Los contratos viven en `references/`, los
schemas en `schemas/`, las rubricas en `judges/`.

## Workers

Delegar mediante Task Packet (`schemas/task-packet.schema.json`) a los perfiles
externos declarados en `manifest.yaml`. Ningun worker ejecuta el juez que
aprueba su propio trabajo. `retry_limit = 2`.

## Limites duros

```text
NO_VALIDATED: true
NO_PRODUCCION: true
NO_RUNTIME_REAL: true
NO_MERGE: true
NO_MARCAR_VIGENTE: true
```

Estados prohibidos en cualquier salida: VALIDATED, APPROVED, PRODUCTION_READY,
PRODUCTION_AUTHORIZED, VIGENTE. Unico cierre satisfactorio: PASS_WITH_EVIDENCE.

## Salida

Story Pack por historia conforme a `schemas/story-pack.schema.json`, matriz de
cobertura, resultados de jueces y ledger binario. Si falta definicion en la
fuente, marcar `PENDING_DECISION`; nunca inferir reglas confirmadas.
