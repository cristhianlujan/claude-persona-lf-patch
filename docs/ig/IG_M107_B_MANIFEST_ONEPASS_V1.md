# IG M10.7 / Lote B — comprobación doble desde un manifiesto (candidato de integración)

## Cambio acotado
La ruta vigente realiza la lectura completa de fuentes por continuidad y otra vez por el guard final. Son controles distintos: identidad del manifiesto frente a JSONB completo + hash.

El candidato incorpora:
- `fn_ig_m107_currentness_from_manifest_v1(run_id,manifest)`: mismo cuerpo de la autoridad vigente de currentness, salvo que consume el manifiesto recibido.
- `fn_ig_m107_bundle_from_manifest_v1(run_id,manifest)`: devuelve el envelope G1 equivalente y un veredicto adicional de manifiesto completo; el parámetro no puede venir de clientes.
- `fn_ig_m107_manifest_guard_bundle_v1(run_id)`: única construcción de manifiesto dentro de la invocación, alimenta los dos controles anteriores.

Todo es aditivo con acceso exclusivo al propietario backend. **Ningún trigger actual, el Validator, Curator ni las políticas de currentness cambia.** Se evita por ahora guardar resultados entre sentencias y entre triggers: el G2B disponible verificó un *fixture*, no todos los escritores reales de fuentes.

## Pruebas en Migration Train
Comparar para el run histórico 933 el JSONB completo de G1 actual con el nuevo bundle; comparar resultado de manifiesto completo; inyectar un manifiesto fijado positivo y dos negativos artificiales (deriva de lifecycle ignorada por identidad; corrupción de SHA detectada). Comprobar una sola referencia de construcción de manifiesto en el wrapper y permisos cerrados.

La prueba histórica puede indicar STALE y no equivale a una corrida viva ni certifica reducción real del Validator. La reducción del número de construcciones es estructural **dentro del helper**: no hay ahorro end-to-end probado.

## Siguiente condición de B
Para sustituir guards actuales se requerirá evidencia real de coherencia concurrente entre funciones/UPDATE (no solo G2B fixture), equivalencia completa y mejora medible. No inventar un cache global ni quitar validaciones. CP3–CP5 siguen pendientes.
