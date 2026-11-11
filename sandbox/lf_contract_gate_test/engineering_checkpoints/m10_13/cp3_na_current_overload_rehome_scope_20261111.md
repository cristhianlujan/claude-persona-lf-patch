# LF IG M10.13 CP3 — Lote de desconexión 01 / NA Curator
**Estado inicial:** candidato, NO aplicado.

## Alcance autorizado
Reemplazar una dependencia no congelada:
- Llamador: `programacion.fn_input_governance_bootstrap_classify_v1_ctx(integer,text,bigint,jsonb)` (ACTIVE_VNEXT, fuente viva).
- Callee legacy: `programacion.fn_input_na_positive_authority_v512_cached_v1(text,integer,bigint,jsonb)` (M10.4 congelado).
- Rehome: sobrecarga de la función activa existente `programacion.fn_input_na_positive_authority_v512(text,integer,bigint,jsonb)`, con el grafo recibido y cuerpo funcional original; no llama a funciones M10.4.
- Mantener la función activa de 3 argumentos, los 26 cuerpos congelados, el Router, IG Edge, y las demás funciones.

## Contrato de pruebas y admisión
1. Readback vigente de fuentes `pg_proc`, fingerprints, freeze y checkpoint.
2. Test real de 47 pares de NA en RUN 951, comparación JSON exacta; fail-closed si no coincide.
3. Cambio de solo un call site en la fuente viva de `bootstrap_classify_v1_ctx`, sin cambiar el grafo ni el resto del cuerpo.
4. Prueba negativa de reintroducción, ACL restringida a los consumidores existentes, `CREATE OR REPLACE` inmutable en freeze.
5. Todo bajo `ACTUALIZACION_DB_LF` / `DB_WRITE_TRANSPORT` / LF Migration Merge Train exact-head.
6. Relectura de source + permiso + rutas y snapshot de checkpoint tras promoción.

**No cerrar CP3:** quedan otros caminos legacy y ausencia de consumidores externos por acreditar; esta es solo la primera desconexión real.
