# PG-00_C3 — Integración exacta de fuente/Train: estado y puerta restante

**Estado:** CANDIDATE_NOT_RELEASED. Ninguna de estas pruebas autoriza PG-01_C4 ni PG-02.

## Componentes probados
- `pg00_c3_github_authenticated_source_v1.py`: lectura de archivo GitHub por API con commit de 40 hex, token, SHA del blob Git y SHA-256 del archivo. Pruebas con opener simulado: 6 PASS.
- `pg00_c3_catalog_release_candidate_v2.sql`: catálogo append-only con lectura y restricciones; siete RED/GREEN PostgreSQL 17.6 sintéticos PASS.
- `pg00_c3_train_binding_candidate_v1.py`: lazo lógico entre `catalog_version`, fuente exacta, digest, ruta y SHA de migración, execution_id y merge SHA. Diez casos (nueve rechazos + uno coincidente aún BLOQUEADO) PASS.
- Reutilizar el verificador existente de `main`: `sandbox/lf_contract_gate_test/train_receipt_verifier/verify_train_receipt.py`; no reemplazarlo por flags de un llamador.

## Bloqueos concretos para una prueba positiva de autoridad
1. El CHG-0007 (PR #13 del repo canónico) permanece draft y sin aprobación específica: no fabricar `approved_by`.
2. `pg00_c3_catalog_release_candidate_v2.sql` es SQL de ensayo que termina en ROLLBACK. Falta migración gobernada en `supabase/migrations` después de aprobación, revisión exact-head y PASE.
3. Falta definir y materializar una unión **en el contenido de la migración real** entre commit+SHA256 de `standards/catalog.json` y bytes de la migración. El diccionario `release_manifest` candidato es datos sin autenticación; no basta con que coincida.
4. Falta aplicar la migración vía Merge Train; el recibo Train auténtico debe cotejarse con el verificador de `main` sobre DB READ ONLY + GitHub PR merged y ledger de migraciones.
5. El registro `transversal` debe leerse con conexión de auditoría READ ONLY, no suministrado por una API arbitraria.
6. Solo entonces agregar un módulo de admisión independiente con resultado positivo y negativas de replay, cambio de commit, downgrade, PR diferente, digest/raw y divergencia BD.

## Advertencia de seguridad
El `bind_c3_train` acepta estructuras de ensayo y por diseño **siempre devuelve BLOCK**. No utilizar el valor `result=PASS` aportado por un llamador como señal de autoridad. No promover este archivo a producción mientras no existan las seis evidencias anteriores.

## Próximo transporte
Cuando el CHG esté revisado/aprobado, abrir PR de migración propio sobre `main` actualizado, con ensayo PostgreSQL RED/GREEN del payload exacto, PASE, Train y lectura posterior. Conservar #3325 draft como paquete candidato o cerrarlo después del reemplazo gobernado; nunca hacer merge del catálogo paralelo.
