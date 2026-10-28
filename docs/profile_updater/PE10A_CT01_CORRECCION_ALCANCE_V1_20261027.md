# PE10A_CT01 — Corrección de alcance y de lo que se dijo que estaba avanzado

Fecha: 2026-10-27. No modifica nada de lo ya hecho: corrige lo que podría leerse como más avance del real.

## 1. Qué es CT01 realmente
- CT01 es un **inventario y una prueba de deriva** de 12 funciones SQL y de los archivos de la ruta de actualización. Es trabajo de **auditoría**.
- **No cambia cómo funciona el actualizador de perfiles.** No hay mejora funcional en v0.1, y v0.2 no está activa.
- Avance de plan: 80 de 148 checkpoints DONE (antes 79); en PE10A, 1 de 63.

## 2. Correcciones a lo que figura en el cierre de CT01
| Dónde dice | Qué dice | Qué es en realidad |
|---|---|---|
| `observed.independent_receipt_bound = true` (recibo de aserción de CT01) | Recibo independiente ligado | **Ninguna de las dos rondas de GPT dio PASS.** Ambas dieron `FAIL` por evidencia insuficiente (no por error técnico hallado), sin atestación del proveedor. El `true` significa "el dueño aceptó ese recibo", no "revisión independiente verificada". Admisión: `OWNER_ACCEPTED_WITHOUT_PROVIDER_ATTESTATION` (también escrito en el mismo recibo). |
| `observed.git_merged = true`, `readback_passed = true` | Fusionado y releído | Valores escritos como constantes. `git_merged` es cierto (el recibo está en commit `c7486f4`); `readback_passed` es la **relectura del catálogo dentro de la misma transacción**, no una relectura posterior desde `main` (`readback_scope` lo declara). La relectura posterior sí se hizo a mano tras el Train. |
| "16 pruebas locales, 16/16" | Migración probada | Probada en réplica PG16 con **funciones de prueba (stubs)** para las 12 superficies, copia reducida de `fn_engineering_checkpoint_transition_v1` y sin los triggers de guarda de producción. La igualdad real con producción la comprobó la propia migración dentro del Train (producción es PG 17.6). |
| `falsifier_negative_executed = true` | Negativos ejecutados | Se ejecutaron 3 mutaciones (cuerpo, firma, función fantasma) dentro de la migración. La mutación de SECURITY DEFINER se probó fuera de la migración. |
| Inventario "exhaustivo" | 43 archivos | Enumeración por búsqueda textual del patrón; **sin validación independiente**. Un archivo del updater que no nombre el patrón no aparece. |

## 3. Pendientes reales que siguen abiertos (no cerrados por CT01)
1. Efectos de escritura indirectos de la cadena del router (aplazado a integración).
2. `anon`/`authenticated` tienen EXECUTE sobre `lf_record_creacion_perfil_step_v1`: no se verificó si es explotable.
3. `fn_engineering_action_spec_assertion_contract_v1` devuelve READY con `pass_when` ausente: sin corregir (queda registrado en la base de conocimiento de errores).
4. Edge desplegada `run-creacion-perfil-lf` difiere de GitHub main con la misma etiqueta de versión.
5. CT02 a CT07 y el resto de PE10A (62 de 63) sin cerrar. CT02 tiene solo un borrador parcial (nombres de argumentos), rama `lf/pe10a-ct02-parity-draft-20261027`.

## 4. Decisión del dueño sobre revisión independiente
Para el trabajo **nuevo** no se usará revisión independiente. Lo ya hecho no se toca.
