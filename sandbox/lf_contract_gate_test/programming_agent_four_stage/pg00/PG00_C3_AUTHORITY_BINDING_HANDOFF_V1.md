# PG-00_C3 — Integración de autoridad GitHub / Train (candidata)

## Reutilización verificada
- El verificador existente en `main`: `sandbox/lf_contract_gate_test/train_receipt_verifier/verify_train_receipt.py`. `fetch_live()` abre transacción PostgreSQL `READ ONLY`, consulta evento, ejecución, pasos, migración y PR fusionado; `verify_snapshot()` produce PASS/BLOCKED/FAIL.
- Nuevo `pg00_c3_github_authenticated_source_v1.py`: lectura GitHub API con token, archivo en commit de 40 caracteres, comparación de Git blob SHA, SHA-256 raw y versión. No acepta `source_authenticated` del llamador.
- `pg00_c3_catalog_release_candidate_v2.sql`: lector BD de estado explícitamente no autoritativo, con tabla append-only y prueba PostgreSQL sintética.

## Unión de las tres autoridades (pendiente de implementación productiva)

1. GitHub autenticado devuelve bytes reales de `paulozterra/lf-programming-sandbox/standards/catalog.json` a commit **de 40 caracteres**.
2. Readback BD debe proceder de conexión PostgreSQL autenticada en transacción solo lectura. No aceptar el diccionario `db_readback` de un usuario/API.
3. Verificador Train obtiene `PASS` real de `verify_snapshot(fetch_live(...))` y debe probar que el recibo pertenece **a la migración exacta del catálogo C3**, no a un Train cualquiera.
4. Debe demostrarse que esa migración contiene el archivo fuente del catálogo exacto, con versión, SHA-256 de bytes y commit fijados. El commit SHA del repositorio del catálogo y el commit merge del repositorio de migraciones son **identidades diferentes**. La firma/unión entre ambos no existe todavía.
5. La aprobación de CHG-0007 sigue pendiente (`approved_by:null`, PR #13 en draft). Ningún PASS de digest sustituye esa aprobación.
6. Solo una vez vinculadas las pruebas independientes, una interfaz de autoridad controlada podría devolver `verified=true`. **Ningún módulo candidato disponible lo devuelve.**

## Límites de seguridad

No hay un recibo real del Train para la publicación C3, ni una migración C3 aplicada en Supabase. La prueba de lectura GitHub usa un opener simulado; demuestra parsing e integridad, no prueba una llamada externa real ni autorización de origen de la BD. La API de GitHub requiere un token de lectura en un ejecutor confiable. No registrar ni exponer secretos.

**Estado**: SOURCE_ADAPTER_TESTED / TRAIN_BINDING_UNIMPLEMENTED / C3_NOT_RELEASED / PG01_BLOCK.
