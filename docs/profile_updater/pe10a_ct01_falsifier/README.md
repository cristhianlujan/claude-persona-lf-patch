# Falsificador CT01 (solo lectura)

`frozen_inventory_v1.json` congela firma, md5(prosrc) y SECURITY DEFINER de las 12 superficies SQL (v2) (observado 2026-10-27).
`python3 gen_falsifier_sql.py [--negatives]` imprime una consulta de solo lectura para `pg_proc` (schema public).

Resultado esperado hoy: `--negatives` → 12 PASS + FAIL_BODY_DRIFT, FAIL_SIGNATURE_DRIFT, FAIL_MISSING_OR_OWNERLESS. Sin `--negatives` → 12 PASS.
Probado el 2026-10-27 ejecutando el SQL generado contra producción (conector solo lectura).

Limites: `mention_in` es busqueda de texto del nombre en `prosrc` (no distingue llamada de comentario); no cubre ACL ni triggers; aun no corre en CI.
