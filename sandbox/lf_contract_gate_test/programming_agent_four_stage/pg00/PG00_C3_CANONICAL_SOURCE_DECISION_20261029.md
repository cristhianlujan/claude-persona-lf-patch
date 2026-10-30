# Decisión owner · PG-00_C3 · Fuente canónica única

Fecha: 2026-10-29. Aprobación explícita en conversación: usar `paulozterra/lf-programming-sandbox` como fuente canónica de C3, partiendo de `standards/catalog.json` v0.6.1 en commit `a846341`, con CHG correspondientes **antes de publicar**.

## Alcance y límites

- Fuente canónica: `paulozterra/lf-programming-sandbox/standards/catalog.json`; vista LLM: `standards/CATALOGO.md` generada por `tools/render_llm.py`.
- Conservación de códigos `STD-*`, 16 dominios y 83 reglas existentes; la release final se fijará después de CHG y revisión independiente.
- El código `STD-ADR-00N` del PR #3325 queda **DESCARTADO COMO AUTORIDAD**; se conserva solo como registro histórico de una hipótesis refutada. No exportar, publicar ni consumir estas reglas.
- Reutilizables de #3325: paridad contra `transversal.decision_log`, lista de dependencias C4 (corregir D15 de LF), política de publicación y evidencia de revisión.
- No hay aprobación de reglas nuevas ni de migración; PASE y Merge Train siguen obligatorios.
- No usar un SHA abreviado como identidad exacta del release. Resolver commit de 40 caracteres y digest de bytes exactos de `catalog.json` **después** del CHG.
- Cuatro huecos ADR-012, 014, 016, 017: CHG ADDITIVE en canónico, sin inventar resolución de conflicto LF ADR-012, precios o montos D17.

## Puerta de salida

`CHG -> validate_catalog.py -> render_llm.py --check -> C7 negativos -> revisión independiente exact-head -> owner -> migración -> PASE -> Train -> readback repo/transversal -> PG-01_C4`.

**Estado:** SOURCE_CANONICAL_SELECTED / RELEASE_NOT_AUTHORIZED.
