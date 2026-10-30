# PG-00.C3.6-B1 — Propuesta de esquema de atestación (calificación)

**Estado:** `DESIGN_CANDIDATE / AUTHORITY_NONE / NO_GO_WRITE`.

El análisis del issue #3374 reutiliza GitHub Reviews, contratos C3.5/C3.6-A, Router/Train y el verificador de recibos existente. En ningún caso una forma JSON válida establece que la identidad, la revisión, los permisos o la vigencia sean auténticos.

## Implementado
- `pg00_c36_b1_attestation_shape_v1.py`: estructura estricta de manifiesto y de sobre de revisión, locators, digests, SHA y separación nominal de actores.
- `test_pg00_c36_b1_attestation_shape_v1.py`: 14 regresiones sintéticas; incluye rechazo de campos `null`, supuestas concesiones de autoridad y rutas traversal.
- Todos los resultados conservan `BLOCKED / authority=NONE`. Ni el algoritmo, ni la simulación de reviewers, ni el GitHub provider declarativo implementan autorización real.

## Brechas intencionales
- El esquema de B1 es **provisional**: necesita aprobación de D-C36-01 y D-C36-02 y alineación con el manifiesto canónico aprobado antes de usarse en producción.
- La forma `reviewed_head_sha` no acredita coincidencia con el HEAD del PR o de la migración. Un control independiente debe consultar GitHub y verificar revisión actual, identidad, rol, permisos, expiración/revocación y vínculo al digest y proposal ID. **Los valores JSON no son verificables desde este módulo**.
- `source` del sobre solo es placeholder de fixture; no es atestación autenticada. La separación nominal de reviewers tampoco prueba que los actores tengan autorización.
- La digest de release requiere resolver D-C36-03; los bytes fuente y `catalog_jsonb_sha256` de PostgreSQL podrían tener representaciones distintas.
- `consumed` / replay requieren ledger durable y transacción Train (D-C36-04/05), no un fixture.
- El lector de recibos general `train_receipt_verifier/verify_train_receipt.py` se reutilizará con comprobaciones de contenido del catálogo (D-C36-06); no copiar su lógica aquí.

## Próxima decisión
Validar B1 independientemente con los 14 tests y casos adversariales nuevos. El owner/gobernanza debe resolver D-C36-01..06 en el issue #3374. No habilitar INSERT, no modificar #3365 ni permitir cualquier bypass del guard de escritura. Mantener PR draft.
