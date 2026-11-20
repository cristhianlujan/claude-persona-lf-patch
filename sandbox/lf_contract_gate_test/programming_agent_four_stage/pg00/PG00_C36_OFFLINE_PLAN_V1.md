# PG-00.C3.6-A — Plan offline sin autoridad

**Estado: QUALIFICATION_ONLY / NO_GO_WRITE.** Este componente no es un escritor; no genera SQL ni aplica migraciones. No recibe tokens ni abre conexiones a Supabase/GitHub.

## Contrato del prototipo
- `pg00_c36_offline_plan_v1.py` inspecciona un manifiesto candidato, bytes fijados de fuente y release, SHA esperado y un registro de fixtures.
- El SHA `trusted_commit` y los bytes deben proceder de un componente autenticado externo en una implementación futura. **Los parámetros del llamador no autentican nada.**
- El registro `fixture_registry` es deliberadamente sintético. La comprobación de `consumed` solo ensaya escenarios de replay; **no implementa antirreplay transaccional ni ledger.**
- Los hashes SHA-256 actuales se calculan sobre **bytes exactos**, no sobre JSON canónico. La política de canonicalización está pendiente de aprobación; un digest válido aquí no certifica un release.
- Rechaza claves JSON duplicadas, contenido alterado (incluidos nulls), propuestas ajenas a fixture, CHG cambiado, rutas no clasificadas y recibos o aprobaciones añadidos como campos.
- La salida es **siempre** `{"verdict":"BLOCKED","authority":"NONE",...}` incluso para fixture coherente. `EXTERNAL_AUTHENTICATED_AUTHORITY_REQUIRED` es permanente.
- No modificar el trigger `PG00_C3_UNTRUSTED_INSERT_FORBIDDEN` del PR #3365 ni dar rol de publicación al agente.

## Evidencias y límites
- 16 tests sintéticos definidos en `test_pg00_c36_offline_plan_v1.py`.
- Una ejecución de pruebas Python local sobre un prototipo equivalente pasó 16/16 antes de su incorporación a GitHub. **Se requiere ejecución independiente del archivo exacto del nuevo HEAD**; PASE SUCCESS por sí mismo no garantiza que estas pruebas se hayan ejecutado.
- Para pasar de C3.6-A a un escritor real aún se necesita: política formal de identidades/owner/revisor; proveedor autenticado; manifest schema+canonicalización; vínculos propuesta-CHG-revisión-migración; antirreplay transaccional; versión monótona; ruta exclusiva Router+Merge Train y verificación postapply de recibo, ledger y readback.
- Todo lo anterior es una lista de dependencias, no autorización de INSERT.

**Criterio de cierre:** pruebas exact-HEAD, auditoría independiente y decisión documentada de autoridad. Mantener PR draft y prohibición de merge/apply sin gobernanza.
