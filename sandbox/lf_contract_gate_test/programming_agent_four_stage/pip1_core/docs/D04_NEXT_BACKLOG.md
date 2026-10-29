# Backlog siguiente lote

1. **B1 (BLOQUEANTE)** Materializar JSON exacto por GitHub API/checkout de solo lectura, ejecutar `verify_exact_inventory.py` y guardar SHA-256 completo + digest + paridad.
2. **B2 (BLOQUEANTE)** Ejecutar tests de mutación sobre copias temporales del JSON exacto recuperado y publicar salida reproducible.
3. **B3 (BLOQUEANTE)** Efectuar review independiente con Claude por diff exacto y cerrar defectos con regresión.
4. **B4 (BLOQUEANTE antes de PR)** Verificar clasificación, manifest de changeset, PASE plan exacto con checkout completo LF sin realizar push.
5. **B5 (DECISIÓN OWNER)** Resolver contrato de prueba de prerequisito PG-00 certificado y autoridad de N/A; no sustituir con simulaciones.
6. **B6 (DISEÑO POSTERIOR)** Definir puerto Verifier de ledger con identidad exacta, sin implementarlo ni conectarlo en este lote.
