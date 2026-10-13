# Carril RECONCILE: diseño de admisión

## Propósito y alcance

El carril reconcilia fuentes de migración entre Git y el ledger aplicado; no ejecuta SQL. Solo admite versiones POST_CUTOVER (>= 20260808031006) clasificadas por el inventario aprobado como A_RENAME, B_SOURCE_FROM_LEDGER o C_RETIRE. LEGACY queda aceptado por el checkpoint/baseline existente. La paridad de nombres y fuentes debe terminar en PASS.

## Admisión y revisión

Un workflow dedicado `lf-migration-reconcile.yml`, activado por `pull_request_target`, admite solo PR etiquetados explícitamente `ready-to-reconcile` por un maintainer y solo contra el SHA actual de `main`. Un job privilegiado obtiene el CSV de inventario aprobado desde un artefacto inmutable asociado al commit de inventario, comprueba su hash fijado en el PR y compara cada ruta, categoría, versión, nombre y SHA canónico del cambio con una fila del CSV. Filas faltantes, duplicadas, ambiguas o modificadas bloquean el check. El PR no puede aprobarse con D_UNKNOWN.

## Límite de cambios y Train

El verificador calcula el diff completo desde `merge-base(main, PR)` y requiere que cada adición, eliminación o movimiento corresponda exactamente a A/B/C del CSV: A preserva el blob y solo cambia nombre/versión según ledger; B crea el SQL exclusivamente desde `statements` del export aprobado y añade una cabecera de fuente; C mueve el blob intacto fuera de `supabase/migrations` y documenta el reemplazo aplicado y su motivo. No acepta cambios de contenido en A/C, archivos de migración adicionales, ni cambios a workflows o configuración que alteren la admisión.

Antes del merge, el clasificador de nombres y la paridad de fuentes corren sobre el árbol candidato completo y ambos deben dar PASS. El job de inventario y estos checks son de solo lectura; ningún paso invoca `apply_migration` ni escribe en la base. Los archivos de B no pueden entrar en el Train durante ese PR: la admisión verifica las rutas exactas del allowlist y el clasificador del Train no encuentra una migración ejecutable fuera de la lista aprobada.

## PR de retiro

Sí. Un PR de retiro como #2412 debe pasar por RECONCILE: C_RETIRE forma parte de las únicas operaciones aceptadas. #2412 se mantiene en draft hasta la aprobación de Cristhian; una vez disponible el carril, se vuelve a validar en `main` contra un CSV aprobado, no se presume admitido por el workflow fuente-only anterior.
